import Foundation

/// All supported alert types from the PRD (Section 4.1).
/// Used for filtering, display, and queue processing.
enum AlertType: String, CaseIterable, Identifiable, Codable {
    case donation
    case follow
    case subscription
    case bits
    case host
    case raid

    var id: String { rawValue }

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .donation:     return "Donation"
        case .follow:       return "Follow"
        case .subscription: return "Subscription"
        case .bits:         return "Bits"
        case .host:         return "Host"
        case .raid:         return "Raid"
        }
    }

    /// SF Symbol icon name for each alert type
    var iconName: String {
        switch self {
        case .donation:     return "dollarsign.circle.fill"
        case .follow:       return "person.badge.plus"
        case .subscription: return "star.circle.fill"
        case .bits:         return "diamond.fill"
        case .host:         return "megaphone.fill"
        case .raid:         return "person.3.fill"
        }
    }

    /// Accent color name (matches design system)
    var accentColorName: String {
        switch self {
        case .donation:     return "alertGreen"
        case .follow:       return "primaryBlue"
        case .subscription: return "alertPurple"
        case .bits:         return "alertYellow"
        case .host:         return "alertOrange"
        case .raid:         return "alertRed"
        }
    }
}
