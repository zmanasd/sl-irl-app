import SwiftUI

/// View for managing alert service connections.
/// Allows the user to connect to Streamlabs via Browser Source URL.
struct ConnectionsView: View {
    @ObservedObject var connectionManager = ConnectionManager.shared
    @State private var streamlabsInput: String = ""
    @State private var isConnecting = false
    @State private var showError = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "link.icloud.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(DesignSystem.Colors.primary)
                    
                    Text("Alert Connections")
                        .font(.title)
                    
                    Text("Connect your streaming services to receive background alerts.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.top, 24)
                
                // Active Connections Summary
                if connectionManager.hasActiveConnection {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DesignSystem.Colors.alertGreen)
                        Text("\(connectionManager.activeServiceCount) Service(s) Connected")
                            .font(.subheadline.bold())
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(DesignSystem.Colors.alertGreen.opacity(0.15))
                    .cornerRadius(DesignSystem.Radius.medium)
                    .padding(.horizontal)
                }
                
                // Streamlabs Card
                ServiceConnectionCard(
                    title: "Streamlabs",
                    icon: "cloud.fill",
                    tintColor: Color(hex: "#31C3A2"),
                    state: connectionManager.state(for: .streamlabs),
                    input: $streamlabsInput,
                    isLoading: isConnecting
                ) {
                    if connectionManager.state(for: .streamlabs) == .connected {
                        connectionManager.disconnect(.streamlabs)
                    } else {
                        connectStreamlabs()
                    }
                }
                
                // Future Services Placeholders
                VStack(spacing: 16) {
                    HStack {
                        Text("Coming Soon")
                            .font(.body.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    
                    PlaceholderServiceCard(title: "Twitch Events", icon: "message.fill")
                    PlaceholderServiceCard(title: "StreamElements", icon: "drop.fill")
                    PlaceholderServiceCard(title: "SoundAlerts", icon: "speaker.wave.3.fill")
                }
                .disabled(true)
                .opacity(0.6)
                
            }
            .padding(.bottom, 40)
        }
        .background(Color.appBackground)
        .alert("Connection Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(connectionManager.lastError ?? "An unknown error occurred.")
        }
    }
    
    private func connectStreamlabs() {
        guard !streamlabsInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isConnecting = true
        
        let input = streamlabsInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let credentials: ServiceCredentials
        
        if input.lowercased().hasPrefix("http") {
            if let url = URL(string: input) {
                credentials = .browserSourceURL(url)
            } else {
                connectionManager.setLastError("Invalid URL format.")
                showError = true
                isConnecting = false
                return
            }
        } else {
            // Assume it's a raw socket token
            credentials = .socketToken(input)
        }
        
        Task {
            await connectionManager.connect(.streamlabs, with: credentials)
            isConnecting = false
            
            if connectionManager.lastError != nil {
                showError = true
            } else {
                streamlabsInput = "" // Clear on success
            }
        }
    }
}

// MARK: - Components

struct ServiceConnectionCard: View {
    let title: String
    let icon: String
    let tintColor: Color
    let state: ConnectionState
    @Binding var input: String
    let isLoading: Bool
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                // Header
                ZStack {
                    Circle()
                        .fill(tintColor.opacity(0.2))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .foregroundStyle(tintColor)
                        .font(.system(size: 20, weight: .bold))
                }
                
                Text(title)
                    .font(.body.bold())
                
                Spacer()
                
                // Status Badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    
                    Text(state.displayName)
                        .font(.caption.bold())
                        .foregroundStyle(statusColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.15))
                .clipShape(Capsule())
            }
            
            // Input Area (if disconnected)
            if state == .disconnected || state == .failed {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Enter your Socket Token or Browser Source URL:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextField("https://streamlabs.com/...", text: $input)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(DesignSystem.Radius.small)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            
            // Action Button
            Button(action: action) {
                HStack {
                    if isLoading || state == .connecting || state == .reconnecting {
                        ProgressView()
                            .tint(state == .connected ? .red : .white)
                            .padding(.trailing, 8)
                    }
                    Text(state == .connected ? "Disconnect" : "Connect")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(state == .connected ? Color.red.opacity(0.15) : tintColor)
                .foregroundStyle(state == .connected ? Color.red : .white)
                .cornerRadius(DesignSystem.Radius.medium)
            }
            .disabled(isLoading && state != .connected)
        }
        .padding(20)
        .background(Color.appCard)
        .cornerRadius(DesignSystem.Radius.large)
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
        .padding(.horizontal)
    }
    
    private var statusColor: Color {
        switch state {
        case .connected: return DesignSystem.Colors.alertGreen
        case .connecting, .reconnecting: return Color.orange
        case .failed: return Color.red
        case .disconnected: return Color.secondary
        }
    }
}

private struct PlaceholderServiceCard: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 32)
                .foregroundStyle(.secondary)
            
            Text(title)
                .font(.body.bold())
            
            Spacer()
            
            Text("Disabled")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.15))
                .clipShape(Capsule())
        }
        .padding(20)
        .background(Color.appCard)
        .cornerRadius(DesignSystem.Radius.large)
        .padding(.horizontal)
    }
}

#Preview {
    ConnectionsView()
}
