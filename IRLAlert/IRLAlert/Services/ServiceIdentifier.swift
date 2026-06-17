import Foundation

/// Relay service identifiers supported by the Twitch-first MVP.
enum ServiceIdentifier: String, CaseIterable, Identifiable, Codable, Sendable {
    case twitchNative = "twitch_native"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .twitchNative: return "Twitch Native"
        }
    }

    /// Map to the corresponding AlertSource on AlertEvent.
    var alertSource: AlertEvent.AlertSource {
        switch self {
        case .twitchNative: return .twitchNative
        }
    }
}
