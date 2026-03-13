import SwiftUI

/// Main dashboard screen.
/// Shows quick status overview of connections and recent activity.
struct DashboardView: View {
    @ObservedObject var connectionManager = ConnectionManager.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                HStack {
                    Text("Dashboard")
                        .font(.title)
                    Spacer()
                    QueueStatusView()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                
                // Connection Health Overview
                VStack(alignment: .leading, spacing: 16) {
                    Text("Service Health")
                        .font(.title2)
                        .padding(.horizontal, 24)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            // Only showing Streamlabs for Phase 3 MVP
                            HealthBadge(
                                title: "Streamlabs",
                                state: connectionManager.state(for: .streamlabs)
                            )
                            
                            HealthBadge(title: "Twitch", state: .disconnected, disabled: true)
                        }
                        .padding(.horizontal, 24)
                    }
                }
                
                Spacer()
                    .frame(height: 40)
                
                // Placeholder for recent events (Phase 4)
                VStack(spacing: 16) {
                    Image(systemName: "tray.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                    Text("No Recent Alerts")
                        .font(.body.bold())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
                .background(Color.appCard)
                .cornerRadius(DesignSystem.Radius.large)
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 100) // Account for floating tab bar
        }
        .background(Color.appBackground)
    }
}

struct HealthBadge: View {
    let title: String
    let state: ConnectionState
    var disabled: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.4), radius: 4)
            
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(disabled ? .secondary : .primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.appCard)
        .cornerRadius(DesignSystem.Radius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .opacity(disabled ? 0.6 : 1.0)
    }
    
    private var statusColor: Color {
        if disabled { return Color.secondary.opacity(0.3) }
        switch state {
        case .connected: return DesignSystem.Colors.alertGreen
        case .connecting, .reconnecting: return Color.orange
        case .failed: return Color.red
        case .disconnected: return Color.secondary.opacity(0.3)
        }
    }
}

#Preview {
    DashboardView()
}
