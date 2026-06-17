import Foundation
import AVFoundation
import Combine
import UserNotifications

/// ViewModel for the Settings screen.
/// Binds AppSettings to the UI with additional logic for TTS voice selection.
@MainActor
final class SettingsVM: ObservableObject {
    
    // MARK: - Published State (mirrored from AppSettings for view binding)
    
    @Published var alertVolume: Float
    @Published var ttsVolume: Float
    @Published var ttsEnabled: Bool
    @Published var ttsRate: Float
    @Published var selectedVoiceId: String?
    @Published var hapticFeedbackEnabled: Bool
    @Published var queueOverflowThreshold: Int
    @Published var interAlertDelay: Double
    @Published var pushNotificationsEnabled: Bool
    @Published var relayBaseURL: String
    @Published var enabledAlertTypes: Set<AlertType>
    
    /// Available TTS voices for the picker
    @Published private(set) var availableVoices: [(id: String, name: String, language: String)] = []
    
    // MARK: - Dependencies
    
    private let settings = AppSettings.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Initialize from AppSettings
        alertVolume = settings.alertVolume
        ttsVolume = settings.ttsVolume
        ttsEnabled = settings.ttsEnabled
        ttsRate = settings.ttsRate
        selectedVoiceId = settings.ttsVoiceIdentifier
        hapticFeedbackEnabled = settings.hapticFeedbackEnabled
        queueOverflowThreshold = settings.queueOverflowThreshold
        interAlertDelay = settings.interAlertDelay
        pushNotificationsEnabled = settings.pushNotificationsEnabled
        relayBaseURL = settings.relayBaseURL
        enabledAlertTypes = settings.enabledAlertTypes
        
        loadAvailableVoices()
        setupBindings()
    }
    
    // MARK: - Public API
    
    /// Toggle a specific alert type on/off.
    func toggleAlertType(_ type: AlertType) {
        if enabledAlertTypes.contains(type) {
            enabledAlertTypes.remove(type)
        } else {
            enabledAlertTypes.insert(type)
        }
    }
    
    /// Reset all settings to defaults.
    func resetToDefaults() {
        alertVolume = 0.85
        ttsVolume = 0.70
        ttsEnabled = true
        ttsRate = 0.5
        selectedVoiceId = nil
        hapticFeedbackEnabled = true
        queueOverflowThreshold = 20
        interAlertDelay = 1.0
        pushNotificationsEnabled = false
        relayBaseURL = "http://localhost:3000"
        enabledAlertTypes = Set(AlertType.allCases)
    }

    /// Builds a secret-safe diagnostics snapshot for physical-device proof runs.
    func diagnosticsSnapshot(
        pushManager: PushNotificationManager = .shared,
        relayClient: RelayClient = .shared,
        generatedAt: Date = Date()
    ) -> String {
        let relayRegistrationStatus: String
        if let error = relayClient.lastRegistrationError {
            relayRegistrationStatus = error
        } else if let statusCode = relayClient.lastRegistrationStatusCode {
            relayRegistrationStatus = "HTTP \(statusCode)"
        } else if relayClient.lastRegistrationAttemptAt != nil {
            relayRegistrationStatus = "Pending"
        } else {
            relayRegistrationStatus = "Not attempted"
        }

        let relayTestStatus: String
        if let error = relayClient.lastTestAlertError {
            relayTestStatus = error
        } else if let statusCode = relayClient.lastTestAlertStatusCode {
            relayTestStatus = "HTTP \(statusCode)"
        } else if relayClient.isSendingTestAlert {
            relayTestStatus = "Sending"
        } else {
            relayTestStatus = "Not sent"
        }

        let relayDiagnosticsStatus: String
        if let error = relayClient.lastDiagnosticsError {
            relayDiagnosticsStatus = error
        } else if let statusCode = relayClient.lastDiagnosticsStatusCode {
            relayDiagnosticsStatus = "\(relayClient.lastDiagnosticsSummary) HTTP \(statusCode)"
        } else if relayClient.isFetchingDiagnostics {
            relayDiagnosticsStatus = "Fetching"
        } else {
            relayDiagnosticsStatus = relayClient.lastDiagnosticsSummary
        }

        let relayReadinessStatus: String
        if let error = relayClient.lastReadinessError {
            relayReadinessStatus = error
        } else if let statusCode = relayClient.lastReadinessStatusCode {
            relayReadinessStatus = "\(relayClient.lastUserReadinessSummary) HTTP \(statusCode)"
        } else if relayClient.isFetchingReadiness {
            relayReadinessStatus = "Fetching"
        } else {
            relayReadinessStatus = relayClient.lastUserReadinessSummary
        }

        return """
        IRL Alert MVP Diagnostics
        Generated At: \(isoString(generatedAt))
        Relay URL: \(relayClient.diagnosticsBaseURL)
        Relay User: \(shortIdentifier(settings.relayUserId))
        Push Alerts Enabled: \(settings.pushNotificationsEnabled)
        Push Permission: \(authorizationTitle(pushManager.authorizationStatus))
        APNs Token: \(pushManager.deviceToken?.isEmpty == false ? "Available" : "Missing")
        APNs Token Updated: \(isoString(pushManager.deviceTokenRegisteredAt))
        APNs Registration Error: \(pushManager.lastRegistrationError ?? "None")
        Push Receipts: \(pushManager.acceptedNotificationCount)/\(pushManager.receivedNotificationCount) accepted
        Dropped Pushes: \(pushManager.droppedNotificationCount)
        Last Received: \(isoString(pushManager.lastNotificationReceivedAt))
        Last Correlation: \(pushManager.lastAcceptedAlert.map { shortIdentifier($0.externalIdentity) } ?? "None")
        Last Drop: \(pushManager.lastDroppedAlertReason ?? "None")
        Relay Register: \(relayRegistrationStatus)
        Last Relay Test: \(relayTestStatus)
        Last Relay Test Correlation: \(relayClient.lastTestAlertCorrelationId.map(shortIdentifier) ?? "None")
        MVP Readiness: \(relayReadinessStatus)
        MVP Readiness Fetched: \(isoString(relayClient.lastReadinessFetchedAt))
        Relay Readiness: \(relayClient.lastReadinessSummary)
        Relay Diagnostics: \(relayDiagnosticsStatus)
        Relay Diagnostics Fetched: \(isoString(relayClient.lastDiagnosticsFetchedAt))
        Relay Current User: \(relayClient.lastDiagnosticsHasCurrentUser ? "Present" : "Missing")
        Relay Device Token: \(relayClient.lastDiagnosticsDeviceTokenStatus)
        Relay APNs Readiness: \(relayClient.lastDiagnosticsApnsReadiness)
        Twitch OAuth Readiness: \(relayClient.lastDiagnosticsTwitchOAuthReadiness)
        Connector Recovery: \(relayClient.lastDiagnosticsConnectorRecoveryStatus)
        Twitch Status: \(relayClient.lastDiagnosticsTwitchStatus)
        Twitch Refresh: \(relayClient.lastDiagnosticsTwitchRefreshStatus)
        Provider Dedupe: \(relayClient.lastDiagnosticsProviderDedupeStatus)
        Relay Delivery: \(relayClient.lastDiagnosticsDeliveryStatus)
        Twitch OAuth Start: \(relayClient.lastTwitchOAuthStatusCode.map { "HTTP \($0)" } ?? "Not attempted")
        Twitch OAuth Started: \(isoString(relayClient.lastTwitchOAuthStartedAt))
        Twitch OAuth Error: \(relayClient.lastTwitchOAuthError ?? "None")
        """
    }
    
    // MARK: - Private Helpers
    
    private func loadAvailableVoices() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") } // English voices only
            .sorted { $0.name < $1.name }
        
        availableVoices = voices.map { (id: $0.identifier, name: $0.name, language: $0.language) }
    }
    
    /// Sync ViewModel changes back to AppSettings.
    private func setupBindings() {
        $alertVolume.dropFirst().sink { [weak self] val in self?.settings.alertVolume = val }.store(in: &cancellables)
        $ttsVolume.dropFirst().sink { [weak self] val in self?.settings.ttsVolume = val }.store(in: &cancellables)
        $ttsEnabled.dropFirst().sink { [weak self] val in self?.settings.ttsEnabled = val }.store(in: &cancellables)
        $ttsRate.dropFirst().sink { [weak self] val in self?.settings.ttsRate = val }.store(in: &cancellables)
        $selectedVoiceId.dropFirst().sink { [weak self] val in self?.settings.ttsVoiceIdentifier = val }.store(in: &cancellables)
        $hapticFeedbackEnabled.dropFirst().sink { [weak self] val in self?.settings.hapticFeedbackEnabled = val }.store(in: &cancellables)
        $queueOverflowThreshold.dropFirst().sink { [weak self] val in self?.settings.queueOverflowThreshold = val }.store(in: &cancellables)
        $interAlertDelay.dropFirst().sink { [weak self] val in self?.settings.interAlertDelay = val }.store(in: &cancellables)
        $pushNotificationsEnabled
            .dropFirst()
            .sink { [weak self] val in
                self?.settings.pushNotificationsEnabled = val
                Task { await PushNotificationManager.shared.handleUserToggle(enabled: val) }
            }
            .store(in: &cancellables)
        $relayBaseURL.dropFirst().sink { [weak self] val in self?.settings.relayBaseURL = val }.store(in: &cancellables)
        $enabledAlertTypes.dropFirst().sink { [weak self] val in self?.settings.enabledAlertTypes = val }.store(in: &cancellables)
    }

    private func authorizationTitle(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "Not Asked"
        case .denied: "Denied"
        case .authorized: "Authorized"
        case .provisional: "Provisional"
        case .ephemeral: "Ephemeral"
        @unknown default: "Unknown"
        }
    }

    private func isoString(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return ISO8601DateFormatter().string(from: date)
    }

    private func shortIdentifier(_ value: String) -> String {
        guard value.count > 12 else { return value }
        return "\(value.prefix(6))...\(value.suffix(6))"
    }
}
