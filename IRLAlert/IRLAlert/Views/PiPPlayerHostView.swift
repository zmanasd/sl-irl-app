import AVKit
import SwiftUI

/// Hosts a direct AVPlayerLayer in the SwiftUI hierarchy for baseline PiP eligibility tests.
struct PiPPlayerLayerHostView: UIViewRepresentable {
    func makeUIView(context: Context) -> PlayerLayerHostView {
        let view = PlayerLayerHostView()
        PiPManager.shared.setPlayerLayer(view.playerLayer)
        return view
    }

    func updateUIView(_ uiView: PlayerLayerHostView, context: Context) {
        PiPManager.shared.setPlayerLayer(uiView.playerLayer)
    }

    final class PlayerLayerHostView: UIView {
        override class var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            PiPManager.shared.setPlayerLayer(playerLayer)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            PiPManager.shared.setPlayerLayer(playerLayer)
        }
    }
}

/// Hosts an AVPlayerViewController in the view hierarchy so PiP runs through AVKit-native playback.
struct PiPPlayerHostView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> PlayerHostViewController {
        let controller = PlayerHostViewController()
        PiPManager.shared.setPlayerViewController(controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: PlayerHostViewController, context: Context) {
        PiPManager.shared.setPlayerViewController(uiViewController)
    }

    final class PlayerHostViewController: AVPlayerViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            configureForHostUsage()
            PiPManager.shared.setPlayerViewController(self)
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            PiPManager.shared.setPlayerViewController(self)
        }

        private func configureForHostUsage() {
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }
    }
}
