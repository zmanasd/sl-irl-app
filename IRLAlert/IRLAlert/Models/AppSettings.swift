import Foundation
import Security
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
        static let enabledAlertTypes = "enabledAlertTypes"
        static let ttsRate = "ttsRate"
        static let pushNotificationsEnabled = "pushNotificationsEnabled"
        static let relayUserId = "relayUserId"
        static let relayBaseURL = "relayBaseURL"
        static let relaySessionToken = "relaySessionToken"
        static let relayAccountUserId = "relayAccountUserId"
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

    /// Whether push notifications are enabled for background alert delivery
    @Published var pushNotificationsEnabled: Bool = false {
        didSet { defaults.set(pushNotificationsEnabled, forKey: Keys.pushNotificationsEnabled) }
    }

    /// Stable identifier for relay registration
    @Published private(set) var relayUserId: String = UUID().uuidString

    /// Relay server base URL used for registration, Twitch OAuth, diagnostics, and test alerts
    @Published var relayBaseURL: String = "http://localhost:3000" {
        didSet { defaults.set(relayBaseURL, forKey: Keys.relayBaseURL) }
    }

    /// Private-beta bearer session returned by `/v1/auth/apple`.
    @Published private(set) var relaySessionToken: String?

    /// Server-owned user identifier returned by authenticated private-beta APIs.
    @Published private(set) var relayAccountUserId: String?

    var relayEffectiveUserId: String {
        relayAccountUserId ?? relayUserId
    }

    var hasRelaySession: Bool {
        relaySessionToken?.isEmpty == false
    }

    func updateRelaySession(userId: String, sessionToken: String) {
        relayAccountUserId = userId
        relaySessionToken = sessionToken
        defaults.set(userId, forKey: Keys.relayAccountUserId)
        defaults.removeObject(forKey: Keys.relaySessionToken)
        KeychainTokenStore.save(sessionToken, account: Keys.relaySessionToken)
    }

    func clearRelaySession() {
        relayAccountUserId = nil
        relaySessionToken = nil
        defaults.removeObject(forKey: Keys.relayAccountUserId)
        defaults.removeObject(forKey: Keys.relaySessionToken)
        KeychainTokenStore.delete(account: Keys.relaySessionToken)
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
            Keys.ttsRate: Float(0.5),
            Keys.pushNotificationsEnabled: false,
            Keys.relayUserId: UUID().uuidString,
            Keys.relayBaseURL: "http://localhost:3000",
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
        pushNotificationsEnabled = defaults.bool(forKey: Keys.pushNotificationsEnabled)
        relayUserId = defaults.string(forKey: Keys.relayUserId) ?? UUID().uuidString
        defaults.set(relayUserId, forKey: Keys.relayUserId)
        relayBaseURL = defaults.string(forKey: Keys.relayBaseURL) ?? "http://localhost:3000"
        relayAccountUserId = defaults.string(forKey: Keys.relayAccountUserId)
        if let legacyToken = defaults.string(forKey: Keys.relaySessionToken), !legacyToken.isEmpty {
            KeychainTokenStore.save(legacyToken, account: Keys.relaySessionToken)
            defaults.removeObject(forKey: Keys.relaySessionToken)
        }
        relaySessionToken = KeychainTokenStore.load(account: Keys.relaySessionToken)

        if let rawValues = defaults.array(forKey: Keys.enabledAlertTypes) as? [String] {
            enabledAlertTypes = Set(rawValues.compactMap { AlertType(rawValue: $0) })
        }
        ttsRate = defaults.float(forKey: Keys.ttsRate)
    }
}

private enum KeychainTokenStore {
    private static let service = "com.irlalert.relay"

    static func save(_ token: String, account: String) {
        guard let data = token.data(using: .utf8) else { return }
        delete(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
