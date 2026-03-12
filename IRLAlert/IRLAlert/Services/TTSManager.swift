import AVFoundation
import os.log

/// Text-to-Speech manager wrapping AVSpeechSynthesizer.
/// Reads out alert details (e.g. "TestUser donated $5.00. Great stream!").
@MainActor
final class TTSManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    
    static let shared = TTSManager()
    
    @Published private(set) var isSpeaking = false
    
    private let synthesizer = AVSpeechSynthesizer()
    private var completionHandler: (() -> Void)?
    private let logger = Logger(subsystem: "com.irlalert.app", category: "TTS")
    
    private override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    // MARK: - Public API
    
    /// Speak the given text, then call completion when done.
    /// - Parameters:
    ///   - text: The text to speak
    ///   - rate: Speech rate (0.0 to 1.0, default AVSpeechUtteranceDefaultSpeechRate)
    ///   - volume: Speech volume (0.0 to 1.0)
    ///   - completion: Called when speech finishes or is cancelled
    func speak(
        _ text: String,
        rate: Float = AVSpeechUtteranceDefaultSpeechRate,
        volume: Float = 1.0,
        completion: @escaping () -> Void
    ) {
        // Stop any in-progress speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.volume = volume
        utterance.pitchMultiplier = 1.0
        
        // Use high-quality voice if available
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }
        
        // Small pre-speech delay for natural feel
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.2
        
        self.completionHandler = completion
        self.isSpeaking = true
        
        synthesizer.speak(utterance)
        logger.info("TTS started: \"\(text.prefix(60))...\"")
    }
    
    /// Stop any in-progress speech immediately.
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        completionHandler = nil
    }
    
    /// Get available voice identifiers for the settings UI
    static var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.starts(with: "en") }
            .sorted { $0.name < $1.name }
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            
            let handler = self.completionHandler
            self.completionHandler = nil
            handler?()
            
            self.logger.info("TTS finished")
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            
            let handler = self.completionHandler
            self.completionHandler = nil
            handler?()
            
            self.logger.info("TTS cancelled")
        }
    }
}
