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
        let soundURLString = alertPayload?["sound_url"] as? String

        guard let soundURLString, let soundURL = URL(string: soundURLString) else {
            contentHandler(bestAttemptContent)
            return
        }

        downloadSound(from: soundURL) { localURL in
            if let localURL {
                bestAttemptContent.sound = UNNotificationSound(
                    named: UNNotificationSoundName(localURL.lastPathComponent)
                )
            }
            contentHandler(bestAttemptContent)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    private func downloadSound(from url: URL, completion: @escaping (URL?) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { location, _, _ in
            guard let location else {
                completion(nil)
                return
            }

            let filename = url.lastPathComponent.isEmpty ? "alert_sound.caf" : url.lastPathComponent
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

            try? FileManager.default.removeItem(at: destination)
            do {
                try FileManager.default.moveItem(at: location, to: destination)
                completion(destination)
            } catch {
                completion(nil)
            }
        }
        task.resume()
    }
}
