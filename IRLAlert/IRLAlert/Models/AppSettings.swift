import Foundation
import SwiftUI

/// Centralized app settings backed by UserDefaults.
/// Stores user preferences and first-launch state.
@MainActor
final class AppSettings: ObservableObject {

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let alertVolume = "alertVolume"
        static let ttsVolume = "ttsVolume"
        static let ttsEnabled = "ttsEnabled"
        static let ttsVoiceIdentifier = "ttsVoiceIdentifier"
        static let hapticFeedbackEnabled = "hapticFeedbackEnabled"
        static let queueOverflowThreshold = "queueOverflowThreshold"
        static let interAlertDelay = "interAlertDelay"
        static let disconnectNotificationTimeout = "disconnectNotificationTimeout"
        static let enabledAlertTypes = "enabledAlertTypes"
        static let ttsRate = "ttsRate"
    }

    private let defaults: UserDefaults

    // MARK: - Singleton for service-layer access
    
    static let shared = AppSettings()

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
        loadValues()
    }

    // MARK: - Onboarding

    @Published var hasCompletedOnboarding: Bool = false {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    // MARK: - Audio Settings

    /// Alert sound volume (0.0–1.0)
    @Published var alertVolume: Float = 0.85 {
        didSet { defaults.set(alertVolume, forKey: Keys.alertVolume) }
    }

    /// TTS volume (0.0–1.0)
    @Published var ttsVolume: Float = 0.70 {
        didSet { defaults.set(ttsVolume, forKey: Keys.ttsVolume) }
    }

    /// Whether text-to-speech is enabled globally
    @Published var ttsEnabled: Bool = true {
        didSet { defaults.set(ttsEnabled, forKey: Keys.ttsEnabled) }
    }

    /// Identifier of the selected system TTS voice (nil = system default)
    @Published var ttsVoiceIdentifier: String? = nil {
        didSet { defaults.set(ttsVoiceIdentifier, forKey: Keys.ttsVoiceIdentifier) }
    }

    /// TTS speech rate (0.0–1.0, default is system default rate)
    @Published var ttsRate: Float = 0.5 {
        didSet { defaults.set(ttsRate, forKey: Keys.ttsRate) }
    }

    // MARK: - Feedback

    /// Whether haptic feedback is enabled
    @Published var hapticFeedbackEnabled: Bool = true {
        didSet { defaults.set(hapticFeedbackEnabled, forKey: Keys.hapticFeedbackEnabled) }
    }

    // MARK: - Queue Settings

    /// Max alerts in queue before overflow summarization kicks in
    @Published var queueOverflowThreshold: Int = 20 {
        didSet { defaults.set(queueOverflowThreshold, forKey: Keys.queueOverflowThreshold) }
    }

    /// Delay in seconds between consecutive alerts
    @Published var interAlertDelay: Double = 1.0 {
        didSet { defaults.set(interAlertDelay, forKey: Keys.interAlertDelay) }
    }

    // MARK: - Connectivity

    /// Seconds of disconnection before firing a local notification (default 30s)
    @Published var disconnectNotificationTimeout: Double = 30.0 {
        didSet { defaults.set(disconnectNotificationTimeout, forKey: Keys.disconnectNotificationTimeout) }
    }

    // MARK: - Alert Type Filters

    /// Which alert types are enabled for audio playback
    @Published var enabledAlertTypes: Set<AlertType> = Set(AlertType.allCases) {
        didSet {
            let rawValues = enabledAlertTypes.map { $0.rawValue }
            defaults.set(rawValues, forKey: Keys.enabledAlertTypes)
        }
    }

    // MARK: - Private Helpers

    private func registerDefaults() {
        defaults.register(defaults: [
            Keys.hasCompletedOnboarding: false,
            Keys.alertVolume: Float(0.85),
            Keys.ttsVolume: Float(0.70),
            Keys.ttsEnabled: true,
            Keys.hapticFeedbackEnabled: true,
            Keys.queueOverflowThreshold: 20,
            Keys.interAlertDelay: 1.0,
            Keys.disconnectNotificationTimeout: 30.0,
            Keys.ttsRate: Float(0.5),
        ])
    }

    private func loadValues() {
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        alertVolume = defaults.float(forKey: Keys.alertVolume)
        ttsVolume = defaults.float(forKey: Keys.ttsVolume)
        ttsEnabled = defaults.bool(forKey: Keys.ttsEnabled)
        ttsVoiceIdentifier = defaults.string(forKey: Keys.ttsVoiceIdentifier)
        hapticFeedbackEnabled = defaults.bool(forKey: Keys.hapticFeedbackEnabled)
        queueOverflowThreshold = defaults.integer(forKey: Keys.queueOverflowThreshold)
        interAlertDelay = defaults.double(forKey: Keys.interAlertDelay)
        disconnectNotificationTimeout = defaults.double(forKey: Keys.disconnectNotificationTimeout)

        if let rawValues = defaults.array(forKey: Keys.enabledAlertTypes) as? [String] {
            enabledAlertTypes = Set(rawValues.compactMap { AlertType(rawValue: $0) })
        }
        ttsRate = defaults.float(forKey: Keys.ttsRate)
    }
}
