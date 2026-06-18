import Foundation
import Combine
import AuthenticationServices

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

    /// Complete Sign in with Apple and store the relay beta session.
    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        lastError = nil

        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityToken = credential.identityToken,
                  let identityTokenString = String(data: identityToken, encoding: .utf8) else {
                lastError = "Apple identity token was not available."
                return
            }

            let fullName = credential.fullName
                .map(PersonNameComponentsFormatter().string(from:))
            await RelayClient.shared.storeAppleIdentityToken(identityTokenString, fullName: fullName)
            if let error = RelayClient.shared.lastAuthError {
                lastError = error
            }

        case .failure(let error):
            lastError = error.localizedDescription
        }
    }

    /// Disconnect Twitch from the authenticated relay account.
    func disconnectTwitch() async {
        lastError = nil
        await RelayClient.shared.disconnectTwitch()
        if let error = RelayClient.shared.lastAccountActionError {
            lastError = error
        }
    }

    /// Delete the authenticated relay account and clear the local session.
    func deleteRelayAccount() async {
        lastError = nil
        await RelayClient.shared.deleteRelayAccount()
        if let error = RelayClient.shared.lastAccountActionError {
            lastError = error
        }
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
