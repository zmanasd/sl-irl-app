import Foundation
import Combine
import os.log

/// Orchestrates all alert service connections and routes events into the `AlertQueueManager`.
///
/// Responsibilities:
/// - Manages the lifecycle of multiple `AlertServiceProtocol` instances
/// - Aggregates connection health status across all services
/// - Routes parsed alert events into the alert queue
/// - Persists connection credentials for quick reconnection
/// - Coordinates with `DisconnectMonitor` for offline notifications
@MainActor
final class ConnectionManager: ObservableObject {
    
    static let shared = ConnectionManager()
    
    // MARK: - Published State
    
    /// Per-service connection state for UI display
    @Published private(set) var serviceStates: [ServiceIdentifier: ConnectionState] = [:]
    
    /// Whether any service is currently connected
    @Published private(set) var hasActiveConnection: Bool = false
    
    /// Total number of active (connected) services
    @Published private(set) var activeServiceCount: Int = 0
    
    /// Last error message for user-facing display
    @Published private(set) var lastError: String?
    
    // MARK: - Dependencies
    
    private let alertQueue = AlertQueueManager.shared
    private let eventStore = EventStore.shared
    private let disconnectMonitor = DisconnectMonitor.shared
    private let logger = Logger(subsystem: "com.irlalert.app", category: "ConnectionManager")
    
    // MARK: - Internal State
    
    private var services: [ServiceIdentifier: any AlertServiceProtocol] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    /// Persisted credentials keyed by service ID
    private let credentialsKey = "savedServiceCredentials"
    
    private init() {
        // Initialize all known services
        registerService(StreamlabsSocketService())
    }
    
    // MARK: - Service Registration
    
    /// Register a new alert service for management.
    private func registerService(_ service: some AlertServiceProtocol) {
        let id = service.serviceIdentifier
        services[id] = service
        serviceStates[id] = .disconnected
        
        // Subscribe to connection state changes
        service.connectionStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self else { return }
                self.serviceStates[id] = newState
                self.updateAggregateState()
                
                // Notify disconnect monitor
                if newState == .disconnected || newState == .reconnecting {
                    self.disconnectMonitor.serviceDidDisconnect(id)
                } else if newState == .connected {
                    self.disconnectMonitor.serviceDidConnect(id)
                }
            }
            .store(in: &cancellables)
        
        // Subscribe to alert events → route to queue + event store
        service.alertPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                self.alertQueue.enqueue(event)
                Task { await self.eventStore.add(event) }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public API
    
    /// Connect a specific service with the given credentials.
    func connect(_ serviceId: ServiceIdentifier, with credentials: ServiceCredentials) async {
        guard let service = services[serviceId] else {
            logger.error("Service not registered: \(serviceId.rawValue)")
            lastError = "Service \(serviceId.displayName) is not available."
            return
        }
        
        do {
            service.autoReconnectEnabled = true
            try await service.connect(with: credentials)
            saveCredentials(credentials, for: serviceId)
            if AppSettings.shared.pushNotificationsEnabled,
               let deviceToken = PushNotificationManager.shared.deviceToken {
                Task {
                    await RelayClient.shared.registerIfPossible(
                        deviceToken: deviceToken,
                        services: registeredServiceIdentifiers()
                    )
                }
            }
            lastError = nil
            logger.info("Successfully initiated connection to \(serviceId.rawValue)")
        } catch {
            logger.error("Failed to connect \(serviceId.rawValue): \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }
    
    /// Disconnect a specific service.
    func disconnect(_ serviceId: ServiceIdentifier) {
        guard let service = services[serviceId] else { return }
        service.disconnect()
        clearCredentials(for: serviceId)
        logger.info("Disconnected \(serviceId.rawValue)")
    }
    
    /// Disconnect all services.
    func disconnectAll() {
        for (id, service) in services {
            service.disconnect()
            clearCredentials(for: id)
        }
        logger.info("All services disconnected")
    }
    
    /// Attempt to reconnect all services using saved credentials.
    func reconnectSaved() async {
        for (id, _) in services {
            if let creds = loadCredentials(for: id) {
                logger.info("Restoring connection for \(id.rawValue)")
                await connect(id, with: creds)
            }
        }
    }
    
    /// Get the current state of a specific service.
    func state(for serviceId: ServiceIdentifier) -> ConnectionState {
        serviceStates[serviceId] ?? .disconnected
    }

    /// All known service identifiers registered with the manager.
    func registeredServiceIdentifiers() -> [ServiceIdentifier] {
        Array(services.keys)
    }

    /// Serialized credentials for relay registration.
    func relayCredentialPayloads() -> [[String: String]] {
        var payloads: [[String: String]] = []

        for serviceId in services.keys {
            guard let credentials = loadCredentials(for: serviceId) else { continue }

            switch credentials {
            case .socketToken(let token):
                payloads.append([
                    "service": serviceId.rawValue,
                    "type": "socket",
                    "value": token
                ])
            case .oauthToken(let token):
                payloads.append([
                    "service": serviceId.rawValue,
                    "type": "oauth",
                    "value": token
                ])
            case .browserSourceURL(let url):
                if serviceId == .streamlabs, let token = try? StreamlabsSocketService.extractToken(from: url) {
                    payloads.append([
                        "service": serviceId.rawValue,
                        "type": "socket",
                        "value": token
                    ])
                } else {
                    payloads.append([
                        "service": serviceId.rawValue,
                        "type": "url",
                        "value": url.absoluteString
                    ])
                }
            }
        }

        return payloads
    }
    
    /// Clear the last error message.
    func clearLastError() {
        lastError = nil
    }
    
    /// Set a custom error message from the UI.
    func setLastError(_ message: String) {
        lastError = message
    }
    
    // MARK: - Aggregate State
    
    private func updateAggregateState() {
        let connected = serviceStates.values.filter { $0 == .connected }
        activeServiceCount = connected.count
        hasActiveConnection = !connected.isEmpty
        PiPManager.shared.updateStatus(isConnected: hasActiveConnection)
    }
    
    // MARK: - Credential Persistence (Keychain-ready, UserDefaults for now)
    
    private func saveCredentials(_ credentials: ServiceCredentials, for serviceId: ServiceIdentifier) {
        let key = "\(credentialsKey)_\(serviceId.rawValue)"
        switch credentials {
        case .socketToken(let token):
            UserDefaults.standard.set("socket:\(token)", forKey: key)
        case .browserSourceURL(let url):
            UserDefaults.standard.set("url:\(url.absoluteString)", forKey: key)
        case .oauthToken(let token):
            UserDefaults.standard.set("oauth:\(token)", forKey: key)
        }
    }
    
    private func loadCredentials(for serviceId: ServiceIdentifier) -> ServiceCredentials? {
        let key = "\(credentialsKey)_\(serviceId.rawValue)"
        guard let stored = UserDefaults.standard.string(forKey: key) else { return nil }
        
        if stored.hasPrefix("socket:") {
            return .socketToken(String(stored.dropFirst(7)))
        } else if stored.hasPrefix("url:"), let url = URL(string: String(stored.dropFirst(4))) {
            return .browserSourceURL(url)
        } else if stored.hasPrefix("oauth:") {
            return .oauthToken(String(stored.dropFirst(6)))
        }
        return nil
    }
    
    private func clearCredentials(for serviceId: ServiceIdentifier) {
        let key = "\(credentialsKey)_\(serviceId.rawValue)"
        UserDefaults.standard.removeObject(forKey: key)
    }
}
