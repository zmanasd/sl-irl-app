import SwiftUI

/// Main entry point for the IRL Alert App.
/// Routes between onboarding and the main tab bar based on first-launch state.
@main
struct IRLAlertApp: App {
    @StateObject private var router = NavigationRouter()
    @StateObject private var appSettings = AppSettings()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .environmentObject(appSettings)
        }
    }
}

/// Root view that switches between onboarding and the main tab bar.
struct RootView: View {
    @EnvironmentObject var router: NavigationRouter
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch router.currentFlow {
            case .onboarding:
                OnboardingView()
            case .main:
                TabBarView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: router.currentFlow)
        .onAppear {
            if appSettings.hasCompletedOnboarding {
                router.currentFlow = .main
            }
        }
        .onChange(of: router.currentFlow) { _, newFlow in
            if newFlow == .main {
                startAudioEngine()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
    }
    
    /// Configure and start the background audio engine when entering the main flow.
    private func startAudioEngine() {
        AudioSessionManager.shared.configureSession()
        PiPManager.shared.prepareIfNeeded()
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        guard appSettings.pipEnabled else { return }
        switch newPhase {
        case .background:
            PiPManager.shared.startIfPossible()
        case .active:
            PiPManager.shared.stopIfActive()
        default:
            break
        }
    }
}
