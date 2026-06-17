import Combine
import Foundation
import os.log

/// Lightweight client for the Twitch/APNs relay server.
@MainActor
final class RelayClient: ObservableObject {

    static let shared = RelayClient()

    @Published private(set) var lastRegistrationAttemptAt: Date?
    @Published private(set) var lastRegistrationSucceededAt: Date?
    @Published private(set) var lastRegistrationStatusCode: Int?
    @Published private(set) var lastRegistrationError: String?
    @Published private(set) var isSendingTestAlert = false
    @Published private(set) var lastTestAlertCorrelationId: String?
    @Published private(set) var lastTestAlertStatusCode: Int?
    @Published private(set) var lastTestAlertError: String?
    @Published private(set) var isStartingTwitchOAuth = false
    @Published private(set) var lastTwitchOAuthStatusCode: Int?
    @Published private(set) var lastTwitchOAuthError: String?
    @Published private(set) var lastTwitchOAuthStartedAt: Date?
    @Published private(set) var isFetchingReadiness = false
    @Published private(set) var lastReadinessStatusCode: Int?
    @Published private(set) var lastReadinessError: String?
    @Published private(set) var lastReadinessFetchedAt: Date?
    @Published private(set) var lastReadinessSummary: String = "Not fetched"
    @Published private(set) var lastUserReadinessSummary: String = "Not checked"
    @Published private(set) var lastUserReadinessOk = false
    @Published private(set) var isFetchingDiagnostics = false
    @Published private(set) var lastDiagnosticsStatusCode: Int?
    @Published private(set) var lastDiagnosticsError: String?
    @Published private(set) var lastDiagnosticsFetchedAt: Date?
    @Published private(set) var lastDiagnosticsSummary: String = "Not fetched"
    @Published private(set) var lastDiagnosticsApnsReadiness: String = "Unknown"
    @Published private(set) var lastDiagnosticsTwitchOAuthReadiness: String = "Unknown"
    @Published private(set) var lastDiagnosticsTwitchStatus: String = "Unknown"
    @Published private(set) var lastDiagnosticsConnectorRecoveryStatus: String = "Unknown"
    @Published private(set) var lastDiagnosticsTwitchRefreshStatus: String = "None"
    @Published private(set) var lastDiagnosticsProviderDedupeStatus: String = "Unknown"
    @Published private(set) var lastDiagnosticsDeliveryStatus: String = "None"
    @Published private(set) var lastDiagnosticsDeviceTokenStatus: String = "Unknown"
    @Published private(set) var lastDiagnosticsHasCurrentUser = false

    private let logger = Logger(subsystem: "com.irlalert.app", category: "RelayClient")
    private let settings = AppSettings.shared

    private var baseURL: URL {
        URL(string: settings.relayBaseURL) ?? URL(string: "http://localhost:3000")!
    }

    var diagnosticsBaseURL: String {
        baseURL.absoluteString
    }

    var twitchEventSubReady: Bool {
        lastUserReadinessOk
    }

    var twitchReadinessLabel: String {
        if lastUserReadinessOk { return "Ready" }
        if lastReadinessFetchedAt != nil { return lastUserReadinessSummary }
        if lastDiagnosticsTwitchStatus != "Unknown",
           lastDiagnosticsTwitchStatus != "Not connected" {
            return lastDiagnosticsTwitchStatus
        }
        if lastTwitchOAuthStartedAt != nil { return "Verify" }
        return "OAuth"
    }

    func registerIfPossible(deviceToken: String, services: [ServiceIdentifier]) async {
        guard settings.pushNotificationsEnabled else { return }

        let payload: [String: Any] = [
            "userId": settings.relayUserId,
            "deviceToken": deviceToken,
            "services": services.map { $0.rawValue },
            "credentials": []
        ]

        lastRegistrationAttemptAt = Date()
        let result = await post(path: "/register", body: payload)
        lastRegistrationStatusCode = result.statusCode

        if let error = result.error {
            lastRegistrationError = error
        } else if let statusCode = result.statusCode, statusCode >= 400 {
            lastRegistrationError = "HTTP \(statusCode)"
        } else {
            lastRegistrationSucceededAt = Date()
            lastRegistrationError = nil
        }
    }

    func sendRelayTestAlert(type: AlertType = .follow) async {
        guard settings.pushNotificationsEnabled else {
            lastTestAlertError = "Push alerts disabled"
            return
        }

        isSendingTestAlert = true
        defer { isSendingTestAlert = false }

        let correlationId = "ios-test-\(UUID().uuidString)"
        lastTestAlertCorrelationId = correlationId

        let alert: [String: Any] = [
            "correlationId": correlationId,
            "providerMessageId": correlationId,
            "alert_id": correlationId,
            "type": type.rawValue,
            "username": "iOSRelayTest",
            "message": "Relay delivery proof alert",
            "source": "twitch_native",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        let result = await post(path: "/alert", body: [
            "userId": settings.relayUserId,
            "alert": alert
        ])

        lastTestAlertStatusCode = result.statusCode
        if let error = result.error {
            lastTestAlertError = error
        } else if let statusCode = result.statusCode, statusCode >= 400 {
            lastTestAlertError = "HTTP \(statusCode)"
        } else {
            lastTestAlertError = nil
        }
    }

    func createTwitchOAuthURL() async -> URL? {
        isStartingTwitchOAuth = true
        defer { isStartingTwitchOAuth = false }

        guard let url = URL(string: "/auth/twitch/start?userId=\(settings.relayUserId)", relativeTo: baseURL) else {
            lastTwitchOAuthError = "Invalid relay URL"
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            lastTwitchOAuthStatusCode = (response as? HTTPURLResponse)?.statusCode

            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                lastTwitchOAuthError = "HTTP \(lastTwitchOAuthStatusCode ?? 0)"
                return nil
            }

            let payload = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            guard let authUrlString = payload?["authUrl"] as? String,
                  let authUrl = URL(string: authUrlString) else {
                lastTwitchOAuthError = "Missing Twitch auth URL"
                return nil
            }

            lastTwitchOAuthStartedAt = Date()
            lastTwitchOAuthError = nil
            return authUrl
        } catch {
            lastTwitchOAuthError = error.localizedDescription
            logger.error("Twitch OAuth start failed: \(error.localizedDescription)")
            return nil
        }
    }

    func fetchReadiness() async {
        isFetchingReadiness = true
        defer { isFetchingReadiness = false }

        guard var components = URLComponents(url: baseURL.appendingPathComponent("ready"), resolvingAgainstBaseURL: false) else {
            lastReadinessError = "Invalid relay URL"
            return
        }
        components.queryItems = [
            URLQueryItem(name: "userId", value: settings.relayUserId)
        ]

        guard let url = components.url else {
            lastReadinessError = "Invalid relay URL"
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            lastReadinessStatusCode = (response as? HTTPURLResponse)?.statusCode

            guard let payload = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                lastReadinessError = "Invalid readiness JSON"
                lastUserReadinessOk = false
                return
            }

            applyReadiness(payload)
            lastReadinessFetchedAt = Date()
            lastReadinessError = nil
        } catch {
            lastReadinessError = error.localizedDescription
            lastUserReadinessOk = false
            logger.error("Relay readiness failed: \(error.localizedDescription)")
        }
    }

    func fetchDiagnostics() async {
        isFetchingDiagnostics = true
        defer { isFetchingDiagnostics = false }

        guard let url = URL(string: "/diagnostics", relativeTo: baseURL) else {
            lastDiagnosticsError = "Invalid relay URL"
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            lastDiagnosticsStatusCode = (response as? HTTPURLResponse)?.statusCode

            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                lastDiagnosticsError = "HTTP \(lastDiagnosticsStatusCode ?? 0)"
                return
            }

            guard let payload = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                lastDiagnosticsError = "Invalid diagnostics JSON"
                return
            }

            applyDiagnostics(payload)
            lastDiagnosticsFetchedAt = Date()
            lastDiagnosticsError = nil
        } catch {
            lastDiagnosticsError = error.localizedDescription
            logger.error("Relay diagnostics failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Networking

    @discardableResult
    private func post(path: String, body: [String: Any]) async -> (statusCode: Int?, error: String?) {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            return (nil, "Invalid relay URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                logger.warning("Relay server returned status \(http.statusCode)")
            }
            return ((response as? HTTPURLResponse)?.statusCode, nil)
        } catch {
            logger.error("Relay request failed: \(error.localizedDescription)")
            return (nil, error.localizedDescription)
        }
    }

    private func applyDiagnostics(_ payload: [String: Any]) {
        let users = payload["users"] as? [[String: Any]] ?? []
        let currentUser = users.first { user in
            stringValue(user["userId"]) == settings.relayUserId
        }

        lastDiagnosticsHasCurrentUser = currentUser != nil
        lastDiagnosticsDeviceTokenStatus = deviceTokenSummary(currentUser)

        let connectors = payload["connectors"] as? [[String: Any]] ?? []
        let twitchConnector = connectors.first { connector in
            stringValue(connector["service"]) == "twitch_native"
        }
        lastDiagnosticsTwitchStatus = stringValue(twitchConnector?["status"]) ?? "Not connected"

        if let recovery = payload["connectorRecovery"] as? [String: Any] {
            let synced = stringValue(recovery["syncedUsers"]) ?? "0"
            let failed = stringValue(recovery["failedUsers"]) ?? "0"
            let lastSync = stringValue(recovery["lastSyncAllAt"]).map(shortIdentifier) ?? "never"
            lastDiagnosticsConnectorRecoveryStatus = "\(synced) synced, \(failed) failed, \(lastSync)"
        } else {
            lastDiagnosticsConnectorRecoveryStatus = "Unknown"
        }

        let readiness = payload["readiness"] as? [String: Any]
        lastDiagnosticsApnsReadiness = readinessSummary(
            readiness?["apns"] as? [String: Any],
            readyLabel: "Configured"
        )
        lastDiagnosticsTwitchOAuthReadiness = readinessSummary(
            readiness?["twitchOAuth"] as? [String: Any],
            readyLabel: "Configured"
        )

        let attempts = payload["recentDeliveryAttempts"] as? [[String: Any]] ?? []
        if let lastAttempt = attempts.last {
            let status = stringValue(lastAttempt["status"]) ?? "unknown"
            let correlationId = stringValue(lastAttempt["correlationId"]) ?? stringValue(lastAttempt["providerMessageId"])
            lastDiagnosticsDeliveryStatus = [status, correlationId.map(shortIdentifier)]
                .compactMap { $0 }
                .joined(separator: " ")
        } else {
            lastDiagnosticsDeliveryStatus = "None"
        }

        let tokenRefreshAttempts = payload["recentTokenRefreshAttempts"] as? [[String: Any]] ?? []
        if let lastRefreshAttempt = tokenRefreshAttempts.last {
            let status = stringValue(lastRefreshAttempt["status"]) ?? "unknown"
            let userId = stringValue(lastRefreshAttempt["userId"]).map(shortIdentifier)
            let error = stringValue(lastRefreshAttempt["error"])
            lastDiagnosticsTwitchRefreshStatus = [status, userId, error]
                .compactMap { $0 }
                .joined(separator: " ")
        } else {
            lastDiagnosticsTwitchRefreshStatus = "None"
        }

        if let dedupe = payload["providerMessageDedupe"] as? [String: Any],
           let tracked = dedupe["tracked"] {
            lastDiagnosticsProviderDedupeStatus = "\(stringValue(tracked) ?? "0") tracked"
        } else {
            lastDiagnosticsProviderDedupeStatus = "Unknown"
        }

        let currentUserStatus = currentUser == nil ? "missing user" : "user registered"
        lastDiagnosticsSummary = "\(users.count) users, \(currentUserStatus)"
    }

    private func applyReadiness(_ payload: [String: Any]) {
        let globalChecks = payload["checks"] as? [[String: Any]]
        let globalOk = globalChecks?.allSatisfy { $0["ok"] as? Bool == true } ?? false
        lastReadinessSummary = globalOk ? "Global ready" : checkFailureSummary(payload["checks"] as? [[String: Any]])

        guard let user = payload["user"] as? [String: Any] else {
            lastUserReadinessOk = false
            lastUserReadinessSummary = "Missing user readiness"
            return
        }

        lastUserReadinessOk = user["ok"] as? Bool == true
        if lastUserReadinessOk {
            lastUserReadinessSummary = "Ready"
        } else {
            lastUserReadinessSummary = checkFailureSummary(user["checks"] as? [[String: Any]])
        }
    }

    private func stringValue(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? CustomStringConvertible { return value.description }
        return nil
    }

    private func readinessSummary(_ payload: [String: Any]?, readyLabel: String) -> String {
        guard let payload else { return "Unknown" }
        if payload["configured"] as? Bool == true { return readyLabel }
        let missing = payload["missing"] as? [String] ?? []
        if missing.isEmpty { return "Incomplete" }
        return "Missing \(missing.joined(separator: ", "))"
    }

    private func checkFailureSummary(_ checks: [[String: Any]]?) -> String {
        let failedChecks = checks?.filter { $0["ok"] as? Bool != true } ?? []
        guard !failedChecks.isEmpty else { return "Incomplete" }

        let labels = failedChecks.map { check in
            let name = stringValue(check["name"]) ?? "check"
            let missing = check["missing"] as? [String] ?? []
            if missing.isEmpty { return name }
            return "\(name): \(missing.joined(separator: ", "))"
        }
        return "Missing \(labels.joined(separator: "; "))"
    }

    private func deviceTokenSummary(_ user: [String: Any]?) -> String {
        guard let user else { return "Missing user" }
        guard user["hasDeviceToken"] as? Bool == true else { return "Missing token" }
        let fingerprint = stringValue(user["deviceTokenFingerprint"]).map(shortIdentifier) ?? "unknown"
        let length = stringValue(user["deviceTokenLength"]) ?? "unknown"
        return "\(fingerprint) length \(length)"
    }

    private func shortIdentifier(_ value: String) -> String {
        guard value.count > 12 else { return value }
        return "\(value.prefix(6))...\(value.suffix(6))"
    }
}
