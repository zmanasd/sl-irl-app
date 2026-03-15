import Foundation
import UIKit
import UserNotifications
import os.log

/// Handles APNs registration, authorization, and routing alert payloads into the app.
@MainActor
final class PushNotificationManager: NSObject, ObservableObject {

    static let shared = PushNotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var deviceToken: String?

    private let logger = Logger(subsystem: "com.irlalert.app", category: "PushNotificationManager")
    private var processedAlertIds = Set<String>()

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshAuthorizationStatus() }
    }

    // MARK: - User Preference Handling

    func handleUserToggle(enabled: Bool) async {
        if enabled {
            await requestAuthorizationAndRegister()
            if let token = deviceToken {
                let services = ConnectionManager.shared.registeredServiceIdentifiers()
                await RelayClient.shared.registerIfPossible(deviceToken: token, services: services)
            }
        } else {
            UIApplication.shared.unregisterForRemoteNotifications()
            await refreshAuthorizationStatus()
        }
    }

    // MARK: - Authorization

    func requestAuthorizationAndRegister() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            logger.info("Push authorization \(granted ? "granted" : "denied")")

            await refreshAuthorizationStatus()

            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            logger.error("Push authorization failed: \(error.localizedDescription)")
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    // MARK: - Token Handling

    func handleDeviceToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        logger.info("APNs device token: \(token, privacy: .private)")

        Task {
            let services = ConnectionManager.shared.registeredServiceIdentifiers()
            await RelayClient.shared.registerIfPossible(deviceToken: token, services: services)
        }
    }

    func handleFailedToRegister(_ error: Error) {
        logger.error("APNs registration failed: \(error.localizedDescription)")
    }

    // MARK: - Payload Routing

    @discardableResult
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) -> AlertEvent? {
        guard let event = parseAlertEvent(from: userInfo) else { return nil }
        AlertQueueManager.shared.enqueue(event)
        Task { await EventStore.shared.add(event) }
        return event
    }

    private func parseAlertEvent(from userInfo: [AnyHashable: Any]) -> AlertEvent? {
        let payload = (userInfo["alert"] as? [String: Any]) ?? userInfo

        let alertId = stringValue("alert_id", in: payload) ?? stringValue("id", in: payload)
        if !shouldProcessAlert(id: alertId) { return nil }

        guard let typeRaw = stringValue("type", in: payload) ?? stringValue("alert_type", in: payload),
              let type = AlertType(rawValue: typeRaw.lowercased()) else {
            logger.warning("Push payload missing alert type.")
            return nil
        }

        guard let username = stringValue("username", in: payload) ?? stringValue("user", in: payload) else {
            logger.warning("Push payload missing username.")
            return nil
        }

        let message = stringValue("message", in: payload)
        let amount = doubleValue("amount", in: payload)
        let formattedAmount = stringValue("formatted_amount", in: payload)
        let soundURL = urlValue("sound_url", in: payload)

        let timestamp = dateValue("timestamp", in: payload) ?? Date()
        let sourceRaw = stringValue("source", in: payload) ?? "streamlabs"
        let source = AlertEvent.AlertSource(rawValue: sourceRaw) ?? .streamlabs

        return AlertEvent(
            type: type,
            username: username,
            message: message,
            amount: amount,
            formattedAmount: formattedAmount,
            soundURL: soundURL,
            timestamp: timestamp,
            source: source
        )
    }

    private func shouldProcessAlert(id: String?) -> Bool {
        guard let id, !id.isEmpty else { return true }
        if processedAlertIds.contains(id) { return false }
        processedAlertIds.insert(id)
        if processedAlertIds.count > 200 {
            processedAlertIds = Set(processedAlertIds.suffix(100))
        }
        return true
    }

    private func stringValue(_ key: String, in payload: [AnyHashable: Any]) -> String? {
        if let value = payload[key] as? String { return value }
        if let value = payload[key] as? CustomStringConvertible { return value.description }
        return nil
    }

    private func doubleValue(_ key: String, in payload: [AnyHashable: Any]) -> Double? {
        if let value = payload[key] as? Double { return value }
        if let value = payload[key] as? Int { return Double(value) }
        if let value = payload[key] as? String { return Double(value) }
        return nil
    }

    private func urlValue(_ key: String, in payload: [AnyHashable: Any]) -> URL? {
        guard let urlString = stringValue(key, in: payload) else { return nil }
        return URL(string: urlString)
    }

    private func dateValue(_ key: String, in payload: [AnyHashable: Any]) -> Date? {
        if let value = payload[key] as? TimeInterval { return Date(timeIntervalSince1970: value) }
        if let value = payload[key] as? Double { return Date(timeIntervalSince1970: value) }
        if let value = payload[key] as? String {
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: value)
        }
        return nil
    }
}

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        _ = handleRemoteNotification(notification.request.content.userInfo)
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        _ = handleRemoteNotification(response.notification.request.content.userInfo)
        completionHandler()
    }
}
