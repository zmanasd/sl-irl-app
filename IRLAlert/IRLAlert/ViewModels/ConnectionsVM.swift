import Foundation
import Combine

/// ViewModel for the Connections screen.
/// Manages Twitch relay setup and proof actions.
@MainActor
final class ConnectionsVM: ObservableObject {
    
    // MARK: - Published State
    
    /// Last error message for UI display
    @Published private(set) var lastError: String?
    
    // MARK: - Public API
    
    /// Clear the current error message
    func clearError() {
        lastError = nil
    }

    /// Request push registration and register this device with the relay for Twitch-native MVP alerts.
    func registerDeviceForMVP() async {
        lastError = nil
        await PushNotificationManager.shared.handleUserToggle(enabled: true)

        guard let deviceToken = PushNotificationManager.shared.deviceToken else {
            lastError = "APNs token is not available yet. Accept notifications and try again."
            return
        }

        await RelayClient.shared.registerIfPossible(
            deviceToken: deviceToken,
            services: [.twitchNative]
        )

        if let error = RelayClient.shared.lastRegistrationError {
            lastError = error
        }
    }

    /// Ask the relay for a Twitch OAuth URL. The view owns opening the URL.
    func createTwitchOAuthURL() async -> URL? {
        lastError = nil
        let url = await RelayClient.shared.createTwitchOAuthURL()
        if url == nil {
            lastError = RelayClient.shared.lastTwitchOAuthError ?? "Could not start Twitch OAuth."
        }
        return url
    }

    /// Send a correlated APNs proof alert through the relay.
    func sendRelayTestAlert() async {
        lastError = nil
        await RelayClient.shared.sendRelayTestAlert()
        if let error = RelayClient.shared.lastTestAlertError {
            lastError = error
        }
    }

    /// Fetch the strict per-user relay readiness gate used by the proof harness.
    func refreshRelayReadiness() async {
        lastError = nil
        await RelayClient.shared.fetchReadiness()
        if let error = RelayClient.shared.lastReadinessError {
            lastError = error
        }
    }

    /// Fetch safe relay diagnostics for proof-run cross-checking.
    func refreshRelayDiagnostics() async {
        lastError = nil
        await RelayClient.shared.fetchDiagnostics()
        if let error = RelayClient.shared.lastDiagnosticsError {
            lastError = error
        }
    }
}
