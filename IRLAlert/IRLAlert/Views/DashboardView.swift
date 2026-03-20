import SwiftUI

/// Main dashboard screen.
/// Shows quick status overview, connection health, and active stream metrics.
struct DashboardView: View {
    @StateObject private var viewModel = DashboardVM()
    
    // Animation state for the pulse rings
    @State private var isPulsing = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Welcome back,")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Broadcaster")
                            .font(.title2.bold())
                    }
                    Spacer()
                    
                    // App Icon / Profile
                    ZStack {
                        Circle()
                            .fill(DesignSystem.Colors.primaryBlue.opacity(0.1))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle().stroke(DesignSystem.Colors.primaryBlue.opacity(0.2), lineWidth: 1)
                            )
                        Image(systemName: "person.wave.2.fill")
                            .foregroundStyle(DesignSystem.Colors.primaryBlue)
                            .font(.system(size: 20))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                
                // Hero Status Section
                VStack(spacing: 16) {
                    ZStack {
                        // Outer pulse ring 1
                        Circle()
                            .fill(viewModel.hasActiveConnection ? DesignSystem.Colors.alertGreen.opacity(0.15) : Color.orange.opacity(0.15))
                            .frame(width: 240, height: 240)
                            .scaleEffect(isPulsing ? 1.2 : 0.8)
                            .opacity(isPulsing ? 0 : 0.6)
                        
                        // Outer pulse ring 2
                        Circle()
                            .fill(viewModel.hasActiveConnection ? DesignSystem.Colors.alertGreen.opacity(0.10) : Color.orange.opacity(0.10))
                            .frame(width: 240, height: 240)
                            .scaleEffect(isPulsing ? 1.4 : 0.8)
                            .opacity(isPulsing ? 0 : 0.4)
                        
                        // Main inner circle background
                        Circle()
                            .fill(Color.appCard)
                            .frame(width: 180, height: 180)
                            .shadow(color: Color.black.opacity(0.1), radius: 20, y: 10)
                            .overlay(
                                Circle().stroke(Color.secondary.opacity(0.1), lineWidth: 8)
                            )
                        
                        // Inner content
                        VStack(spacing: 8) {
                            Image(systemName: viewModel.hasActiveConnection ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 48, weight: .light))
                                .foregroundStyle(viewModel.hasActiveConnection ? DesignSystem.Colors.alertGreen : Color.orange)
                            
                            Text(viewModel.hasActiveConnection ? "Active" : "Standby")
                                .font(.title3.bold())
                                .foregroundStyle(viewModel.hasActiveConnection ? DesignSystem.Colors.alertGreen : Color.orange)
                        }
                    }
                    .padding(.vertical, 20)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: false)) {
                            isPulsing = true
                        }
                    }
                    
                    VStack(spacing: 4) {
                        Text(viewModel.hasActiveConnection ? "System Online" : "Waiting for Connection")
                            .font(.headline)
                        Text(viewModel.hasActiveConnection ? "Monitoring \(viewModel.activeServiceCount) connected services" : "No active alert sources")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Service Connectivity Grid
                VStack(alignment: .leading, spacing: 12) {
                    Text("SERVICE CONNECTIVITY")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ServiceStatusCard(
                                title: "Streamlabs",
                                icon: "bolt.fill",
                                color: .teal,
                                state: viewModel.serviceStates[.streamlabs] ?? .disconnected
                            )
                            
                            ServiceStatusCard(
                                title: "Twitch",
                                icon: "message.fill",
                                color: .purple,
                                state: viewModel.serviceStates[.twitchNative] ?? .disconnected
                            )
                            
                            ServiceStatusCard(
                                title: "StreamElements",
                                icon: "cup.and.saucer.fill",
                                color: .blue,
                                state: viewModel.serviceStates[.streamElements] ?? .disconnected
                            )
                        }
                        .padding(.horizontal, 24)
                    }
                }
                
                // Metrics Grid
                HStack(spacing: 16) {
                    MetricCard(
                        title: "QUEUE DEPTH",
                        icon: "list.bullet.rectangle.portrait",
                        iconColor: DesignSystem.Colors.primaryBlue,
                        value: "\(viewModel.queueCount)",
                        unit: "alerts",
                        subtext: viewModel.isProcessing ? "Processing..." : "Idle",
                        subIcon: viewModel.isProcessing ? "waveform.path.ecg" : "moon.zzz",
                        subColor: viewModel.isProcessing ? DesignSystem.Colors.alertGreen : .secondary
                    )
                    
                    MetricCard(
                        title: "PROCESSED",
                        icon: "checkmark.circle.fill",
                        iconColor: DesignSystem.Colors.alertGreen,
                        value: "\(viewModel.processedCount)",
                        unit: "total",
                        subtext: viewModel.skippedCount > 0 ? "\(viewModel.skippedCount) skipped" : "All clear",
                        subIcon: viewModel.skippedCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.seal.fill",
                        subColor: viewModel.skippedCount > 0 ? Color.orange : .secondary
                    )
                }
                .padding(.horizontal, 24)
                
                // Session Card
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Session Details")
                                .font(.headline)
                            Text("Active connection metrics")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    
                    Divider()
                        .padding(.leading)
                    
                    HStack {
                        Text("Uptime")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(viewModel.uptimeString)
                            .fontWeight(.medium)
                            // We use a timer within the card just to kick the view update since uptimeString is computed
                            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in }
                    }
                    .padding()
                }
                .background(Color.appCard)
                .cornerRadius(DesignSystem.Radius.large)
                .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
                .padding(.horizontal, 24)
                
            }
            .padding(.bottom, 100) // Account for floating tab bar
        }
        .background(Color.appBackground)
    }
}

// MARK: - Subcomponents

struct ServiceStatusCard: View {
    let title: String
    let icon: String
    let color: Color
    let state: ConnectionState
    
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(color)
            }
            
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.system(size: 12, weight: .bold))
            }
        }
        .frame(width: 110)
        .padding(.vertical, 16)
        .background(Color.appCard)
        .cornerRadius(DesignSystem.Radius.large)
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.large)
                .stroke(Color.secondary.opacity(0.05), lineWidth: 1)
        )
    }
    
    private var statusColor: Color {
        switch state {
        case .connected: return DesignSystem.Colors.alertGreen
        case .connecting, .reconnecting: return Color.orange
        case .failed: return Color.red
        case .disconnected: return Color.secondary.opacity(0.4)
        }
    }
    
    private var statusText: String {
        switch state {
        case .connected: return "Online"
        case .connecting, .reconnecting: return "Syncing"
        case .failed: return "Error"
        case .disconnected: return "Offline"
        }
    }
}

struct MetricCard: View {
    let title: String
    let icon: String
    let iconColor: Color
    let value: String
    let unit: String
    let subtext: String
    let subIcon: String
    let subColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 32, weight: .bold))
                Text(unit)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 4) {
                Image(systemName: subIcon)
                    .font(.system(size: 10))
                Text(subtext)
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(subColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.appCard)
        .cornerRadius(DesignSystem.Radius.large)
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
    }
}

#Preview {
    DashboardView()
}
