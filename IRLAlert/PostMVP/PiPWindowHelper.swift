import AVFoundation
import AVKit
import UIKit
import os.log

/// Creates a dedicated off-screen UIWindow that hosts an AVPlayerViewController
/// as a proper child view controller, enabling AVKit's built-in PiP support.
///
/// AVPlayerViewController handles Picture-in-Picture internally when:
///   - `allowsPictureInPicturePlayback = true`
///   - `canStartPictureInPictureAutomaticallyFromInline = true`
///   - The VC is in a live UIWindowScene (not a SwiftUI hosting hierarchy)
///
/// The window is placed off-screen (at -200,-200) with near-zero alpha so it
/// is "visible" to AVKit but invisible to the user.
@MainActor
final class PiPWindowHelper: NSObject {

    static let shared = PiPWindowHelper()
    private override init() { super.init() }

    private let logger = Logger(subsystem: "com.irlalert.app", category: "PiPWindowHelper")

    private var pipWindow: UIWindow?
    private(set) var playerViewController: AVPlayerViewController?

    // MARK: - Public

    var isAttached: Bool { pipWindow != nil && playerViewController != nil }

    /// Set up the off-screen UIWindow + AVPlayerViewController.
    /// `player` must already have an item ready to play.
    func attach(player: AVPlayer, to scene: UIWindowScene) {
        guard pipWindow == nil else {
            logger.info("PiP window already attached.")
            return
        }

        // Root VC container for the player VC
        let rootVC = UIViewController()
        rootVC.view.backgroundColor = .clear

        // AVPlayerViewController with PiP enabled
        let pvc = AVPlayerViewController()
        pvc.player = player
        pvc.allowsPictureInPicturePlayback = true
        pvc.canStartPictureInPictureAutomaticallyFromInline = true
        pvc.updatesNowPlayingInfoCenter = false

        rootVC.addChild(pvc)
        pvc.view.frame = CGRect(x: 0, y: 0, width: 100, height: 56) // 16:9 non-zero frame
        pvc.view.backgroundColor = .black
        rootVC.view.addSubview(pvc.view)
        pvc.didMove(toParent: rootVC)
        playerViewController = pvc

        // Off-screen window — must NOT be hidden for AVKit to detect it
        let window = UIWindow(windowScene: scene)
        window.rootViewController = rootVC
        window.frame = CGRect(x: -200, y: -200, width: 100, height: 56)
        window.windowLevel = .normal - 1
        window.isHidden = false
        window.alpha = 0.01 // nearly invisible but technically "visible"
        window.makeKeyAndVisible()
        pipWindow = window

        logger.info("PiP off-screen window ready. Player: \(player.currentItem != nil ? "has item" : "no item")")
    }

    func detach() {
        playerViewController?.player = nil
        playerViewController?.willMove(toParent: nil)
        playerViewController?.view.removeFromSuperview()
        playerViewController?.removeFromParent()
        playerViewController = nil
        pipWindow?.isHidden = true
        pipWindow = nil
        logger.info("PiP window detached.")
    }
}

// MARK: - AVPlayerViewControllerDelegate

extension PiPWindowHelper: AVPlayerViewControllerDelegate {
    nonisolated func playerViewControllerDidStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        Task { @MainActor in PiPWindowHelper.shared.logger.info("PiP started via AVPlayerViewController.") }
    }

    nonisolated func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        Task { @MainActor in PiPWindowHelper.shared.logger.info("PiP stopped via AVPlayerViewController.") }
    }
}
