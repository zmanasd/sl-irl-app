import AVFoundation
import os.log

/// Plays a silent audio loop to keep the app alive in the background.
/// iOS suspends apps that aren't actively using audio — this silent track
/// tricks the system into keeping our process running so we can receive
/// WebSocket events and play alerts at any time.
@MainActor
final class SilentAudioPlayer: ObservableObject {
    
    static let shared = SilentAudioPlayer()
    
    @Published private(set) var isPlaying = false
    
    private var audioPlayer: AVAudioPlayer?
    private let logger = Logger(subsystem: "com.irlalert.app", category: "SilentAudio")
    
    private init() {}
    
    // MARK: - Public API
    
    /// Start playing the silent audio loop. The audio session must already be configured.
    func start() {
        guard !isPlaying else {
            logger.info("Silent audio already playing, skipping start()")
            return
        }
        
        do {
            let player = try createSilentPlayer()
            player.numberOfLoops = -1 // Loop forever
            player.volume = 0.01 // Near-silent but not zero (zero can be optimized away)
            
            if player.play() {
                audioPlayer = player
                isPlaying = true
                logger.info("Silent audio loop started — background mode active")
            } else {
                logger.error("AVAudioPlayer.play() returned false")
            }
        } catch {
            logger.error("Failed to start silent audio: \(error.localizedDescription)")
        }
    }
    
    /// Stop the silent audio loop. Only call this when the user explicitly
    /// wants to disconnect all services and stop background processing.
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        logger.info("Silent audio loop stopped — background mode inactive")
    }
    
    // MARK: - Silent Audio Generation
    
    /// Creates an AVAudioPlayer that plays a programmatically generated silent WAV file.
    /// No bundled audio file needed — we generate the PCM data in memory.
    private func createSilentPlayer() throws -> AVAudioPlayer {
        let sampleRate: Double = 44100
        let duration: Double = 1.0 // 1 second of silence, looped
        let numSamples = Int(sampleRate * duration)
        
        // Generate minimal WAV file in memory (16-bit PCM, mono, silence)
        var wavData = Data()
        
        // WAV Header (44 bytes)
        let dataSize = numSamples * 2 // 16-bit = 2 bytes per sample
        let fileSize = 36 + dataSize
        
        wavData.append(contentsOf: "RIFF".utf8)                          // ChunkID
        wavData.append(littleEndianUInt32(UInt32(fileSize)))             // ChunkSize
        wavData.append(contentsOf: "WAVE".utf8)                          // Format
        wavData.append(contentsOf: "fmt ".utf8)                          // Subchunk1ID
        wavData.append(littleEndianUInt32(16))                           // Subchunk1Size (PCM)
        wavData.append(littleEndianUInt16(1))                            // AudioFormat (1 = PCM)
        wavData.append(littleEndianUInt16(1))                            // NumChannels (mono)
        wavData.append(littleEndianUInt32(UInt32(sampleRate)))           // SampleRate
        wavData.append(littleEndianUInt32(UInt32(sampleRate) * 2))       // ByteRate
        wavData.append(littleEndianUInt16(2))                            // BlockAlign
        wavData.append(littleEndianUInt16(16))                           // BitsPerSample
        wavData.append(contentsOf: "data".utf8)                          // Subchunk2ID
        wavData.append(littleEndianUInt32(UInt32(dataSize)))             // Subchunk2Size
        
        // PCM data — all zeros = silence
        wavData.append(Data(count: dataSize))
        
        return try AVAudioPlayer(data: wavData)
    }
    
    // MARK: - Binary Helpers
    
    private func littleEndianUInt32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
    
    private func littleEndianUInt16(_ value: UInt16) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
