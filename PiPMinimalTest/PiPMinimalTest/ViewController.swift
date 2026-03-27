import AVFoundation
import AVKit
import UIKit

/// Minimal PiP test — pure UIKit, no SwiftUI.
/// If PiP works here on the same device, the root cause is SwiftUI embedding.
/// If PiP fails here too, the root cause is iOS 26.0.1 itself.
class ViewController: UIViewController {

    private var playerViewController: AVPlayerViewController!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // 1. Configure audio session for playback
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
            print("✅ Audio session: .playback / .moviePlayback / active")
        } catch {
            print("❌ Audio session error: \(error)")
        }

        // 2. Create AVPlayer with a known-good remote MP4
        let url = URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!
        let player = AVPlayer(url: url)
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible

        // 3. Present AVPlayerViewController natively (NOT via SwiftUI)
        playerViewController = AVPlayerViewController()
        playerViewController.player = player
        playerViewController.allowsPictureInPicturePlayback = true
        playerViewController.canStartPictureInPictureAutomaticallyFromInline = true

        addChild(playerViewController)
        view.addSubview(playerViewController.view)
        playerViewController.view.frame = view.bounds
        playerViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerViewController.didMove(toParent: self)

        // 4. Auto-play
        player.play()

        // 5. Log PiP eligibility
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let possible = self.playerViewController.allowsPictureInPicturePlayback
            let timeControl = player.timeControlStatus.rawValue
            let itemStatus = player.currentItem?.status.rawValue ?? -1
            print("🔍 PiP allowed: \(possible)")
            print("🔍 Time control: \(timeControl) (0=paused, 1=waiting, 2=playing)")
            print("🔍 Item status: \(itemStatus) (0=unknown, 1=ready, 2=failed)")
            print("🔍 Now background the app to test PiP!")
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .all
    }
}
