import AVFoundation
import os.log

/// Plays local alert sound files through AVAudioPlayer.
@MainActor
final class AudioPlaybackService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    
    static let shared = AudioPlaybackService()
    
    @Published private(set) var isPlaying = false
    
    private var audioPlayer: AVAudioPlayer?
    private var completionHandler: (() -> Void)?
    private let logger = Logger(subsystem: "com.irlalert.app", category: "AudioPlayback")
    
    private override init() {
        super.init()
    }
    
    // MARK: - Public API
    
    /// Play a sound from a local file URL.
    /// - Parameters:
    ///   - url: Local URL of the sound file
    ///   - volume: Playback volume (0.0 to 1.0)
    ///   - completion: Called when playback finishes or fails
    func playSound(from url: URL, volume: Float = 1.0, completion: @escaping () -> Void) {
        Task {
            guard url.isFileURL else {
                logger.error("Remote alert sound URLs are post-MVP: \(url.absoluteString)")
                completion()
                return
            }
            
            do {
                // Stop any existing playback
                stopCurrentPlayback()
                
                let player = try AVAudioPlayer(contentsOf: url)
                player.delegate = self
                player.volume = volume
                player.prepareToPlay()
                
                self.audioPlayer = player
                self.completionHandler = completion
                self.isPlaying = true
                
                if player.play() {
                    logger.info("Playing sound: \(url.lastPathComponent)")
                } else {
                    logger.error("AVAudioPlayer.play() returned false")
                    self.isPlaying = false
                    completion()
                }
            } catch {
                logger.error("Failed to create audio player: \(error.localizedDescription)")
                completion()
            }
        }
    }
    
    /// Stop any currently playing sound.
    func stopCurrentPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        // Don't call completion here — it's an explicit stop, not a natural finish
    }
    
    // MARK: - AVAudioPlayerDelegate
    
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.audioPlayer = nil
            
            let handler = self.completionHandler
            self.completionHandler = nil
            handler?()
            
            self.logger.info("Sound playback finished (success: \(flag))")
        }
    }
    
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor in
            self.isPlaying = false
            self.audioPlayer = nil
            
            let handler = self.completionHandler
            self.completionHandler = nil
            handler?()
            
            self.logger.error("Audio decode error: \(error?.localizedDescription ?? "unknown")")
        }
    }
}
