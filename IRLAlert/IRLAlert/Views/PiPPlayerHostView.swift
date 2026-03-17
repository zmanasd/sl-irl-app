import AVKit
import SwiftUI

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
