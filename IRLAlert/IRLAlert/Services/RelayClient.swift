import Foundation
import os.log

/// Lightweight client for the relay server (Phase 5A).
@MainActor
final class RelayClient {

    static let shared = RelayClient()

    private let logger = Logger(subsystem: "com.irlalert.app", category: "RelayClient")
    private let settings = AppSettings.shared

    private var baseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "relayBaseURL"),
           let url = URL(string: override) {
            return url
        }
        return URL(string: "http://localhost:3000")!
    }

    private var lastPresenceState: Bool?

    func registerIfPossible(deviceToken: String, services: [ServiceIdentifier]) async {
        guard settings.pushNotificationsEnabled else { return }

        let credentials = ConnectionManager.shared.relayCredentialPayloads()
        let payload: [String: Any] = [
            "userId": settings.relayUserId,
            "deviceToken": deviceToken,
            "services": services.map { $0.rawValue },
            "credentials": credentials
        ]

        await post(path: "/register", body: payload)
    }

    func updatePresence(directConnectionActive: Bool) async {
        guard settings.pushNotificationsEnabled else { return }
        guard let deviceToken = PushNotificationManager.shared.deviceToken else { return }

        if lastPresenceState == directConnectionActive { return }
        lastPresenceState = directConnectionActive

        let payload: [String: Any] = [
            "userId": settings.relayUserId,
            "deviceToken": deviceToken,
            "directConnectionActive": directConnectionActive
        ]

        await post(path: "/presence", body: payload)
    }

    // MARK: - Networking

    private func post(path: String, body: [String: Any]) async {
        guard let url = URL(string: path, relativeTo: baseURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                logger.warning("Relay server returned status \(http.statusCode)")
            }
        } catch {
            logger.error("Relay request failed: \(error.localizedDescription)")
        }
    }
}
