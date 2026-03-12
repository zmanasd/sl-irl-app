import SwiftUI

/// Placeholder for the onboarding flow.
/// Will be fully styled in Phase 1 Frontend.
struct OnboardingView: View {
    @EnvironmentObject var router: NavigationRouter
    @EnvironmentObject var appSettings: AppSettings

    @State private var currentPage = 0
    private let totalPages = 4

    var body: some View {
        VStack(spacing: 0) {
            // Skip button
            HStack {
                Spacer()
                Button("Skip") {
                    router.completeOnboarding(settings: appSettings)
                }
                .font(.body.weight(.medium))
                .padding()
            }

            Spacer()

            // Page content placeholder
            VStack(spacing: 20) {
                Image(systemName: pageIcon)
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)

                Text(pageTitle)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(pageSubtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            // Progress dots & Continue button
            VStack(spacing: 24) {
                Button(action: advancePage) {
                    Text(currentPage == totalPages - 1 ? "Get Started" : "Continue")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)

                // Progress dots
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 10, height: 10)
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Page Content

    private var pageIcon: String {
        switch currentPage {
        case 0: return "shield.fill"
        case 1: return "bell.badge.fill"
        case 2: return "speaker.wave.3.fill"
        case 3: return "wifi"
        default: return "questionmark"
        }
    }

    private var pageTitle: String {
        switch currentPage {
        case 0: return "Welcome to IRL Alert"
        case 1: return "Allow Notifications"
        case 2: return "Background Audio"
        case 3: return "Stay Connected"
        default: return ""
        }
    }

    private var pageSubtitle: String {
        switch currentPage {
        case 0: return "Never miss a stream alert while you're live on the go."
        case 1: return "Get notified if your alert connection drops so you can react fast."
        case 2: return "IRL Alert plays sounds in the background, mixed over your streaming app."
        case 3: return "Connect your Streamlabs, StreamElements, or Twitch alerts to get started."
        default: return ""
        }
    }

    // MARK: - Actions

    private func advancePage() {
        if currentPage < totalPages - 1 {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentPage += 1
            }
        } else {
            router.completeOnboarding(settings: appSettings)
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(NavigationRouter())
        .environmentObject(AppSettings())
}
