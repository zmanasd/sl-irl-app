import Foundation
import SwiftUI

/// Twitch-first MVP alert types.
/// Used for filtering, display, and queue processing.
enum AlertType: String, CaseIterable, Identifiable, Codable {
    case follow
    case subscription
    case bits
    case raid
    case channelPoints = "channel_points"

    var id: String { rawValue }

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .follow:       return "Follow"
        case .subscription: return "Subscription"
        case .bits:         return "Bits"
        case .raid:         return "Raid"
        case .channelPoints: return "Channel Points"
        }
    }

    /// SF Symbol icon name for each alert type
    var iconName: String {
        switch self {
        case .follow:       return "person.badge.plus"
        case .subscription: return "star.circle.fill"
        case .bits:         return "diamond.fill"
        case .raid:         return "person.3.fill"
        case .channelPoints: return "sparkles"
        }
    }

    /// Accent color mapped to DesignSystem tokens
    var accentColor: Color {
        switch self {
        case .follow:       return DesignSystem.Colors.primaryBlue
        case .subscription: return DesignSystem.Colors.alertPurple
        case .bits:         return DesignSystem.Colors.alertYellow
        case .raid:         return DesignSystem.Colors.alertRed
        case .channelPoints: return DesignSystem.Colors.alertOrange
        }
    }
}
