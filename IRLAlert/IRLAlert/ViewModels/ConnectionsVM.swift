import Foundation
import Combine

/// ViewModel for the Connections screen.
/// Manages service connections and credential input.
@MainActor
final class ConnectionsVM: ObservableObject {
    
    // MARK: - Published State
    
    /// Per-service connection states
    @Published private(set) var serviceStates: [ServiceIdentifier: ConnectionState] = [:]
    
    /// Whether any service is connected
    @Published private(set) var hasActiveConnection = false
    
    /// Number of active services
    @Published private(set) var activeServiceCount = 0
    
    /// Last error message for UI display
    @Published private(set) var lastError: String?
    
    /// User input fields per service
    @Published var streamlabsInput: String = ""
    
    /// Loading state per service
    @Published var isConnecting: [ServiceIdentifier: Bool] = [:]
    
    // MARK: - Dependencies
    
    private let connectionManager = ConnectionManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        bindConnectionManager()
    }
    
    // MARK: - Public API
    
    /// Connect Streamlabs using whatever the user entered (URL or raw token).
    func connectStreamlabs() async {
        let input = streamlabsInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        
        isConnecting[.streamlabs] = true
        lastError = nil
        
        let credentials: ServiceCredentials
        if input.lowercased().hasPrefix("http") {
            guard let url = URL(string: input) else {
                lastError = "Invalid URL format."
                isConnecting[.streamlabs] = false
                return
            }
            credentials = .browserSourceURL(url)
        } else {
            credentials = .socketToken(input)
        }
        
        await connectionManager.connect(.streamlabs, with: credentials)
        isConnecting[.streamlabs] = false
        
        if let error = connectionManager.lastError {
            lastError = error
        } else {
            streamlabsInput = "" // Clear on success
        }
    }
    
    /// Disconnect a specific service.
    func disconnect(_ serviceId: ServiceIdentifier) {
        connectionManager.disconnect(serviceId)
        lastError = nil
    }
    
    /// Disconnect all services.
    func disconnectAll() {
        connectionManager.disconnectAll()
        lastError = nil
    }
    
    /// Get connection state for a specific service.
    func state(for serviceId: ServiceIdentifier) -> ConnectionState {
        serviceStates[serviceId] ?? .disconnected
    }
    
    // MARK: - Bindings
    
    private func bindConnectionManager() {
        connectionManager.$serviceStates
            .assign(to: &$serviceStates)
        
        connectionManager.$hasActiveConnection
            .assign(to: &$hasActiveConnection)
        
        connectionManager.$activeServiceCount
            .assign(to: &$activeServiceCount)
        
        connectionManager.$lastError
            .assign(to: &$lastError)
    }
}
