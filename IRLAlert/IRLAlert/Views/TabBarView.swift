import SwiftUI

/// Main container housing all primary screens and the custom floating navigation bar.
struct TabBarView: View {
    @EnvironmentObject var router: NavigationRouter
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Main Content Area
            Group {
                switch router.selectedTab {
                case .dashboard:
                    DashboardView()
                case .connections:
                    ConnectionsView()
                case .testing:
                    AlertTestingView()
                case .alerts:
                    EventLogView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Add padding so content isn't hidden under the custom tab bar
            .padding(.bottom, 80)
            
            // Custom Tab Bar Overlay
            CustomNavBar()
                .environmentObject(router)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background(Color.appBackground.ignoresSafeArea())
    }
}

/// The custom iOS-style floating navigation bar matching the stitch design.
struct CustomNavBar: View {
    @EnvironmentObject var router: NavigationRouter
    
    var body: some View {
        HStack(spacing: 0) {
            // Left tabs
            NavBarItem(
                tab: .dashboard,
                icon: "house.fill",
                title: "Home",
                isSelected: router.selectedTab == .dashboard
            ) { router.switchToTab(.dashboard) }
            
            NavBarItem(
                tab: .connections,
                icon: "cable.connector.horizontal",
                title: "Devices",
                isSelected: router.selectedTab == .connections
            ) { router.switchToTab(.connections) }
            
            // Center Floating Action Button (Testing)
            Button {
                router.switchToTab(.testing)
            } label: {
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.primaryBlue)
                        .frame(width: 56, height: 56)
                        .shadow(color: DesignSystem.Colors.primaryBlue.opacity(0.4), radius: 12, x: 0, y: 6)
                        .overlay(
                            Circle()
                                .stroke(Color.appBackground, lineWidth: 4)
                        )
                    
                    Image(systemName: "flask.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .offset(y: -20) // Pop out of the top of the bar
            
            // Right tabs
            NavBarItem(
                tab: .alerts,
                icon: "bell.fill",
                title: "Alerts",
                isSelected: router.selectedTab == .alerts
            ) { router.switchToTab(.alerts) }
            
            NavBarItem(
                tab: .settings,
                icon: "gearshape.fill",
                title: "Settings",
                isSelected: router.selectedTab == .settings
            ) { router.switchToTab(.settings) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        // Add safe area bottom padding manually to ensure it sits right on notch devices
        .padding(.bottom, UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first?.windows.first?.safeAreaInsets.bottom ?? 20)
        .background(
            Material.bar
        )
        .background(
            Color.appBackground.opacity(0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 0)) // Standard bottom bar
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Color.gray.opacity(0.2)),
            alignment: .top
        )
    }
}

// MARK: - Subcomponents

struct NavBarItem: View {
    let tab: NavigationRouter.Tab
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? DesignSystem.Colors.primary : Color.secondary)
                
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isSelected ? DesignSystem.Colors.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        // Remove button highlight effect for a more native feel
        .buttonStyle(.plain)
    }
}

#Preview {
    TabBarView()
        .environmentObject(NavigationRouter())
        .environmentObject(AppSettings())
}
