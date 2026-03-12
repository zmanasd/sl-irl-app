import SwiftUI

/// Main tab bar container matching the iOS blur-backdrop nav style from the stitch designs.
/// Houses all primary screens: Dashboard, Alerts, Testing, Settings.
struct TabBarView: View {
    @EnvironmentObject var router: NavigationRouter

    var body: some View {
        TabView(selection: $router.selectedTab) {
            DashboardView()
                .tabItem {
                    Label(
                        NavigationRouter.Tab.dashboard.title,
                        systemImage: NavigationRouter.Tab.dashboard.iconName
                    )
                }
                .tag(NavigationRouter.Tab.dashboard)

            EventLogView()
                .tabItem {
                    Label(
                        NavigationRouter.Tab.alerts.title,
                        systemImage: NavigationRouter.Tab.alerts.iconName
                    )
                }
                .tag(NavigationRouter.Tab.alerts)

            AlertTestingView()
                .tabItem {
                    Label(
                        NavigationRouter.Tab.testing.title,
                        systemImage: NavigationRouter.Tab.testing.iconName
                    )
                }
                .tag(NavigationRouter.Tab.testing)

            SettingsView()
                .tabItem {
                    Label(
                        NavigationRouter.Tab.settings.title,
                        systemImage: NavigationRouter.Tab.settings.iconName
                    )
                }
                .tag(NavigationRouter.Tab.settings)
        }
    }
}

#Preview {
    TabBarView()
        .environmentObject(NavigationRouter())
        .environmentObject(AppSettings())
}
