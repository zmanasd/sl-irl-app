import Foundation
import Combine
import SocketIO
import os.log

/// Streamlabs integration service.
///
/// Connects to the Streamlabs Socket API via Socket.IO to receive real-time
/// alert events (donations, follows, subscriptions, bits, hosts, raids).
///
/// Supports two connection modes:
/// 1. **Socket Token** — obtained from the Streamlabs dashboard API Settings
/// 2. **Browser Source URL** — the overlay URL contains an embedded token
///
/// All events are parsed into the unified `AlertEvent` model and published
/// for consumption by the `ConnectionManager` and `AlertQueueManager`.
final class StreamlabsSocketService: @unchecked Sendable, AlertServiceProtocol {
    
    // MARK: - Protocol Conformance
    
    let serviceIdentifier: ServiceIdentifier = .streamlabs
    var autoReconnectEnabled: Bool = true
    
    var connectionStatePublisher: AnyPublisher<ConnectionState, Never> {
        connectionStateSubject.eraseToAnyPublisher()
    }
    
    var connectionState: ConnectionState {
        connectionStateSubject.value
    }
    
    var alertPublisher: AnyPublisher<AlertEvent, Never> {
        alertSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Private State
    
    private let connectionStateSubject = CurrentValueSubject<ConnectionState, Never>(.disconnected)
    private let alertSubject = PassthroughSubject<AlertEvent, Never>()
    private let logger = Logger(subsystem: "com.irlalert.app", category: "StreamlabsSocket")
    
    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var currentToken: String?
    
    // Reconnect state
    private var reconnectAttempts = 0
    private let maxReconnectDelay: TimeInterval = 30.0
    private var reconnectTask: Task<Void, Never>?
    
    // Supported Streamlabs event types
    private static let supportedTypes: Set<String> = [
        "donation", "follow", "subscription", "host", "raid", "bits",
        "subgift", "submysterygift"
    ]
    
    // MARK: - Init
    
    init() {}
    
    deinit {
        disconnect()
    }
    
    // MARK: - Connection
    
    func connect(with credentials: ServiceCredentials) async throws {
        guard connectionState != .connected else {
            throw AlertServiceError.alreadyConnected
        }
        
        let token: String
        switch credentials {
        case .socketToken(let t):
            token = t
        case .browserSourceURL(let url):
            token = try Self.extractToken(from: url)
        case .oauthToken:
            throw AlertServiceError.unsupportedCredentialType
        }
        
        guard !token.isEmpty else {
            throw AlertServiceError.invalidCredentials("Socket token is empty")
        }
        
        currentToken = token
        reconnectAttempts = 0
        
        connectionStateSubject.send(.connecting)
        logger.info("Connecting to Streamlabs with token: \(token.prefix(8))...")
        
        setupSocket(token: token)
        socket?.connect()
    }
    
    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        autoReconnectEnabled = false
        socket?.disconnect()
        manager?.disconnect()
        manager = nil
        socket = nil
        currentToken = nil
        connectionStateSubject.send(.disconnected)
        logger.info("Disconnected from Streamlabs")
    }
    
    // MARK: - Socket Setup
    
    private func setupSocket(token: String) {
        // Clean up previous connection if any
        socket?.removeAllHandlers()
        manager?.disconnect()
        
        let url = URL(string: "https://sockets.streamlabs.com")!
        
        manager = SocketManager(socketURL: url, config: [
            .log(false),
            .compress,
            .forceWebsockets(true),
            .reconnects(false), // We handle reconnection ourselves
            .connectParams(["token": token])
        ])
        
        socket = manager?.defaultSocket
        
        // --- Connection lifecycle ---
        
        socket?.on(clientEvent: .connect) { [weak self] _, _ in
            guard let self else { return }
            self.reconnectAttempts = 0
            self.connectionStateSubject.send(.connected)
            self.logger.info("✅ Connected to Streamlabs socket")
        }
        
        socket?.on(clientEvent: .disconnect) { [weak self] _, _ in
            guard let self else { return }
            self.logger.warning("⚠️ Disconnected from Streamlabs socket")
            if self.autoReconnectEnabled {
                self.scheduleReconnect()
            } else {
                self.connectionStateSubject.send(.disconnected)
            }
        }
        
        socket?.on(clientEvent: .error) { [weak self] data, _ in
            guard let self else { return }
            self.logger.error("❌ Streamlabs socket error: \(String(describing: data))")
            if self.autoReconnectEnabled {
                self.scheduleReconnect()
            } else {
                self.connectionStateSubject.send(.failed)
            }
        }
        
        // --- Alert event handler ---
        
        socket?.on("event") { [weak self] data, _ in
            guard let self else { return }
            self.handleEvent(data: data)
        }
    }
    
    // MARK: - Event Parsing
    
    /// Parse incoming Streamlabs Socket.IO "event" payload into `AlertEvent`s.
    ///
    /// Streamlabs event structure:
    /// ```json
    /// {
    ///   "type": "donation",
    ///   "for": "streamlabs",
    ///   "message": [
    ///     {
    ///       "name": "UserName",
    ///       "amount": "5.00",
    ///       "formatted_amount": "$5.00",
    ///       "message": "Great stream!",
    ///       "sound_url": "https://...",
    ///       ...
    ///     }
    ///   ]
    /// }
    /// ```
    private func handleEvent(data: [Any]) {
        guard let dict = data.first as? [String: Any] else {
            logger.warning("Received event with unexpected structure")
            return
        }
        
        guard let typeString = dict["type"] as? String else {
            logger.debug("Event missing 'type' field")
            return
        }
        
        let normalizedType = typeString.lowercased()
        guard Self.supportedTypes.contains(normalizedType) else {
            logger.debug("Ignoring unsupported event type: \(typeString)")
            return
        }
        
        guard let messages = dict["message"] as? [[String: Any]] else {
            logger.debug("Event missing 'message' array")
            return
        }
        
        for payload in messages {
            if let alertEvent = parsePayload(payload, type: normalizedType) {
                logger.info("📢 Alert: \(alertEvent.type.rawValue) from \(alertEvent.username)")
                alertSubject.send(alertEvent)
            }
        }
    }
    
    /// Parse a single message payload into an `AlertEvent`.
    private func parsePayload(_ payload: [String: Any], type: String) -> AlertEvent? {
        let username = payload["name"] as? String ?? "Unknown"
        let message = payload["message"] as? String
        let soundURLString = payload["sound_url"] as? String
        let soundURL = soundURLString.flatMap { URL(string: $0) }
        
        // Parse amount — can be string or number from Streamlabs
        let amount: Double? = {
            if let numAmount = payload["amount"] as? Double { return numAmount }
            if let numAmount = payload["amount"] as? Int { return Double(numAmount) }
            if let strAmount = payload["amount"] as? String { return Double(strAmount) }
            return nil
        }()
        
        let formattedAmount = payload["formatted_amount"] as? String
        
        // Map Streamlabs type strings to our AlertType enum
        let alertType: AlertType
        switch type {
        case "donation":
            alertType = .donation
        case "follow":
            alertType = .follow
        case "subscription", "subgift", "submysterygift":
            alertType = .subscription
        case "bits":
            alertType = .bits
        case "host":
            alertType = .host
        case "raid":
            alertType = .raid
        default:
            logger.debug("No AlertType mapping for: \(type)")
            return nil
        }
        
        return AlertEvent(
            type: alertType,
            username: username,
            message: message,
            amount: amount,
            formattedAmount: formattedAmount,
            soundURL: soundURL,
            source: .streamlabs
        )
    }
    
    // MARK: - Token Extraction
    
    /// Extract the socket token from a Streamlabs Browser Source overlay URL.
    ///
    /// Example URL formats:
    /// - `https://streamlabs.com/alert-box/v3/ABCDEF123456`
    /// - `https://streamlabs.com/widgets/alert-box/v3/ABCDEF123456`
    /// - URLs with `?token=ABCDEF123456` query parameter
    static func extractToken(from url: URL) throws -> String {
        // Method 1: Check for explicit ?token= parameter
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let tokenItem = components.queryItems?.first(where: { $0.name == "token" }),
           let token = tokenItem.value, !token.isEmpty {
            return token
        }
        
        // Method 2: Extract from path — last path component is typically the token
        let path = url.path
        let segments = path.split(separator: "/").map(String.init)
        
        // The token is usually the last segment, and it's a long alphanumeric string
        if let lastSegment = segments.last,
           lastSegment.count >= 10,
           lastSegment.allSatisfy({ $0.isLetter || $0.isNumber }) {
            return lastSegment
        }
        
        throw AlertServiceError.tokenExtractionFailed(
            "Could not extract socket token from URL: \(url.absoluteString)"
        )
    }
    
    // MARK: - Reconnection (Exponential Backoff)
    
    private func scheduleReconnect() {
        connectionStateSubject.send(.reconnecting)
        reconnectTask?.cancel()
        
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts - 1)), maxReconnectDelay)
        
        logger.info("Scheduling reconnect attempt #\(self.reconnectAttempts) in \(delay)s")
        
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, let token = self.currentToken else { return }
            
            self.logger.info("Reconnecting to Streamlabs (attempt #\(self.reconnectAttempts))...")
            self.setupSocket(token: token)
            self.socket?.connect()
        }
    }
}
