import AVFoundation
import AVKit
import UIKit
import os.log

/// Creates a dedicated off-screen UIWindow that hosts an AVPlayerViewController
/// as a proper child view controller, enabling AVKit's PiP scene discovery.
///
/// A 1×1 hidden AVPlayerLayer sublayer is insufficient — AVKit requires the
/// player to be presented via a full view controller hierarchy in a real
/// UIWindowScene. This matches the exact structure used in the minimal UIKit
/// test app that confirmed PiP works.
@MainActor
final class PiPWindowHelper {

    static let shared = PiPWindowHelper()
    private init() {}

    private let logger = Logger(subsystem: "com.irlalert.app", category: "PiPWindowHelper")

    private var pipWindow: UIWindow?
    private var playerViewController: AVPlayerViewController?

    // MARK: - Public

    /// The player view controller whose playerLayer backs the PiP controller.
    var hostedPlayerViewController: AVPlayerViewController? { playerViewController }

    /// Whether the window and VC are properly set up.
    var isAttached: Bool { pipWindow != nil && playerViewController != nil }

    /// Create the off-screen PiP window and host the player VC inside it.
    /// Must be called after a UIWindowScene is available.
    func attach(player: AVPlayer, to scene: UIWindowScene) {
        guard pipWindow == nil else {
            logger.info("PiP window already attached.")
            return
        }

        // Build AVPlayerViewController — the exact same way the working test app does it
        let pvc = AVPlayerViewController()
        pvc.player = player
        pvc.allowsPictureInPicturePlayback = true
        pvc.canStartPictureInPictureAutomaticallyFromInline = true
        playerViewController = pvc

        // Minimal root VC to hold the player VC as a child
        let rootVC = UIViewController()
        rootVC.addChild(pvc)
        pvc.view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)  // non-zero size required
        rootVC.view.addSubview(pvc.view)
        pvc.didMove(toParent: rootVC)

        // Create a separate UIWindow in the same scene, placed off-screen
        let window = UIWindow(windowScene: scene)
        window.rootViewController = rootVC
        window.frame = CGRect(x: -200, y: -200, width: 100, height: 100)  // off-screen
        window.windowLevel = .normal - 1  // below all other content
        window.isHidden = false  // must be visible (not hidden) for AVKit eligibility
        window.alpha = 0.01      // nearly invisible but not hidden
        window.makeKeyAndVisible()
        pipWindow = window

        logger.info("PiP window attached — AVPlayerViewController hosted in off-screen UIWindowScene window.")
    }

    func detach() {
        playerViewController?.willMove(toParent: nil)
        playerViewController?.view.removeFromSuperview()
        playerViewController?.removeFromParent()
        playerViewController = nil
        pipWindow?.isHidden = true
        pipWindow = nil
        logger.info("PiP window detached.")
    }
}
