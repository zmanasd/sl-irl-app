import Foundation
import SwiftUI

/// Manages the top-level navigation flow of the app.
/// Controls whether the user sees onboarding or the main tab bar.
@MainActor
final class NavigationRouter: ObservableObject {

    /// The two top-level flows in the app.
    enum AppFlow: Equatable {
        case onboarding
        case main
    }

    /// The currently selected tab in the main tab bar.
    enum Tab: Int, CaseIterable, Identifiable {
        case dashboard = 0
        case alerts = 1
        case testing = 2
        case settings = 3

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .dashboard: return "Home"
            case .alerts:    return "Alerts"
            case .testing:   return "Testing"
            case .settings:  return "Settings"
            }
        }

        var iconName: String {
            switch self {
            case .dashboard: return "house.fill"
            case .alerts:    return "bolt.fill"
            case .testing:   return "flask.fill"
            case .settings:  return "gearshape.fill"
            }
        }
    }

    // MARK: - Published State

    /// Current top-level flow (onboarding vs main)
    @Published var currentFlow: AppFlow = .onboarding

    /// Currently selected tab in the main tab bar
    @Published var selectedTab: Tab = .dashboard

    // MARK: - Navigation Actions

    /// Called when onboarding is completed or skipped.
    func completeOnboarding(settings: AppSettings) {
        settings.hasCompletedOnboarding = true
        withAnimation(.easeInOut(duration: 0.4)) {
            currentFlow = .main
        }
    }

    /// Switch to a specific tab programmatically.
    func switchToTab(_ tab: Tab) {
        selectedTab = tab
    }
}
