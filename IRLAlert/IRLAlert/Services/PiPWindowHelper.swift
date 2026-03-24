import AVFoundation
import AVKit
import UIKit
import os.log

/// Attaches an AVPlayerLayer directly to the UIKit window's root view layer,
/// bypassing SwiftUI's hosting hierarchy entirely.
///
/// This solves the PiP eligibility issue: AVKit requires the player layer to be
/// in a UIKit view hierarchy with a valid UIWindowScene. SwiftUI's
/// UIViewControllerRepresentable breaks this scene discovery.
@MainActor
final class PiPWindowHelper {

    static let shared = PiPWindowHelper()

    private let logger = Logger(subsystem: "com.irlalert.app", category: "PiPWindowHelper")
    private var playerLayer: AVPlayerLayer?
    private weak var hostWindow: UIWindow?

    /// Call from SceneDelegate once the UIWindow is available.
    func attach(to window: UIWindow, player: AVPlayer) {
        guard hostWindow == nil else {
            logger.info("PiP layer already attached to window.")
            return
        }
        hostWindow = window

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        // 1×1 invisible layer — satisfies AVKit's hierarchy requirement
        // without showing any visible playback surface.
        layer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        layer.opacity = 0

        window.rootViewController?.view.layer.addSublayer(layer)
        playerLayer = layer

        logger.info("AVPlayerLayer attached to UIWindow root view layer.")
    }

    /// Returns the UIKit-hosted player layer for PiP controller binding.
    var attachedLayer: AVPlayerLayer? {
        playerLayer
    }

    /// Whether the layer is properly hosted in the window hierarchy.
    var isAttached: Bool {
        guard let layer = playerLayer else { return false }
        return layer.superlayer != nil && hostWindow != nil
    }
}
