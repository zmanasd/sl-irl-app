import UserNotifications

final class NotificationService: UNNotificationServiceExtension {

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        guard let bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        let userInfo = request.content.userInfo
        let alertPayload = userInfo["alert"] as? [String: Any]

        if let title = alertPayload?["title"] as? String {
            bestAttemptContent.title = title
        } else if let type = alertPayload?["type"] as? String,
                  let username = alertPayload?["username"] as? String {
            bestAttemptContent.title = "IRL Alert"
            bestAttemptContent.body = "\(username) triggered a \(type)."
        }

        contentHandler(bestAttemptContent)
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

}
