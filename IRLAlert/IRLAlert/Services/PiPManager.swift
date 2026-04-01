import AVFoundation
import AVKit
import Combine
import UIKit
import os.log

/// Manages Picture-in-Picture lifecycle for background execution.
///
/// Uses `PiPWindowHelper` to host an `AVPlayerViewController` in a dedicated
/// off-screen `UIWindow`. `AVPlayerViewController` handles PiP internally —
/// no separate `AVPictureInPictureController` is needed.
@MainActor
final class PiPManager: NSObject, ObservableObject {

    static let shared = PiPManager()

    // MARK: - Published State

    @Published private(set) var isActive: Bool = false
    @Published private(set) var isSupported: Bool = AVPictureInPictureController.isPictureInPictureSupported()

    // MARK: - Private

    private let logger = Logger(subsystem: "com.irlalert.app", category: "PiPManager")
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var playerTimeControlObservation: NSKeyValueObservation?
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var didSetup = false
    private var refreshTask: Task<Void, Never>?
    private var setupRetryCount = 0
    private var setupRetryTask: Task<Void, Never>?

    private let placeholderAssetVersion = 3

    private struct StatusSnapshot {
        var lastAlert: String = "IRL Alert Active"
        var isConnected: Bool = false
        var queueCount: Int = 0
    }

    private var statusSnapshot = StatusSnapshot()

    // MARK: - Public API

    /// Set up the PiP pipeline. Call after the app appears on screen.
    func setup() {
        guard !didSetup else { return }
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            logger.warning("PiP not supported on this device.")
            isSupported = false
            return
        }

        AudioSessionManager.shared.configureSession()
        createPlayerIfNeeded()

        guard let player else {
            logger.error("Failed to create AVPlayer for PiP.")
            return
        }

        guard let scene = findActiveWindowScene() else {
            logger.warning("No foreground UIWindowScene yet — will retry.")
            scheduleDeferredSetup()
            return
        }

        // Host AVPlayerViewController in a dedicated off-screen UIWindow.
        // AVPlayerViewController manages PiP automatically when its properties are set.
        PiPWindowHelper.shared.attach(player: player, to: scene)

        guard let pvc = PiPWindowHelper.shared.playerViewController else {
            logger.error("PiPWindowHelper failed to create AVPlayerViewController.")
            return
        }

        pvc.delegate = PiPWindowHelper.shared

        player.play()
        didSetup = true
        logger.info("PiP setup complete — AVPlayerViewController in off-screen UIWindow.")
    }

    /// Stop PiP when returning to foreground.
    func stopIfActive() {
        guard isActive else { return }
        // AVPlayerViewController's delegate tracks isActive; let the system handle dismissal
        // when app becomes foreground active. No manual stop needed — system dismisses PiP.
        logger.info("stopIfActive called — PiP will dismiss as app enters foreground.")
    }

    /// Update the status content shown in the PiP placeholder frame.
    func updateStatus(lastAlert: String? = nil, isConnected: Bool? = nil, queueCount: Int? = nil) {
        if let lastAlert, !lastAlert.isEmpty { statusSnapshot.lastAlert = lastAlert }
        if let isConnected { statusSnapshot.isConnected = isConnected }
        if let queueCount { statusSnapshot.queueCount = queueCount }
        schedulePlaceholderRefresh()
    }

    // MARK: - Player Setup

    private func createPlayerIfNeeded() {
        guard player == nil else { return }

        guard let item = makePlayerItem() else {
            logger.error("Failed to create player item for PiP.")
            return
        }

        playerItem = item
        observePlayerItem(item)

        NotificationCenter.default.addObserver(
            self, selector: #selector(loopPlayerItem),
            name: .AVPlayerItemDidPlayToEndTime, object: item
        )

        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = true
        newPlayer.actionAtItemEnd = .none
        newPlayer.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        player = newPlayer
        observePlayer(newPlayer)
    }

    private func makePlayerItem() -> AVPlayerItem? {
        if let bundled = Bundle.main.url(forResource: "pip_baseline", withExtension: "mp4") {
            return AVPlayerItem(url: bundled)
        }
        if let cached = placeholderFileURL(), FileManager.default.fileExists(atPath: cached.path) {
            return AVPlayerItem(url: cached)
        }
        generatePlaceholderAsync()
        // Remote fallback while placeholder is being generated
        let remoteURL = URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!
        return AVPlayerItem(url: remoteURL)
    }

    // MARK: - Player Observation

    private func observePlayer(_ player: AVPlayer) {
        playerTimeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] observed, _ in
            Task { @MainActor in
                if observed.timeControlStatus == .playing {
                    self?.logger.debug("Player playing.")
                }
            }
        }
    }

    private func observePlayerItem(_ item: AVPlayerItem) {
        playerItemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
            Task { @MainActor in
                switch observed.status {
                case .readyToPlay:
                    self?.logger.debug("Player item ready to play.")
                case .failed:
                    self?.logger.error("Player item failed: \(observed.error?.localizedDescription ?? "unknown")")
                default:
                    break
                }
            }
        }
    }

    @objc private func loopPlayerItem() {
        player?.seek(to: .zero)
        player?.play()
    }

    // MARK: - Deferred Setup

    private func scheduleDeferredSetup() {
        guard setupRetryCount < 5 else {
            logger.error("PiP setup failed: no UIWindowScene available after 5 retries.")
            return
        }
        setupRetryCount += 1
        setupRetryTask?.cancel()
        setupRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self?.didSetup = false
            self?.setup()
        }
    }

    // MARK: - Placeholder Video Generation

    private func placeholderFileURL() -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return caches.appendingPathComponent("pip_placeholder_v\(placeholderAssetVersion).mp4")
    }

    private func generatePlaceholderAsync() {
        guard let url = placeholderFileURL() else { return }
        guard !FileManager.default.fileExists(atPath: url.path) else { return }

        let targetURL = url
        Task { @MainActor [weak self] in
            await self?.generatePlaceholderVideo(at: targetURL)
            guard let self, let url = self.placeholderFileURL(),
                  FileManager.default.fileExists(atPath: url.path) else { return }
            let item = AVPlayerItem(url: url)
            self.swapPlayerItem(item)
        }
    }

    private func schedulePlaceholderRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self else { return }
            guard let url = self.placeholderFileURL() else { return }
            try? FileManager.default.removeItem(at: url)
            await self.generatePlaceholderVideo(at: url)
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let item = AVPlayerItem(url: url)
            self.swapPlayerItem(item)
        }
    }

    private func swapPlayerItem(_ item: AVPlayerItem) {
        if let old = playerItem {
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: old)
        }
        playerItem = item
        observePlayerItem(item)
        NotificationCenter.default.addObserver(
            self, selector: #selector(loopPlayerItem),
            name: .AVPlayerItemDidPlayToEndTime, object: item
        )
        player?.replaceCurrentItem(with: item)
        if isActive { player?.play() }
    }

    private func generatePlaceholderVideo(at url: URL) async {
        let width = 320, height = 180
        let fps: Int32 = 30

        do {
            let tempVideoURL = url.deletingLastPathComponent().appendingPathComponent("pip_temp_video.mp4")
            let tempAudioURL = url.deletingLastPathComponent().appendingPathComponent("pip_temp_audio.caf")
            try? FileManager.default.removeItem(at: tempVideoURL)
            try? FileManager.default.removeItem(at: tempAudioURL)

            try await writeVideoTrack(to: tempVideoURL, width: width, height: height, fps: fps)
            try writeSilentAudioTrack(to: tempAudioURL, duration: 1.0)
            try await mergeMedia(videoURL: tempVideoURL, audioURL: tempAudioURL, outputURL: url)

            try? FileManager.default.removeItem(at: tempVideoURL)
            try? FileManager.default.removeItem(at: tempAudioURL)
        } catch {
            logger.error("Placeholder generation failed: \(error.localizedDescription)")
        }
    }

    private func writeVideoTrack(to url: URL, width: Int, height: Int, fps: Int32) async throws {
        let writer = try AVAssetWriter(url: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )

        guard writer.canAdd(input) else {
            throw NSError(domain: "PiP", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input."])
        }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameCount = fps
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            guard let buffer = makeStatusFrame(width: width, height: height) else { continue }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }

        input.markAsFinished()
        await withCheckedContinuation { c in writer.finishWriting { c.resume() } }

        if writer.status != .completed {
            throw writer.error ?? NSError(domain: "PiP", code: 2)
        }
    }

    private func writeSilentAudioTrack(to url: URL, duration: Double) throws {
        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else {
            throw NSError(domain: "PiP", code: 3)
        }
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "PiP", code: 4)
        }
        buffer.frameLength = frameCount
        if let data = buffer.floatChannelData {
            memset(data[0], 0, Int(frameCount) * MemoryLayout<Float>.size)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }

    private func mergeMedia(videoURL: URL, audioURL: URL, outputURL: URL) async throws {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        let duration = try await videoAsset.load(.duration)

        if let vTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
           let cTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try cTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: vTrack, at: .zero)
            cTrack.preferredTransform = try await vTrack.load(.preferredTransform)
        }
        if let aTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
           let cTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try cTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: aTrack, at: .zero)
        }

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "PiP", code: 5)
        }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        await withCheckedContinuation { c in session.exportAsynchronously { c.resume() } }
        if session.status != .completed {
            throw session.error ?? NSError(domain: "PiP", code: 6)
        }
    }

    private func makeStatusFrame(width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB,
                            [kCVPixelBufferCGImageCompatibilityKey as String: true,
                             kCVPixelBufferCGBitmapContextCompatibilityKey as String: true] as CFDictionary,
                            &pixelBuffer)
        guard let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: colorSpace, bitmapInfo: bitmapInfo) else { return nil }

        ctx.setFillColor(UIColor(red: 0.06, green: 0.10, blue: 0.16, alpha: 1.0).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1.0, y: -1.0)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let dotColor = statusSnapshot.isConnected ? UIColor.systemGreen : UIColor.systemRed
        ctx.setFillColor(dotColor.cgColor)
        ctx.fillEllipse(in: CGRect(x: 16, y: 16, width: 10, height: 10))

        let title = statusSnapshot.lastAlert.isEmpty ? "IRL Alert Active" : statusSnapshot.lastAlert
        title.draw(in: CGRect(x: 0, y: CGFloat(height) * 0.45, width: CGFloat(width), height: 24),
                   withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20), .foregroundColor: UIColor.white, .paragraphStyle: paragraph])

        let connectionText = statusSnapshot.isConnected ? "Connected" : "Disconnected"
        let subtitle = "\(connectionText) • Queue \(statusSnapshot.queueCount)"
        subtitle.draw(in: CGRect(x: 0, y: CGFloat(height) * 0.45 + 24, width: CGFloat(width), height: 18),
                      withAttributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.white.withAlphaComponent(0.75), .paragraphStyle: paragraph])

        return buffer
    }

    // MARK: - Helpers

    private func findActiveWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
}
