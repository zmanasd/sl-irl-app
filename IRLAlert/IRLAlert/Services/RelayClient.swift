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
    @Published private(set) var lastAuthStatusCode: Int?
    @Published private(set) var lastAuthError: String?
    @Published private(set) var lastAccountActionStatusCode: Int?
    @Published private(set) var lastAccountActionError: String?
    @Published private(set) var lastAppReceiptStatusCode: Int?
    @Published private(set) var lastAppReceiptError: String?
    @Published private(set) var lastAppReceiptCorrelationId: String?

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

        let path = settings.hasRelaySession ? "/v1/devices" : "/register"
        let payload: [String: Any]
        if settings.hasRelaySession {
            var betaPayload: [String: Any] = [
                "deviceToken": deviceToken,
                "apnsEnvironment": apnsEnvironment
            ]
            if let build = appBuild { betaPayload["appBuild"] = build }
            if let version = appVersion { betaPayload["appVersion"] = version }
            payload = betaPayload
        } else {
            payload = [
                "userId": settings.relayEffectiveUserId,
                "deviceToken": deviceToken,
                "services": services.map { $0.rawValue },
                "credentials": []
            ]
        }

        lastRegistrationAttemptAt = Date()
        let result = await post(path: path, body: payload, authenticated: settings.hasRelaySession)
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

        let result: (statusCode: Int?, error: String?)
        if settings.hasRelaySession {
            let json = await postJson(path: "/v1/test-alert", body: [
                "type": type.rawValue,
                "username": "iOSRelayTest",
                "message": "Relay delivery proof alert"
            ], authenticated: true)
            if let backendCorrelationId = json.payload?["correlationId"] as? String {
                lastTestAlertCorrelationId = backendCorrelationId
            }
            result = (json.statusCode, json.error)
        } else {
            result = await post(path: "/alert", body: [
                "userId": settings.relayEffectiveUserId,
                "alert": alert
            ])
        }

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

        let path = settings.hasRelaySession
            ? "/v1/twitch/oauth/start"
            : "/auth/twitch/start?userId=\(settings.relayEffectiveUserId)"
        guard let url = URL(string: path, relativeTo: baseURL) else {
            lastTwitchOAuthError = "Invalid relay URL"
            return nil
        }

        do {
            var request = URLRequest(url: url)
            if settings.hasRelaySession, let token = settings.relaySessionToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
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

        let readinessPath = settings.hasRelaySession ? "/v1/status" : "/ready"
        guard let readinessURL = URL(string: readinessPath, relativeTo: baseURL),
              var components = URLComponents(url: readinessURL, resolvingAgainstBaseURL: true) else {
            lastReadinessError = "Invalid relay URL"
            return
        }
        if !settings.hasRelaySession {
            components.queryItems = [
                URLQueryItem(name: "userId", value: settings.relayEffectiveUserId)
            ]
        }

        guard let url = components.url else {
            lastReadinessError = "Invalid relay URL"
            return
        }

        do {
            var request = URLRequest(url: url)
            if settings.hasRelaySession, let token = settings.relaySessionToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            lastReadinessStatusCode = (response as? HTTPURLResponse)?.statusCode

            guard let payload = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                lastReadinessError = "Invalid readiness JSON"
                lastUserReadinessOk = false
                return
            }

            if settings.hasRelaySession,
               var readinessPayload = payload["readiness"] as? [String: Any] {
                readinessPayload["user"] = payload["user"]
                applyReadiness(readinessPayload)
            } else {
                applyReadiness(payload)
            }
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

        let path = settings.hasRelaySession ? "/v1/diagnostics" : "/diagnostics"
        guard let url = URL(string: path, relativeTo: baseURL) else {
            lastDiagnosticsError = "Invalid relay URL"
            return
        }

        do {
            var request = URLRequest(url: url)
            if settings.hasRelaySession, let token = settings.relaySessionToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
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

    func storeAppleIdentityToken(_ identityToken: String, fullName: String? = nil) async {
        var body: [String: Any] = ["identityToken": identityToken]
        if let fullName {
            body["fullName"] = fullName
        }

        let result = await postJson(path: "/v1/auth/apple", body: body)
        lastAuthStatusCode = result.statusCode

        guard result.error == nil else {
            lastAuthError = result.error
            return
        }
        guard let payload = result.payload,
              let userId = payload["userId"] as? String,
              let sessionToken = payload["sessionToken"] as? String else {
            lastAuthError = "Missing relay session"
            return
        }

        settings.updateRelaySession(userId: userId, sessionToken: sessionToken)
        lastAuthError = nil
    }

    func disconnectTwitch() async {
        guard settings.hasRelaySession else {
            lastAccountActionError = "Relay session required"
            return
        }

        let result = await post(path: "/v1/twitch/disconnect", body: [:], authenticated: true)
        lastAccountActionStatusCode = result.statusCode
        if let error = result.error {
            lastAccountActionError = error
        } else if let statusCode = result.statusCode, statusCode >= 400 {
            lastAccountActionError = "HTTP \(statusCode)"
        } else {
            lastAccountActionError = nil
            await fetchDiagnostics()
            await fetchReadiness()
        }
    }

    func deleteRelayAccount() async {
        guard settings.hasRelaySession else {
            lastAccountActionError = "Relay session required"
            return
        }

        let result = await delete(path: "/v1/account", authenticated: true)
        lastAccountActionStatusCode = result.statusCode
        if let error = result.error {
            lastAccountActionError = error
        } else if let statusCode = result.statusCode, statusCode >= 400 {
            lastAccountActionError = "HTTP \(statusCode)"
        } else {
            settings.clearRelaySession()
            lastAccountActionError = nil
            lastUserReadinessOk = false
            lastUserReadinessSummary = "Account deleted"
            lastDiagnosticsSummary = "Session cleared"
        }
    }

    func recordAppReceipt(for event: AlertEvent) async {
        guard settings.hasRelaySession else { return }
        guard let correlationId = event.correlationId ?? event.providerMessageId else { return }
        lastAppReceiptCorrelationId = correlationId

        var body: [String: Any] = [
            "correlationId": correlationId,
            "status": "received",
            "appReceivedAt": ISO8601DateFormatter().string(from: Date())
        ]
        if let providerMessageId = event.providerMessageId {
            body["providerMessageId"] = providerMessageId
        }
        if let build = appBuild {
            body["appBuild"] = build
        }
        if let version = appVersion {
            body["appVersion"] = version
        }

        let result = await post(path: "/v1/alerts/receipt", body: body, authenticated: true)
        lastAppReceiptStatusCode = result.statusCode
        if let error = result.error {
            lastAppReceiptError = error
        } else if let statusCode = result.statusCode, statusCode >= 400 {
            lastAppReceiptError = "HTTP \(statusCode)"
        } else {
            lastAppReceiptError = nil
        }
    }

    // MARK: - Networking

    @discardableResult
    private func post(path: String, body: [String: Any], authenticated: Bool = false) async -> (statusCode: Int?, error: String?) {
        let result = await postJson(path: path, body: body, authenticated: authenticated)
        return (result.statusCode, result.error)
    }

    @discardableResult
    private func postJson(path: String, body: [String: Any], authenticated: Bool = false) async -> (statusCode: Int?, payload: [String: Any]?, error: String?) {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            return (nil, nil, "Invalid relay URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated, let token = settings.relaySessionToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                logger.warning("Relay server returned status \(http.statusCode)")
            }
            let payload = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            return ((response as? HTTPURLResponse)?.statusCode, payload, nil)
        } catch {
            logger.error("Relay request failed: \(error.localizedDescription)")
            return (nil, nil, error.localizedDescription)
        }
    }

    private var apnsEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    private var appBuild: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }

    private var appVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    @discardableResult
    private func delete(path: String, authenticated: Bool = false) async -> (statusCode: Int?, error: String?) {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            return (nil, "Invalid relay URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        if authenticated, let token = settings.relaySessionToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                logger.warning("Relay server returned status \(http.statusCode)")
            }
            return ((response as? HTTPURLResponse)?.statusCode, nil)
        } catch {
            logger.error("Relay delete request failed: \(error.localizedDescription)")
            return (nil, error.localizedDescription)
        }
    }

    private func applyDiagnostics(_ payload: [String: Any]) {
        let users = payload["users"] as? [[String: Any]] ?? []
        let currentUser = payload["user"] as? [String: Any] ?? users.first { user in
            stringValue(user["userId"]) == settings.relayEffectiveUserId
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

        let readinessContainer = payload["readiness"] as? [String: Any]
        let readiness = readinessContainer?["readiness"] as? [String: Any] ?? readinessContainer
        lastDiagnosticsApnsReadiness = readinessSummary(
            readiness?["apns"] as? [String: Any],
            readyLabel: "Configured"
        )
        lastDiagnosticsTwitchOAuthReadiness = readinessSummary(
            readiness?["twitchOAuth"] as? [String: Any],
            readyLabel: "Configured"
        )

        let attempts = payload["attempts"] as? [[String: Any]]
            ?? payload["recentDeliveryAttempts"] as? [[String: Any]]
            ?? []
        if let lastAttempt = attempts.last {
            let status = stringValue(lastAttempt["status"]) ?? "unknown"
            let correlationId = stringValue(lastAttempt["correlationId"]) ?? stringValue(lastAttempt["providerMessageId"])
            lastDiagnosticsDeliveryStatus = [status, correlationId.map(shortIdentifier)]
                .compactMap { $0 }
                .joined(separator: " ")
        } else {
            lastDiagnosticsDeliveryStatus = "None"
        }

        let tokenRefreshAttempts = payload["tokenRefreshAttempts"] as? [[String: Any]]
            ?? payload["recentTokenRefreshAttempts"] as? [[String: Any]]
            ?? []
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
        let userCount = payload["user"] == nil ? users.count : 1
        lastDiagnosticsSummary = "\(userCount) users, \(currentUserStatus)"
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
