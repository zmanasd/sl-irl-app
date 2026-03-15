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

    private let logger = Logger(subsystem: "com.irlalert.app", category: "PiPManager")
    private var pipController: AVPictureInPictureController?
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var playerLayer: AVPlayerLayer?
    private var didPrepare = false
    private var isGeneratingPlaceholder = false
    private var startRetryCount = 0
    private let maxStartRetryCount = 3
    private var refreshTask: Task<Void, Never>?

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

    // MARK: - Public API

    func prepareIfNeeded() {
        guard !didPrepare else { return }
        didPrepare = true

        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            logger.warning("PiP not supported on this device.")
            isSupported = false
            return
        }

        setupPlayerLayerIfNeeded()

        guard let playerLayer else {
            logger.warning("PiP player layer missing. Provide a PiP video source.")
            return
        }

        pipController = AVPictureInPictureController(playerLayer: playerLayer)
        pipController?.delegate = self
    }

    func startIfPossible() {
        prepareIfNeeded()
        guard let pipController else {
            scheduleStartRetry()
            return
        }
        guard pipController.isPictureInPicturePossible else {
            logger.warning("PiP not possible. Ensure a valid video source is active.")
            return
        }
        startRetryCount = 0
        player?.play()
        pipController.startPictureInPicture()
    }

    func stopIfActive() {
        guard let pipController, pipController.isPictureInPictureActive else { return }
        pipController.stopPictureInPicture()
    }

    /// Optionally provide a custom player layer (e.g., for a richer PiP view).
    func setPlayerLayer(_ layer: AVPlayerLayer) {
        playerLayer = layer
        pipController = AVPictureInPictureController(playerLayer: layer)
        pipController?.delegate = self
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

        schedulePlaceholderRefresh()
    }

    // MARK: - Private Helpers

    private func setupPlayerLayerIfNeeded() {
        guard player == nil else { return }

        guard let url = placeholderVideoURL() else { return }

        let item = AVPlayerItem(url: url)
        setPlayerItem(item)
        player = AVPlayer(playerItem: item)
        player?.isMuted = true
        player?.actionAtItemEnd = .none

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        playerLayer = layer
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

        return caches.appendingPathComponent("pip_placeholder.mp4")
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
        }

        return nil
    }

    private func scheduleStartRetry() {
        guard startRetryCount < maxStartRetryCount else { return }
        startRetryCount += 1
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            self.startIfPossible()
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(loopPlayerItem),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
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
        let frameCount = fps * Int32(durationSeconds)

        do {
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
                logger.error("Unable to add input to AVAssetWriter.")
                return
            }
            writer.add(input)

            writer.startWriting()
            writer.startSession(atSourceTime: .zero)

            let snapshot = statusSnapshot

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
        } catch {
            logger.error("Failed to generate PiP placeholder: \(error.localizedDescription)")
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
}

extension PiPManager: @preconcurrency AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = true
        logger.info("PiP starting.")
        Task { await RelayClient.shared.updatePresence(directConnectionActive: true) }
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        logger.info("PiP stopping.")
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = false
        logger.info("PiP stopped.")
        Task { await RelayClient.shared.updatePresence(directConnectionActive: UIApplication.shared.applicationState == .active) }
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        logger.error("PiP failed to start: \(error.localizedDescription)")
    }
}
