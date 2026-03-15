import AVKit
import Combine
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
    private var playerLayer: AVPlayerLayer?
    private var didPrepare = false

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
        guard let pipController else { return }
        guard pipController.isPictureInPicturePossible else {
            logger.warning("PiP not possible. Ensure a valid video source is active.")
            return
        }
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

    // MARK: - Private Helpers

    private func setupPlayerLayerIfNeeded() {
        guard player == nil else { return }

        guard let url = Bundle.main.url(forResource: "pip_placeholder", withExtension: "mp4") else {
            logger.warning("Missing pip_placeholder.mp4 in app bundle.")
            return
        }

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.isMuted = true
        player?.actionAtItemEnd = .none

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(loopPlayerItem),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        playerLayer = layer
    }

    @objc private func loopPlayerItem() {
        player?.seek(to: .zero)
        player?.play()
    }
}

extension PiPManager: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = true
        logger.info("PiP starting.")
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        logger.info("PiP stopping.")
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = false
        logger.info("PiP stopped.")
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        logger.error("PiP failed to start: \(error.localizedDescription)")
    }
}
