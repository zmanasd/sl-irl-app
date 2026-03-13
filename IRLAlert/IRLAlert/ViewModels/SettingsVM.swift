import Foundation
import AVFoundation
import Combine

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
    @Published var disconnectNotificationTimeout: Double
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
        disconnectNotificationTimeout = settings.disconnectNotificationTimeout
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
        disconnectNotificationTimeout = 30.0
        enabledAlertTypes = Set(AlertType.allCases)
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
        $disconnectNotificationTimeout.dropFirst().sink { [weak self] val in self?.settings.disconnectNotificationTimeout = val }.store(in: &cancellables)
        $enabledAlertTypes.dropFirst().sink { [weak self] val in self?.settings.enabledAlertTypes = val }.store(in: &cancellables)
    }
}
