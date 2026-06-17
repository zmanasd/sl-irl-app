import SwiftUI

/// Main view for Twitch relay setup, iPhone registration, and delivery diagnostics.
struct ConnectionsView: View {
    @StateObject private var viewModel = ConnectionsVM()
    @ObservedObject private var pushManager = PushNotificationManager.shared
    @ObservedObject private var relayClient = RelayClient.shared
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.openURL) private var openURL
    
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
                    
                    // MVP Status Banner
                    MVPStatusBanner(
                        pushEnabled: appSettings.pushNotificationsEnabled,
                        hasDeviceToken: pushManager.deviceToken != nil,
                        relayStatus: relayRegistrationStatus,
                        twitchReady: relayClient.twitchEventSubReady
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
                    
                    // Twitch MVP proof setup
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("TWITCH MVP SETUP")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .tracking(1.0)
                            
                            Spacer()
                            
                            Text("Proof-first")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DesignSystem.Colors.primaryBlue)
                        }
                        .padding(.horizontal, 24)
                        
                        VStack(spacing: 12) {
                            MVPConnectionActionRow(
                                icon: "message.fill",
                                iconColor: .purple,
                                title: "Connect Twitch",
                                subtitle: twitchOAuthSubtitle,
                                isLoading: relayClient.isStartingTwitchOAuth
                            ) {
                                Task {
                                    if let url = await viewModel.createTwitchOAuthURL() {
                                        openURL(url)
                                    }
                                }
                            }
                            
                            MVPConnectionActionRow(
                                icon: "iphone.radiowaves.left.and.right",
                                iconColor: .orange,
                                title: "Register This iPhone",
                                subtitle: deviceRegistrationSubtitle,
                                isLoading: false
                            ) {
                                Task { await viewModel.registerDeviceForMVP() }
                            }

                            MVPConnectionActionRow(
                                icon: "paperplane.fill",
                                iconColor: .blue,
                                title: "Send Relay Test Alert",
                                subtitle: relayTestSubtitle,
                                isLoading: relayClient.isSendingTestAlert
                            ) {
                                Task { await viewModel.sendRelayTestAlert() }
                            }

                            MVPConnectionActionRow(
                                icon: "checkmark.shield.fill",
                                iconColor: .green,
                                title: "Check MVP Readiness",
                                subtitle: relayReadinessSubtitle,
                                isLoading: relayClient.isFetchingReadiness
                            ) {
                                Task { await viewModel.refreshRelayReadiness() }
                            }

                            MVPConnectionActionRow(
                                icon: "stethoscope",
                                iconColor: .teal,
                                title: "Refresh Relay Diagnostics",
                                subtitle: relayDiagnosticsSubtitle,
                                isLoading: relayClient.isFetchingDiagnostics
                            ) {
                                Task { await viewModel.refreshRelayDiagnostics() }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    
                    // Relay Details
                    VStack(alignment: .leading, spacing: 16) {
                        Text("RELAY DETAILS")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .tracking(1.0)
                            .padding(.horizontal, 24)
                        
                        VStack(spacing: 12) {
                            MVPInfoRow(title: "Relay URL", value: appSettings.relayBaseURL)
                            MVPInfoRow(title: "Relay User", value: shortIdentifier(appSettings.relayUserId))
                            MVPInfoRow(title: "APNs Token", value: pushManager.deviceToken == nil ? "Missing" : "Available")
                            MVPInfoRow(title: "Last Correlation", value: pushManager.lastAcceptedAlert?.externalIdentity ?? relayClient.lastTestAlertCorrelationId ?? "None")
                            MVPInfoRow(title: "MVP Readiness", value: relayClient.lastUserReadinessSummary)
                            MVPInfoRow(title: "Relay Ready", value: relayClient.lastReadinessSummary)
                            MVPInfoRow(title: "Relay Snapshot", value: relayClient.lastDiagnosticsSummary)
                            MVPInfoRow(title: "Relay APNs", value: relayClient.lastDiagnosticsApnsReadiness)
                            MVPInfoRow(title: "Twitch OAuth", value: relayClient.lastDiagnosticsTwitchOAuthReadiness)
                            MVPInfoRow(title: "Twitch Status", value: relayClient.lastDiagnosticsTwitchStatus)
                            MVPInfoRow(title: "Last Delivery", value: relayClient.lastDiagnosticsDeliveryStatus)
                        }
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 120) // Tab bar clearance
            }
        }
    }

    private var relayRegistrationStatus: String {
        if let error = relayClient.lastRegistrationError { return error }
        if let statusCode = relayClient.lastRegistrationStatusCode { return "HTTP \(statusCode)" }
        return "Not registered"
    }

    private var twitchOAuthSubtitle: String {
        if let error = relayClient.lastTwitchOAuthError { return error }
        if let date = relayClient.lastTwitchOAuthStartedAt {
            return "Started \(date.formatted(date: .omitted, time: .shortened))"
        }
        return "Open Twitch authorization through the relay"
    }

    private var deviceRegistrationSubtitle: String {
        if let error = relayClient.lastRegistrationError { return error }
        if let date = relayClient.lastRegistrationSucceededAt {
            return "Registered \(date.formatted(date: .omitted, time: .shortened))"
        }
        if pushManager.deviceToken == nil {
            return "Request APNs permission and send token to relay"
        }
        return "Send current APNs token to relay"
    }

    private var relayTestSubtitle: String {
        if let error = relayClient.lastTestAlertError { return error }
        if let correlationId = relayClient.lastTestAlertCorrelationId {
            return shortIdentifier(correlationId)
        }
        return "Exercise relay -> APNs -> iPhone delivery"
    }

    private var relayReadinessSubtitle: String {
        if let error = relayClient.lastReadinessError { return error }
        if let date = relayClient.lastReadinessFetchedAt {
            return "Checked \(date.formatted(date: .omitted, time: .shortened))"
        }
        return "Verify Twitch EventSub, OAuth, APNs, and this relay user"
    }

    private var relayDiagnosticsSubtitle: String {
        if let error = relayClient.lastDiagnosticsError { return error }
        if let date = relayClient.lastDiagnosticsFetchedAt {
            return "Fetched \(date.formatted(date: .omitted, time: .shortened))"
        }
        return "Compare relay state with this iPhone"
    }

    private func shortIdentifier(_ value: String) -> String {
        guard value.count > 12 else { return value }
        return "\(value.prefix(6))...\(value.suffix(6))"
    }
}

// MARK: - Subcomponents

struct MVPStatusBanner: View {
    let pushEnabled: Bool
    let hasDeviceToken: Bool
    let relayStatus: String
    let twitchReady: Bool

    private var isReady: Bool {
        pushEnabled && hasDeviceToken && relayStatus.hasPrefix("HTTP 2") && twitchReady
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isReady ? DesignSystem.Colors.alertGreen : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(isReady ? "MVP PROOF READY" : "SETUP REQUIRED")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(isReady ? DesignSystem.Colors.alertGreen : Color.orange)
                        .tracking(1.0)
                }

                Text("MVP delivery requires Twitch EventSub diagnostics, relay registration, and APNs on this iPhone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(16)
        .background(isReady ? DesignSystem.Colors.alertGreen.opacity(0.05) : Color.orange.opacity(0.07))
        .cornerRadius(DesignSystem.Radius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .stroke(isReady ? DesignSystem.Colors.alertGreen.opacity(0.15) : Color.orange.opacity(0.15), lineWidth: 1)
        )
    }
}

struct MVPConnectionActionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconColor.opacity(0.14))
                        .frame(width: 42, height: 42)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(iconColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Color.appCard)
            .cornerRadius(DesignSystem.Radius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

struct MVPInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(DesignSystem.Radius.small)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        )
    }
}

#Preview {
    ConnectionsView()
}
