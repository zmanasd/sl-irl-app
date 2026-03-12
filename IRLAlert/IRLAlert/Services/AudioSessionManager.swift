import AVFoundation
import Combine
import os.log

/// Manages the AVAudioSession for background audio playback.
/// Configures the session for `.playback` with `.mixWithOthers` so alert sounds
/// play over other audio (e.g. Spotify, Apple Music) without pausing them.
@MainActor
final class AudioSessionManager: ObservableObject {
    
    static let shared = AudioSessionManager()
    
    @Published private(set) var isSessionActive = false
    @Published private(set) var currentRoute: String = "Unknown"
    
    private let logger = Logger(subsystem: "com.irlalert.app", category: "AudioSession")
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupNotifications()
    }
    
    // MARK: - Session Configuration
    
    /// Configure and activate the audio session for background alert playback.
    /// Must be called early in the app lifecycle (e.g. on app launch).
    func configureSession() {
        let session = AVAudioSession.sharedInstance()
        
        do {
            // .playback = audio continues when screen locks / app backgrounds
            // .mixWithOthers = our alerts mix over Spotify/Music instead of pausing them
            // .duckOthers = briefly lower other audio volume while our alert plays
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers, .duckOthers]
            )
            
            try session.setActive(true)
            isSessionActive = true
            currentRoute = describeCurrentRoute(session)
            
            logger.info("Audio session configured: category=playback, mixWithOthers+duckOthers, active=true")
        } catch {
            logger.error("Failed to configure audio session: \(error.localizedDescription)")
            isSessionActive = false
        }
    }
    
    /// Deactivate the audio session (e.g. when user explicitly stops all alerts).
    func deactivateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            isSessionActive = false
            logger.info("Audio session deactivated")
        } catch {
            logger.error("Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Interruption Handling
    
    private func setupNotifications() {
        // Handle audio interruptions (phone calls, Siri, alarms)
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleInterruption(notification)
            }
            .store(in: &cancellables)
        
        // Handle route changes (headphones unplugged, Bluetooth disconnects)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleRouteChange(notification)
            }
            .store(in: &cancellables)
    }
    
    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }
        
        switch type {
        case .began:
            logger.info("Audio interruption began (phone call, Siri, etc.)")
            isSessionActive = false
            
        case .ended:
            logger.info("Audio interruption ended — reactivating session")
            // Check if we should resume playback
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    configureSession() // Re-activate
                }
            }
            
        @unknown default:
            logger.warning("Unknown audio interruption type: \(typeValue)")
        }
    }
    
    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }
        
        let session = AVAudioSession.sharedInstance()
        currentRoute = describeCurrentRoute(session)
        
        switch reason {
        case .oldDeviceUnavailable:
            logger.info("Audio route: device removed (headphones unplugged). Route: \(self.currentRoute)")
        case .newDeviceAvailable:
            logger.info("Audio route: new device connected. Route: \(self.currentRoute)")
        case .routeConfigurationChange:
            logger.info("Audio route configuration changed. Route: \(self.currentRoute)")
        default:
            logger.info("Audio route changed (reason: \(reasonValue)). Route: \(self.currentRoute)")
        }
    }
    
    // MARK: - Helpers
    
    private func describeCurrentRoute(_ session: AVAudioSession) -> String {
        let outputs = session.currentRoute.outputs
        if outputs.isEmpty { return "No output" }
        return outputs.map { $0.portName }.joined(separator: ", ")
    }
}
