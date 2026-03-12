import Foundation

/// Unified alert event model used across the entire app.
/// Created by service integrations, processed by AlertQueueManager, displayed in EventLogView.
struct AlertEvent: Identifiable, Codable, Sendable {
    let id: UUID
    let type: AlertType
    let username: String
    let message: String?
    let amount: Double?
    let formattedAmount: String?
    let soundURL: URL?
    let timestamp: Date
    let source: AlertSource
    
    /// Which streaming service produced this alert
    enum AlertSource: String, Codable, Sendable {
        case streamlabs
        case streamElements = "stream_elements"
        case twitchNative = "twitch_native"
        case soundAlerts = "sound_alerts"
        case mock // For testing
    }
    
    init(
        id: UUID = UUID(),
        type: AlertType,
        username: String,
        message: String? = nil,
        amount: Double? = nil,
        formattedAmount: String? = nil,
        soundURL: URL? = nil,
        timestamp: Date = Date(),
        source: AlertSource
    ) {
        self.id = id
        self.type = type
        self.username = username
        self.message = message
        self.amount = amount
        self.formattedAmount = formattedAmount
        self.soundURL = soundURL
        self.timestamp = timestamp
        self.source = source
    }
    
    /// Generate a TTS string for this alert based on its type
    var ttsText: String {
        switch type {
        case .donation:
            let amountStr = formattedAmount ?? (amount.map { String(format: "$%.2f", $0) } ?? "")
            if let message = message, !message.isEmpty {
                return "\(username) donated \(amountStr). \(message)"
            }
            return "\(username) donated \(amountStr)"
            
        case .subscription:
            return "\(username) just subscribed!"
            
        case .bits:
            let bitCount = amount.map { "\(Int($0))" } ?? "some"
            return "\(username) cheered \(bitCount) bits"
            
        case .follow:
            return "\(username) is now following"
            
        case .host:
            let viewerCount = amount.map { "\(Int($0))" } ?? "some"
            return "\(username) is hosting with \(viewerCount) viewers"
            
        case .raid:
            let viewerCount = amount.map { "\(Int($0))" } ?? "some"
            return "\(username) is raiding with \(viewerCount) viewers!"
        }
    }
    
    // MARK: - Mock Factories (for testing)
    
    static func mockDonation(
        username: String = "TestUser",
        amount: Double = 5.00,
        message: String = "Great stream!"
    ) -> AlertEvent {
        AlertEvent(
            type: .donation,
            username: username,
            message: message,
            amount: amount,
            formattedAmount: String(format: "$%.2f", amount),
            source: .mock
        )
    }
    
    static func mockSubscription(username: String = "SubFan") -> AlertEvent {
        AlertEvent(type: .subscription, username: username, source: .mock)
    }
    
    static func mockRaid(username: String = "RaidLeader", viewers: Int = 150) -> AlertEvent {
        AlertEvent(
            type: .raid,
            username: username,
            amount: Double(viewers),
            source: .mock
        )
    }
    
    static func mockBits(username: String = "BitsBaron", bits: Int = 500) -> AlertEvent {
        AlertEvent(
            type: .bits,
            username: username,
            amount: Double(bits),
            source: .mock
        )
    }
    
    static func mockFollow(username: String = "NewFollower") -> AlertEvent {
        AlertEvent(type: .follow, username: username, source: .mock)
    }
}
