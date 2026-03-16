import AVKit
import SwiftUI

/// Hosts an AVPlayerLayer in the view hierarchy so PiP can start.
struct PiPPlayerHostView: UIViewRepresentable {
    func makeUIView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        PiPManager.shared.setPlayerLayer(view.playerLayer)
        return view
    }

    func updateUIView(_ uiView: PlayerHostView, context: Context) {
        PiPManager.shared.setPlayerLayer(uiView.playerLayer)
    }

    final class PlayerHostView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
