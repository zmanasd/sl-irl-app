import SwiftUI

/// High-fidelity onboarding flow matching the stitch design language.
struct OnboardingView: View {
    @EnvironmentObject var router: NavigationRouter
    @EnvironmentObject var appSettings: AppSettings

    @State private var currentPage = 0
    private let totalPages = 4

    var body: some View {
        VStack(spacing: 0) {
            // Top Status/Header Area
            HStack {
                // Invisible spacer to balance the skip button
                Spacer().frame(width: 60)
                
                Spacer()
                
                // Center Branding
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                            .fill(DesignSystem.Colors.primary)
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "bolt.shield.fill") // Stream alert + shield vibe
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Text("IRL Alert")
                        .font(.system(size: 17, weight: .semibold, design: .default))
                        .foregroundStyle(Color.primary)
                }
                
                Spacer()
                
                // Skip Button
                Button("Skip") {
                    router.completeOnboarding(settings: appSettings)
                }
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.primary)
                .frame(width: 60, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)

            // Main Content Area
            GeometryReader { geometry in
                TabView(selection: $currentPage) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        OnboardingPageView(pageIndex: index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            // Footer / Actions
            VStack(spacing: 24) {
                Button(action: advancePage) {
                    Text(currentPage == totalPages - 1 ? "Get Started" : "Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(DesignSystem.Colors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
                        .shadow(color: DesignSystem.Colors.primary.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                
                // Progress Dots
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? DesignSystem.Colors.primary : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .animation(.spring(), value: currentPage)
                    }
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 16)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .onChange(of: appSettings.pushNotificationsEnabled) { _, isEnabled in
            Task { await PushNotificationManager.shared.handleUserToggle(enabled: isEnabled) }
        }
    }

    private func advancePage() {
        if currentPage < totalPages - 1 {
            withAnimation(.spring()) {
                currentPage += 1
            }
        } else {
            router.completeOnboarding(settings: appSettings)
        }
    }
}

// MARK: - Page View Component

struct OnboardingPageView: View {
    let pageIndex: Int
    @EnvironmentObject var appSettings: AppSettings
    
    // Animation state for pulse rings
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Hero Visual (Concentric pulsing rings from stitch design)
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.primary.opacity(0.1))
                    .frame(width: 240, height: 240)
                    .scaleEffect(isAnimating ? 1.1 : 0.9)
                    .opacity(isAnimating ? 0.5 : 1.0)
                
                Circle()
                    .fill(DesignSystem.Colors.primary.opacity(0.15))
                    .frame(width: 180, height: 180)
                
                Circle()
                    .fill(Color.appCard)
                    .frame(width: 130, height: 130)
                    .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
                    .overlay(
                        Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                
                Image(systemName: pageIcon)
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(iconColor)
                    
                // Floating Badge
                if pageIndex == 0 {
                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.white)
                                Text("LIVE")
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(DesignSystem.Colors.alertRed)
                            .clipShape(Capsule())
                            .shadow(radius: 4)
                            .offset(x: -30, y: -20)
                        }
                        Spacer()
                    }
                    .frame(width: 240, height: 240)
                }
            }
            .padding(.bottom, 40)
            .task {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
            
            // Text Content
            VStack(spacing: 12) {
                Text(pageTitle)
                    .font(.system(size: 28, weight: .heavy, design: .default))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.primary)
                
                Text(pageSubtitle)
                    .font(.system(size: 17))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 20)
            }
            
            // Highlighted Detail Cards (from stitch design)
            if !detailCards.isEmpty {
                VStack(spacing: 12) {
                    ForEach(detailCards, id: \.title) { card in
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(DesignSystem.Colors.primary.opacity(0.1))
                                    .frame(width: 44, height: 44)
                                Image(systemName: card.icon)
                                    .font(.system(size: 20))
                                    .foregroundStyle(DesignSystem.Colors.primary)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.primary)
                                Text(card.subtitle)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .background(Color.appCard)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.large))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.Radius.large)
                                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 2)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
            }

            if pageIndex == 3 {
                VStack(spacing: 12) {
                    Toggle(isOn: $appSettings.pushNotificationsEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable Push Alerts")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Receive alerts when the app is backgrounded.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.primary))
                    .padding(16)
                    .background(Color.appCard)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )

                    Toggle(isOn: $appSettings.pipEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable Picture-in-Picture")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Keeps alerts live while multitasking.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.primary))
                    .padding(16)
                    .background(Color.appCard)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Content Configuration
    
    private var pageIcon: String {
        switch pageIndex {
        case 0: return "video.badge.waveform" // Streaming
        case 1: return "bell.badge.fill" // Notifications
        case 2: return "speaker.wave.3.fill" // Background audio
        case 3: return "link.icloud.fill" // Connections
        default: return "star.fill"
        }
    }
    
    private var iconColor: Color {
        switch pageIndex {
        case 0: return DesignSystem.Colors.primary
        case 1: return DesignSystem.Colors.alertOrange
        case 2: return DesignSystem.Colors.alertGreen
        case 3: return DesignSystem.Colors.alertPurple
        default: return DesignSystem.Colors.primary
        }
    }
    
    private var pageTitle: String {
        switch pageIndex {
        case 0: return "IRL Stream Alerts"
        case 1: return "Stay Informed"
        case 2: return "Always Listening"
        case 3: return "Plug & Play"
        default: return ""
        }
    }
    
    private var pageSubtitle: String {
        switch pageIndex {
        case 0: return "Never miss a donation, sub, or raid while you're live out in the real world."
        case 1: return "Important alerts trigger local notifications so you never miss a beat."
        case 2: return "IRL Alert runs in the background, mixing alerts over your streaming app directly into your earpiece."
        case 3: return "Connect via Streamlabs URLs or direct OAuth to Twitch and StreamElements."
        default: return ""
        }
    }
    
    private struct DetailCard {
        let icon: String
        let title: String
        let subtitle: String
    }
    
    private var detailCards: [DetailCard] {
        switch pageIndex {
        case 1:
            return [
                DetailCard(icon: "bell.and.waves.left.and.right", title: "Allow Notifications", subtitle: "Crucial for disconnect warnings and background alert text."),
                DetailCard(icon: "exclamationmark.triangle.fill", title: "Critical Alerts", subtitle: "Get warned immediately if your connection drops.")
            ]
        case 2:
            return [
                DetailCard(icon: "music.note", title: "Audio Permissions", subtitle: "Required to establish the continuous background audio session."),
            ]
        default:
            return []
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(NavigationRouter())
        .environmentObject(AppSettings())
}
