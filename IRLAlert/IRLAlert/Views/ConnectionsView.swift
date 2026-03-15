import SwiftUI

/// Main view for managing active service connections.
/// Allows the user to configure and monitor their alert sources.
struct ConnectionsView: View {
    @StateObject private var viewModel = ConnectionsVM()
    @State private var showingStreamlabsInput = false
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    HStack {
                        Text("Devices & Connections")
                            .font(.largeTitle.weight(.bold))
                            .tracking(-0.5)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    
                    // Connection Status Banner
                    StatusBanner(
                        hasActive: viewModel.hasActiveConnection,
                        activeCount: viewModel.activeServiceCount
                    )
                    .padding(.horizontal, 24)
                    
                    // Error Banner
                    if let error = viewModel.lastError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                                .font(.caption.bold())
                            Spacer()
                            Button {
                                viewModel.clearError()
                            } label: {
                                Image(systemName: "xmark")
                            }
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .foregroundStyle(.red)
                        .cornerRadius(12)
                        .padding(.horizontal, 24)
                    }
                    
                    // Sync Services Grid
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("SYNC SERVICES")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .tracking(1.0)
                            
                            Spacer()
                            
                            Text("\(viewModel.activeServiceCount) Active")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DesignSystem.Colors.primaryBlue)
                        }
                        .padding(.horizontal, 24)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ServiceGridCard(
                                title: "Streamlabs",
                                subtitle: "Socket or URL",
                                icon: "bolt.fill",
                                color: .teal,
                                state: viewModel.serviceStates[.streamlabs] ?? .disconnected
                            ) {
                                if viewModel.serviceStates[.streamlabs] == .connected || viewModel.serviceStates[.streamlabs] == .connecting {
                                    viewModel.disconnect(.streamlabs)
                                } else {
                                    showingStreamlabsInput = true
                                }
                            }
                            
                            // Twitch Card (Placeholder for Phase 5)
                            ServiceGridCard(
                                title: "Twitch",
                                subtitle: "OAuth Linked",
                                icon: "message.fill",
                                color: .purple,
                                state: viewModel.serviceStates[.twitchNative] ?? .disconnected
                            ) { }
                            
                            // StreamElements Card (Placeholder for Phase 5)
                            ServiceGridCard(
                                title: "HyperChat",
                                subtitle: "WebSocket",
                                icon: "cup.and.saucer.fill",
                                color: .blue,
                                state: viewModel.serviceStates[.streamElements] ?? .disconnected
                            ) { }
                            
                            // SoundAlerts Card (Placeholder for Phase 5)
                            ServiceGridCard(
                                title: "SoundAlerts",
                                subtitle: "Browser Source",
                                icon: "speaker.wave.3.fill",
                                color: .orange,
                                state: viewModel.serviceStates[.soundAlerts] ?? .disconnected
                            ) { }
                        }
                        .padding(.horizontal, 24)
                    }
                    
                    // Quick Connect Helpers
                    VStack(alignment: .leading, spacing: 16) {
                        Text("QUICK CONNECT")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .tracking(1.0)
                            .padding(.horizontal, 24)
                        
                        VStack(spacing: 12) {
                            Button {} label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "qrcode.viewfinder")
                                        .font(.title3)
                                    Text("Scan Browser URL QR Code")
                                        .font(.body.weight(.semibold))
                                    Spacer()
                                }
                                .padding()
                                .frame(height: 56)
                                .background(Color.appCard)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                                )
                            }
                            .foregroundStyle(.primary)
                            
                            Button {} label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "macbook.and.iphone")
                                        .font(.title3)
                                    Text("Find Devices on Setup Network")
                                        .font(.body.weight(.semibold))
                                    Spacer()
                                }
                                .padding()
                                .frame(height: 56)
                                .background(Color.appCard)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                                )
                            }
                            .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 120) // Tab bar clearance
            }
        }
        // Streamlabs Input Sheet
        .sheet(isPresented: $showingStreamlabsInput) {
            StreamlabsInputSheet(
                token: $viewModel.streamlabsInput,
                isConnecting: viewModel.isConnecting[.streamlabs] ?? false,
                cancel: { showingStreamlabsInput = false },
                connect: {
                    Task {
                        await viewModel.connectStreamlabs()
                        showingStreamlabsInput = false
                    }
                }
            )
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Subcomponents

struct StatusBanner: View {
    let hasActive: Bool
    let activeCount: Int
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ZStack {
                        if hasActive {
                            Circle()
                                .fill(DesignSystem.Colors.alertGreen.opacity(0.4))
                                .frame(width: 8, height: 8)
                                .scaleEffect(1.5)
                                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: false), value: hasActive)
                        }
                        Circle()
                            .fill(hasActive ? DesignSystem.Colors.alertGreen : Color.secondary)
                            .frame(width: 8, height: 8)
                    }
                    Text(hasActive ? "BACKGROUND SYNC ACTIVE" : "SYNC INACTIVE")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(hasActive ? DesignSystem.Colors.alertGreen : .secondary)
                        .tracking(1.0)
                }
                Text("App is monitoring event streams via background socket connection for instant auditory alerts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(16)
        .background(hasActive ? DesignSystem.Colors.alertGreen.opacity(0.05) : Color.secondary.opacity(0.05))
        .cornerRadius(DesignSystem.Radius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .stroke(hasActive ? DesignSystem.Colors.alertGreen.opacity(0.15) : Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}

struct ServiceGridCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let state: ConnectionState
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.1))
                            .frame(width: 40, height: 40)
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(color)
                    }
                    Spacer()
                    if state == .connected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DesignSystem.Colors.alertGreen)
                    } else if state == .connecting || state == .reconnecting {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(state == .connected ? "Online" : (state == .connecting ? "Connecting..." : subtitle))
                        .font(.caption)
                        .foregroundStyle(state == .connected ? DesignSystem.Colors.alertGreen : .secondary)
                }
            }
            .padding(16)
            .background(Color.appCard)
            .cornerRadius(DesignSystem.Radius.medium)
            .shadow(color: state == .connected ? color.opacity(0.1) : Color.black.opacity(0.03), radius: 8, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                    .stroke(state == .connected ? color.opacity(0.3) : Color.secondary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct StreamlabsInputSheet: View {
    @Binding var token: String
    let isConnecting: Bool
    let cancel: () -> Void
    let connect: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Streamlabs Connection")
                        .font(.title3.bold())
                    Text("Paste your Browser Source URL or socket token below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                TextField("https://streamlabs.com/alert-box/v3/...", text: $token)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                
                Button {
                    connect()
                } label: {
                    HStack {
                        if isConnecting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Connect")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(token.isEmpty ? Color.gray : DesignSystem.Colors.primaryBlue)
                    .foregroundStyle(.white)
                    .font(.headline)
                    .cornerRadius(DesignSystem.Radius.small)
                }
                .disabled(token.isEmpty || isConnecting)
                
                Spacer()
            }
            .padding(24)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: cancel)
                }
            }
        }
    }
}

#Preview {
    ConnectionsView()
}
