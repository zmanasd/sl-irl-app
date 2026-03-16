import AVFoundation
import AVKit
import Combine
import UIKit
import os.log

/// Manages Picture-in-Picture lifecycle for background execution.
@MainActor
final class PiPManager: NSObject, ObservableObject {

    static let shared = PiPManager()

    @Published private(set) var isActive: Bool = false
    @Published private(set) var isSupported: Bool = AVPictureInPictureController.isPictureInPictureSupported()
    @Published private(set) var isPossible: Bool = false
    @Published private(set) var hasAttachedPlayerLayer: Bool = false
    @Published private(set) var hasAttachedPlayerViewController: Bool = false
    @Published private(set) var hasPiPController: Bool = false
    @Published private(set) var isBoundLayerStable: Bool = false
    @Published private(set) var isReadyForDisplay: Bool = false
    @Published private(set) var itemStatusDescription: String = "unknown"
    @Published private(set) var timeControlDescription: String = "idle"
    @Published private(set) var lastFailureReason: String = "none"
    @Published private(set) var lastStartAttemptSource: String = "none"
    @Published private(set) var pendingDeferredStartSource: String = "none"

    private enum PlaybackMode {
        case baselineRealMedia
        case statusPlaceholder

        var debugLabel: String {
            switch self {
            case .baselineRealMedia:
                return "baseline-real-media"
            case .statusPlaceholder:
                return "status-placeholder"
            }
        }
    }

    private let logger = Logger(subsystem: "com.irlalert.app", category: "PiPManager")
    private let placeholderAssetVersion = 2
    private let baselineMediaURL = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8")
#if DEBUG
    private let playbackMode: PlaybackMode = .baselineRealMedia
#else
    private let playbackMode: PlaybackMode = .statusPlaceholder
#endif
    private var pipController: AVPictureInPictureController?
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var playerLayer: AVPlayerLayer?
    private weak var playerViewController: AVPlayerViewController?
    private var pipPossibleObservation: NSKeyValueObservation?
    private var playerLayerReadyObservation: NSKeyValueObservation?
    private var playerTimeControlObservation: NSKeyValueObservation?
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var didPrepare = false
    private var isGeneratingPlaceholder = false
    private var startRetryCount = 0
    private let maxStartRetryCount = 3
    private var refreshTask: Task<Void, Never>?
    private var deferredStartSource: String?

    private struct PiPStatusSnapshot {
        var lastAlert: String
        var isConnected: Bool
        var queueCount: Int
    }

    private var statusSnapshot = PiPStatusSnapshot(
        lastAlert: "IRL Alert Active",
        isConnected: false,
        queueCount: 0
    )

    var isBaselineRealMediaMode: Bool {
        playbackMode == .baselineRealMedia
    }

    var playbackModeDebugLabel: String {
        playbackMode.debugLabel
    }

    // MARK: - Public API

    func prepareIfNeeded() {
        if didPrepare, pipController != nil { return }

        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            logger.warning("PiP not supported on this device.")
            isSupported = false
            lastFailureReason = "PiP unsupported on this device"
            return
        }

        // Step 2 ordering: activate audio session before creating/starting PiP controller.
        AudioSessionManager.shared.configureSession()
        setupPlayerLayerIfNeeded()
        bindPlayerLayerFromHostedControllerIfNeeded()

        guard let playerLayer else {
            logger.warning("PiP player layer missing. Provide a PiP video source.")
            lastFailureReason = playerViewController == nil
                ? "PiP host not attached yet"
                : "PiP player layer missing (host not ready)"
            return
        }

        ensurePiPControllerBoundToInitialLayer(playerLayer)
        player?.play()
        refreshDebugState()
        didPrepare = true
    }

    func startIfPossible(source: String = "app", force: Bool = false) {
        lastStartAttemptSource = source
        prepareIfNeeded()
        bindPlayerLayerFromHostedControllerIfNeeded()
        refreshDebugState()
        guard let pipController else {
            queueDeferredStart(source: source)
            lastFailureReason = "No PiP controller available"
            if !force {
                scheduleStartRetry(source: source)
            }
            return
        }
        player?.play()
        guard force || pipController.isPictureInPicturePossible else {
            logger.warning("PiP not possible. Ensure a valid video source is active.")
            queueDeferredStart(source: source)
            lastFailureReason = "PiP not possible yet"
            scheduleStartRetry(source: source)
            return
        }
        startRetryCount = 0
        clearDeferredStart()
        lastFailureReason = "none"
        pipController.startPictureInPicture()
    }

    func stopIfActive() {
        guard let pipController, pipController.isPictureInPictureActive else { return }
        pipController.stopPictureInPicture()
    }

    /// Optionally provide a custom player layer (e.g., for a richer PiP view).
    func setPlayerLayer(_ layer: AVPlayerLayer) {
        if playerLayer === layer {
            observePlayerLayer(layer)
            setupPlayerLayerIfNeeded()
            ensurePiPControllerBoundToInitialLayer(layer)
            return
        }
        layer.videoGravity = .resizeAspectFill
        playerLayer = layer
        hasAttachedPlayerLayer = true
        observePlayerLayer(layer)
        setupPlayerLayerIfNeeded()
        ensurePiPControllerBoundToInitialLayer(layer)
        refreshDebugState()
        attemptDeferredStartIfPossible(trigger: "player layer attached")
        didPrepare = true
    }

    /// Attach a hosted AVPlayerViewController so PiP uses AVKit-native playback surfaces.
    func setPlayerViewController(_ controller: AVPlayerViewController) {
        if playerViewController !== controller {
            playerViewController = controller
        }
        hasAttachedPlayerViewController = true
        configurePlayerViewController(controller)
        setupPlayerLayerIfNeeded()
        bindPlayerLayerFromHostedControllerIfNeeded()
        refreshDebugState()
        attemptDeferredStartIfPossible(trigger: "host attached")
        didPrepare = true
    }

    func updateStatus(lastAlert: String? = nil, isConnected: Bool? = nil, queueCount: Int? = nil) {
        if let lastAlert, !lastAlert.isEmpty {
            statusSnapshot.lastAlert = lastAlert
        }
        if let isConnected {
            statusSnapshot.isConnected = isConnected
        }
        if let queueCount {
            statusSnapshot.queueCount = queueCount
        }

        if playbackMode == .statusPlaceholder {
            schedulePlaceholderRefresh()
        }
    }

    func ensurePreviewPlayback() {
        guard playerViewController != nil || playerLayer != nil else {
            lastFailureReason = "Waiting for PiP host attachment"
            return
        }
        prepareIfNeeded()
        player?.play()
        refreshDebugState()
    }

    // MARK: - Private Helpers

    private func setupPlayerLayerIfNeeded() {
        if player == nil {
            guard let item = makeInitialPlayerItem() else {
                if playbackMode == .baselineRealMedia {
                    lastFailureReason = "Baseline media source unavailable"
                } else {
                    lastFailureReason = "PiP placeholder unavailable"
                }
                return
            }
            setPlayerItem(item)
            let newPlayer = AVPlayer(playerItem: item)
            newPlayer.isMuted = playbackMode != .baselineRealMedia
            newPlayer.actionAtItemEnd = .none
            newPlayer.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
            newPlayer.automaticallyWaitsToMinimizeStalling = true
            player = newPlayer
            observePlayer(newPlayer)
        }

        if let playerViewController {
            configurePlayerViewController(playerViewController)
        }

        if let player {
            if let existingLayer = playerLayer {
                if existingLayer.player !== player {
                    existingLayer.player = player
                }
            }
        }

        bindPlayerLayerFromHostedControllerIfNeeded()
        if let playerLayer {
            ensurePiPControllerBoundToInitialLayer(playerLayer)
        }

        refreshDebugState()
    }

    private func makeInitialPlayerItem() -> AVPlayerItem? {
        switch playbackMode {
        case .baselineRealMedia:
            if let bundledClip = Bundle.main.url(forResource: "pip_baseline", withExtension: "mp4") {
                return AVPlayerItem(url: bundledClip)
            }
            guard let baselineMediaURL else { return nil }
            return AVPlayerItem(url: baselineMediaURL)
        case .statusPlaceholder:
            guard let url = placeholderVideoURL() else { return nil }
            return AVPlayerItem(url: url)
        }
    }

    private func ensurePiPControllerBoundToInitialLayer(_ layer: AVPlayerLayer) {
        if pipController == nil {
            guard isLayerStableForPiP(layer) else {
                logger.debug("Deferring PiP controller creation until player layer is stable in window.")
                return
            }
            pipController = makePiPController(for: layer)
            return
        }

        guard let existingLayer = pipController?.playerLayer, existingLayer !== layer else { return }
        if !isLayerStableForPiP(existingLayer), isLayerStableForPiP(layer), !isActive {
            logger.notice("Rebinding PiP controller once from unstable initial layer to stable layer.")
            pipController = makePiPController(for: layer)
            return
        }

        logger.notice("Ignoring player-layer rebind to preserve single PiP controller lifetime.")
    }

    private func isLayerStableForPiP(_ layer: AVPlayerLayer) -> Bool {
        let inHierarchy = layer.superlayer != nil
        let hasSize = !layer.bounds.isEmpty
        let hostHasWindow = playerViewController?.view.window != nil || playerViewController == nil
        return inHierarchy && hasSize && hostHasWindow
    }

    private func queueDeferredStart(source: String) {
        deferredStartSource = source
        pendingDeferredStartSource = source
    }

    private func clearDeferredStart() {
        deferredStartSource = nil
        pendingDeferredStartSource = "none"
    }

    private func attemptDeferredStartIfPossible(trigger: String) {
        guard let pipController, let queuedSource = deferredStartSource else { return }
        guard pipController.isPictureInPicturePossible else { return }

        clearDeferredStart()
        startRetryCount = 0
        lastStartAttemptSource = "\(queuedSource) -> \(trigger)"
        lastFailureReason = "none"
        pipController.startPictureInPicture()
    }

    private func configurePlayerViewController(_ controller: AVPlayerViewController) {
        controller.player = player
        controller.showsPlaybackControls = false
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.updatesNowPlayingInfoCenter = false
        controller.videoGravity = .resizeAspectFill
    }

    private func bindPlayerLayerFromHostedControllerIfNeeded() {
        guard let playerViewController else { return }
        guard let discoveredLayer = findPlayerLayer(in: playerViewController.view.layer) else {
            hasAttachedPlayerLayer = playerLayer != nil
            return
        }

        if discoveredLayer.player !== player {
            discoveredLayer.player = player
        }

        if playerLayer !== discoveredLayer {
            playerLayer = discoveredLayer
            observePlayerLayer(discoveredLayer)
        }

        ensurePiPControllerBoundToInitialLayer(discoveredLayer)
        hasAttachedPlayerLayer = true
    }

    private func findPlayerLayer(in rootLayer: CALayer?) -> AVPlayerLayer? {
        guard let rootLayer else { return nil }
        if let foundLayer = rootLayer as? AVPlayerLayer {
            return foundLayer
        }
        for sublayer in rootLayer.sublayers ?? [] {
            if let foundLayer = findPlayerLayer(in: sublayer) {
                return foundLayer
            }
        }
        return nil
    }

    private func makePiPController(for playerLayer: AVPlayerLayer) -> AVPictureInPictureController? {
        guard let controller = AVPictureInPictureController(playerLayer: playerLayer) else {
            logger.error("Failed to create PiP controller for player layer.")
            lastFailureReason = "Failed to create PiP controller"
            return nil
        }

        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.requiresLinearPlayback = false
        pipPossibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] observedController, _ in
            let isPossible = observedController.isPictureInPicturePossible
            Task { @MainActor in
                self?.isPossible = isPossible
                if isPossible {
                    self?.attemptDeferredStartIfPossible(trigger: "possible=true")
                }
            }
        }
        return controller
    }

    private func observePlayer(_ player: AVPlayer) {
        playerTimeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] observedPlayer, _ in
            let description: String
            switch observedPlayer.timeControlStatus {
            case .paused:
                description = "paused"
            case .waitingToPlayAtSpecifiedRate:
                description = "waiting"
            case .playing:
                description = "playing"
            @unknown default:
                description = "unknown"
            }

            Task { @MainActor in
                self?.timeControlDescription = description
            }
        }
    }

    private func observePlayerLayer(_ layer: AVPlayerLayer) {
        playerLayerReadyObservation = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] observedLayer, _ in
            let ready = observedLayer.isReadyForDisplay
            Task { @MainActor in
                self?.isReadyForDisplay = ready
            }
        }
    }

    @objc private func loopPlayerItem() {
        player?.seek(to: .zero)
        player?.play()
    }

    private func placeholderFileURL() -> URL? {
        let fileManager = FileManager.default
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            logger.error("Unable to locate caches directory for PiP placeholder.")
            return nil
        }

        return caches.appendingPathComponent("pip_placeholder_v\(placeholderAssetVersion).mp4")
    }

    private func placeholderVideoURL() -> URL? {
        let fileManager = FileManager.default
        guard let url = placeholderFileURL() else { return nil }
        if fileManager.fileExists(atPath: url.path) {
            return url
        }

        guard !isGeneratingPlaceholder else { return nil }
        isGeneratingPlaceholder = true

        Task.detached { [weak self] in
            await self?.generatePlaceholderVideo(at: url)
            await MainActor.run {
                PiPManager.shared.setupPlayerLayerIfNeeded()
            }
        }

        return nil
    }

    private func scheduleStartRetry(source: String) {
        guard startRetryCount < maxStartRetryCount else { return }
        startRetryCount += 1
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            self.startIfPossible(source: "\(source) retry \(self.startRetryCount)")
        }
    }

    private func schedulePlaceholderRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            await self?.regeneratePlaceholderVideo()
        }
    }

    private func setPlayerItem(_ item: AVPlayerItem) {
        if let existing = playerItem {
            NotificationCenter.default.removeObserver(
                self,
                name: .AVPlayerItemDidPlayToEndTime,
                object: existing
            )
        }

        playerItem = item
        observePlayerItem(item)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(loopPlayerItem),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
    }

    private func observePlayerItem(_ item: AVPlayerItem) {
        playerItemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            let description: String
            switch observedItem.status {
            case .unknown:
                description = "unknown"
            case .readyToPlay:
                description = "ready"
            case .failed:
                description = "failed"
            @unknown default:
                description = "unknown"
            }

            Task { @MainActor in
                self?.itemStatusDescription = description
                if observedItem.status == .failed {
                    self?.lastFailureReason = observedItem.error?.localizedDescription ?? "Player item failed"
                }
            }
        }
    }

    private func regeneratePlaceholderVideo() async {
        guard let url = placeholderFileURL() else { return }
        guard !isGeneratingPlaceholder else { return }
        isGeneratingPlaceholder = true
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            // ignore
        }

        await generatePlaceholderVideo(at: url)

        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let item = AVPlayerItem(url: url)
        setPlayerItem(item)
        player?.replaceCurrentItem(with: item)
        if isActive {
            player?.play()
        }
    }

    private func generatePlaceholderVideo(at url: URL) async {
        defer {
            Task { @MainActor in
                self.isGeneratingPlaceholder = false
                self.setupPlayerLayerIfNeeded()
            }
        }

        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            // Ignore if file didn't exist
        }

        let width = 320
        let height = 180
        let fps: Int32 = 30
        let durationSeconds = 1
        let tempVideoURL = url.deletingLastPathComponent().appendingPathComponent("pip_placeholder_video.mp4")
        let tempAudioURL = url.deletingLastPathComponent().appendingPathComponent("pip_placeholder_audio.caf")

        do {
            try FileManager.default.removeItem(at: tempVideoURL)
        } catch {
            // Ignore if file didn't exist
        }

        do {
            try FileManager.default.removeItem(at: tempAudioURL)
        } catch {
            // Ignore if file didn't exist
        }

        do {
            try await writePlaceholderVideoOnly(
                to: tempVideoURL,
                width: width,
                height: height,
                fps: fps,
                durationSeconds: durationSeconds,
                snapshot: statusSnapshot
            )
            try writeSilentAudioTrack(to: tempAudioURL, durationSeconds: Double(durationSeconds))
            try await mergePlaceholderMedia(videoURL: tempVideoURL, audioURL: tempAudioURL, outputURL: url)
        } catch {
            logger.error("Failed to generate PiP placeholder: \(error.localizedDescription)")
        }

        try? FileManager.default.removeItem(at: tempVideoURL)
        try? FileManager.default.removeItem(at: tempAudioURL)
    }

    private func writePlaceholderVideoOnly(
        to url: URL,
        width: Int,
        height: Int,
        fps: Int32,
        durationSeconds: Int,
        snapshot: PiPStatusSnapshot
    ) async throws {
        let frameCount = fps * Int32(durationSeconds)
        let writer = try AVAssetWriter(url: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attributes
        )

        guard writer.canAdd(input) else {
            throw NSError(domain: "PiPPlaceholder", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unable to add video input to AVAssetWriter."
            ])
        }
        writer.add(input)

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }

            guard let buffer = makePixelBuffer(width: width, height: height, snapshot: snapshot) else { continue }
            let time = CMTime(value: CMTimeValue(frame), timescale: fps)
            adaptor.append(buffer, withPresentationTime: time)
        }

        input.markAsFinished()

        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }

        if writer.status != .completed {
            throw writer.error ?? NSError(domain: "PiPPlaceholder", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Video writer failed to finish."
            ])
        }
    }

    private func writeSilentAudioTrack(to url: URL, durationSeconds: Double) throws {
        let sampleRate = 44_100.0
        let channelCount: AVAudioChannelCount = 1
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) else {
            throw NSError(domain: "PiPPlaceholder", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Unable to create audio format."
            ])
        }

        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "PiPPlaceholder", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Unable to create silent audio buffer."
            ])
        }

        buffer.frameLength = frameCount
        if let channelData = buffer.floatChannelData {
            for channel in 0..<Int(channelCount) {
                memset(channelData[channel], 0, Int(frameCount) * MemoryLayout<Float>.size)
            }
        }

        let audioFile = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try audioFile.write(from: buffer)
    }

    private func mergePlaceholderMedia(videoURL: URL, audioURL: URL, outputURL: URL) async throws {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)

        let duration = try await videoAsset.load(.duration)
        guard let sourceVideoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw NSError(domain: "PiPPlaceholder", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "Unable to load placeholder video track."
            ])
        }

        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: sourceVideoTrack,
            at: .zero
        )
        compositionVideoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        if let sourceAudioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: sourceAudioTrack,
                at: .zero
            )
        }

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw NSError(domain: "PiPPlaceholder", code: 6, userInfo: [
                NSLocalizedDescriptionKey: "Unable to create export session for placeholder asset."
            ])
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = false

        await withCheckedContinuation { continuation in
            exportSession.exportAsynchronously {
                continuation.resume()
            }
        }

        if exportSession.status != .completed {
            throw exportSession.error ?? NSError(domain: "PiPPlaceholder", code: 7, userInfo: [
                NSLocalizedDescriptionKey: "Merged placeholder export failed."
            ])
        }
    }

    private func makePixelBuffer(width: Int, height: Int, snapshot: PiPStatusSnapshot) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            if let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) {
                let background = UIColor(red: 0.06, green: 0.10, blue: 0.16, alpha: 1.0)
                context.setFillColor(background.cgColor)
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))

                context.translateBy(x: 0, y: CGFloat(height))
                context.scaleBy(x: 1.0, y: -1.0)

                let title = snapshot.lastAlert.isEmpty ? "IRL Alert Active" : snapshot.lastAlert
                let connectionText = snapshot.isConnected ? "Connected" : "Disconnected"
                let subtitle = "\(connectionText) • Queue \(snapshot.queueCount)"

                let dotColor = snapshot.isConnected ? UIColor.systemGreen : UIColor.systemRed
                context.setFillColor(dotColor.cgColor)
                context.fillEllipse(in: CGRect(x: 16, y: 16, width: 10, height: 10))

                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center

                let titleAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 20),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraph
                ]

                let subtitleAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.75),
                    .paragraphStyle: paragraph
                ]

                let titleRect = CGRect(x: 0, y: CGFloat(height) * 0.45, width: CGFloat(width), height: 24)
                let subtitleRect = CGRect(x: 0, y: CGFloat(height) * 0.45 + 24, width: CGFloat(width), height: 18)

                title.draw(in: titleRect, withAttributes: titleAttributes)
                subtitle.draw(in: subtitleRect, withAttributes: subtitleAttributes)
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        return buffer
    }

    private func refreshDebugState() {
        isSupported = AVPictureInPictureController.isPictureInPictureSupported()
        hasAttachedPlayerViewController = playerViewController != nil
        hasPiPController = pipController != nil
        hasAttachedPlayerLayer = playerLayer != nil
        isReadyForDisplay = playerLayer?.isReadyForDisplay ?? false
        if let boundLayer = pipController?.playerLayer {
            isBoundLayerStable = isLayerStableForPiP(boundLayer)
        } else {
            isBoundLayerStable = false
        }
        isPossible = pipController?.isPictureInPicturePossible ?? false
        if let item = player?.currentItem {
            switch item.status {
            case .unknown:
                itemStatusDescription = "unknown"
            case .readyToPlay:
                itemStatusDescription = "ready"
            case .failed:
                itemStatusDescription = "failed"
            @unknown default:
                itemStatusDescription = "unknown"
            }
        } else {
            itemStatusDescription = "missing"
        }

        if let player {
            switch player.timeControlStatus {
            case .paused:
                timeControlDescription = "paused"
            case .waitingToPlayAtSpecifiedRate:
                timeControlDescription = "waiting"
            case .playing:
                timeControlDescription = "playing"
            @unknown default:
                timeControlDescription = "unknown"
            }
        } else {
            timeControlDescription = "missing"
        }
    }
}

extension PiPManager: @preconcurrency AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = true
        lastFailureReason = "none"
        refreshDebugState()
        logger.info("PiP starting.")
        Task { await RelayClient.shared.updatePresence(directConnectionActive: true) }
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        logger.info("PiP stopping.")
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = false
        refreshDebugState()
        logger.info("PiP stopped.")
        Task { await RelayClient.shared.updatePresence(directConnectionActive: UIApplication.shared.applicationState == .active) }
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        let nsError = error as NSError
        lastFailureReason = "\(nsError.domain) (\(nsError.code)): \(nsError.localizedDescription)"
        queueDeferredStart(source: lastStartAttemptSource)
        refreshDebugState()
        logger.error("PiP failed to start: \(error.localizedDescription)")
    }
}
