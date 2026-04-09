import Foundation
import Combine

// MARK: - Connection State

/// Represents the lifecycle state of an alert service connection.
enum ConnectionState: String, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed
    
    var isActive: Bool { self == .connected }
    var displayName: String { rawValue.capitalized }
}

// MARK: - Service Identifier

/// Unique identifier for each supported alert service.
enum ServiceIdentifier: String, CaseIterable, Identifiable, Codable, Sendable {
    case streamlabs
    case streamElements = "stream_elements"
    case twitchNative = "twitch_native"
    case soundAlerts = "sound_alerts"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .streamlabs: return "Streamlabs"
        case .streamElements: return "StreamElements"
        case .twitchNative: return "Twitch Native"
        case .soundAlerts: return "SoundAlerts"
        }
    }
    
    /// Map to the corresponding AlertSource on AlertEvent
    var alertSource: AlertEvent.AlertSource {
        switch self {
        case .streamlabs: return .streamlabs
        case .streamElements: return .streamElements
        case .twitchNative: return .twitchNative
        case .soundAlerts: return .soundAlerts
        }
    }
}

// MARK: - Connection Credentials

/// Encapsulates the authentication details needed to connect to a service.
enum ServiceCredentials: Sendable {
    /// Socket API token obtained from the service dashboard
    case socketToken(String)
    /// OAuth access token obtained through ASWebAuthenticationSession
    case oauthToken(String)
    /// Browser Source URL that embeds a socket token
    case browserSourceURL(URL)
}

// MARK: - Alert Service Protocol

/// Contract for all streaming alert service integrations.
/// Each service (Streamlabs, StreamElements, etc.) conforms to this protocol.
protocol AlertServiceProtocol: AnyObject, Sendable {
    /// Unique identifier for this service type
    var serviceIdentifier: ServiceIdentifier { get }
    
    /// Current connection state — published for UI observation
    var connectionStatePublisher: AnyPublisher<ConnectionState, Never> { get }
    
    /// Current connection state (synchronous read)
    var connectionState: ConnectionState { get }
    
    /// Stream of parsed alert events from this service
    var alertPublisher: AnyPublisher<AlertEvent, Never> { get }
    
    /// Connect to the service with the given credentials.
    func connect(with credentials: ServiceCredentials) async throws
    
    /// Gracefully disconnect from the service.
    func disconnect()
    
    /// Whether auto-reconnection is enabled
    var autoReconnectEnabled: Bool { get set }
}

// MARK: - Service Errors

/// Errors that can occur during service connection or communication.
enum AlertServiceError: LocalizedError, Sendable {
    case invalidCredentials(String)
    case connectionFailed(String)
    case parseError(String)
    case unsupportedCredentialType
    case tokenExtractionFailed(String)
    case alreadyConnected
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials(let detail): return "Invalid credentials: \(detail)"
        case .connectionFailed(let detail): return "Connection failed: \(detail)"
        case .parseError(let detail): return "Parse error: \(detail)"
        case .unsupportedCredentialType: return "Unsupported credential type for this service"
        case .tokenExtractionFailed(let detail): return "Could not extract token: \(detail)"
        case .alreadyConnected: return "Service is already connected"
        }
    }
}
