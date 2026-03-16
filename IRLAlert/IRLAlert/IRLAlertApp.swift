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
    @StateObject private var pipManager = PiPManager.shared

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
        .overlay(alignment: .topLeading) {
#if DEBUG
            if scenePhase == .active {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PiP Debug Build")
                        .font(.caption.weight(.bold))
                    Text("enabled: \(appSettings.pipEnabled ? "on" : "off")  supported: \(pipManager.isSupported ? "yes" : "no")  possible: \(pipManager.isPossible ? "yes" : "no")")
                        .font(.caption2)
                    Text("flow: \(router.currentFlow == .main ? "main" : "onboarding")  layer: \(pipManager.hasAttachedPlayerLayer ? "yes" : "no")  active: \(pipManager.isActive ? "yes" : "no")")
                        .font(.caption2)
                    Text("ready: \(pipManager.isReadyForDisplay ? "yes" : "no")  item: \(pipManager.itemStatusDescription)  time: \(pipManager.timeControlDescription)")
                        .font(.caption2)
                    if pipManager.lastStartAttemptSource != "none" {
                        Text("attempt: \(pipManager.lastStartAttemptSource)")
                            .font(.caption2)
                    }
                    if pipManager.lastFailureReason != "none" {
                        Text("last: \(pipManager.lastFailureReason)")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Force Start PiP") {
                        pipManager.startIfPossible(source: "debug button", force: true)
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                }
                .padding(10)
                .background(Color.black.opacity(0.78))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.leading, 16)
                .padding(.top, 14)
            }
#endif
        }
        .overlay(alignment: .bottomTrailing) {
            if shouldKeepPiPHostAttached {
                ZStack(alignment: .bottomLeading) {
                    PiPPlayerHostView()
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.08, green: 0.12, blue: 0.18),
                                    Color(red: 0.15, green: 0.21, blue: 0.29)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("PiP Preview")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        Text(appSettings.pipEnabled ? "Background the app to test" : "Enable PiP in settings")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(10)
                }
                .frame(width: 176, height: 99)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
                .padding(.trailing, 16)
                .padding(.bottom, 96)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .onAppear {
            if appSettings.hasCompletedOnboarding {
                router.currentFlow = .main
            }
            if appSettings.pipEnabled {
                startAudioEngine()
                PiPManager.shared.ensurePreviewPlayback()
            }
            Task { await PushNotificationManager.shared.handleUserToggle(enabled: appSettings.pushNotificationsEnabled) }
        }
        .onChange(of: router.currentFlow) { _, newFlow in
            if newFlow == .main {
                startAudioEngine()
            }
        }
        .onChange(of: appSettings.pipEnabled) { _, enabled in
            if enabled {
                startAudioEngine()
                PiPManager.shared.ensurePreviewPlayback()
            } else {
                PiPManager.shared.stopIfActive()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
    }

    private var shouldShowPiPPreview: Bool {
#if DEBUG
        scenePhase == .active
#else
        appSettings.pipEnabled && scenePhase == .active
#endif
    }

    private var shouldKeepPiPHostAttached: Bool {
#if DEBUG
        scenePhase == .active || appSettings.pipEnabled || pipManager.isActive
#else
        appSettings.pipEnabled || pipManager.isActive
#endif
    }
    
    /// Configure and start the background audio engine when entering the main flow.
    private func startAudioEngine() {
        AudioSessionManager.shared.configureSession()
        SilentAudioPlayer.shared.start()
        PiPManager.shared.prepareIfNeeded()
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .inactive:
            if appSettings.pipEnabled {
                PiPManager.shared.startIfPossible()
            }
        case .background:
            if appSettings.pipEnabled {
                Task { await RelayClient.shared.updatePresence(directConnectionActive: true) }
            } else {
                Task { await RelayClient.shared.updatePresence(directConnectionActive: false) }
            }
        case .active:
            if appSettings.pipEnabled {
                PiPManager.shared.ensurePreviewPlayback()
            }
            PiPManager.shared.stopIfActive()
            Task { await RelayClient.shared.updatePresence(directConnectionActive: true) }
        default:
            break
        }
    }
}
