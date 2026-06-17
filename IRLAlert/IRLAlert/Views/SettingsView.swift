import SwiftUI
import UIKit
import UserNotifications

/// Settings screen for configuring app behavior and alerts.
struct SettingsView: View {
    @StateObject private var viewModel = SettingsVM()
    @ObservedObject private var pushManager = PushNotificationManager.shared
    @ObservedObject private var relayClient = RelayClient.shared
    @State private var diagnosticsCopiedAt: Date?
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    HStack {
                        Text("Settings")
                            .font(.largeTitle.weight(.bold))
                            .tracking(-0.5)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    
                    // User Profile Mockup
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(DesignSystem.Colors.primaryBlue.opacity(0.2))
                                .frame(width: 56, height: 56)
                                .overlay(
                                    Circle().stroke(DesignSystem.Colors.primaryBlue.opacity(0.3), lineWidth: 1)
                                )
                            Image(systemName: "person.fill")
                                .font(.title)
                                .foregroundStyle(DesignSystem.Colors.primaryBlue)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Local Device")
                                .font(.headline)
                            Text("Twitch MVP Device")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                            .font(.footnote.bold())
                    }
                    .padding(16)
                    .background(Color.appCard)
                    .cornerRadius(DesignSystem.Radius.medium)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                    
                    // Alert Preferences
                    SettingsSection(title: "Alert Preferences") {
                        // Alert Volume
                        SettingsSliderRow(
                            icon: "speaker.wave.3.fill",
                            iconColor: .red,
                            title: "Alert Volume",
                            value: $viewModel.alertVolume,
                            range: 0...1,
                            format: { "\(Int($0 * 100))%" }
                        )
                        
                        Divider().padding(.leading, 56)
                        
                        // TTS Toggle
                        SettingsToggleRow(
                            icon: "text.bubble.fill",
                            iconColor: .blue,
                            title: "Enable Text-to-Speech",
                            isOn: $viewModel.ttsEnabled
                        )
                        
                        Divider().padding(.leading, 56)
                        
                        // TTS Volume
                        if viewModel.ttsEnabled {
                            SettingsSliderRow(
                                icon: "volume.2.fill",
                                iconColor: .cyan,
                                title: "TTS Volume",
                                value: $viewModel.ttsVolume,
                                range: 0...1,
                                format: { "\(Int($0 * 100))%" }
                            )
                            Divider().padding(.leading, 56)
                        }
                        
                        // TTS Voice Selection
                        SettingsPickerRow(
                            icon: "person.wave.2.fill",
                            iconColor: .purple,
                            title: "TTS Voice",
                            selection: $viewModel.selectedVoiceId,
                            options: viewModel.availableVoices.map { ($0.id, "\($0.name) (\($0.language))") }
                        )
                        
                        Divider().padding(.leading, 56)
                        
                        // Haptic Feedback
                        SettingsToggleRow(
                            icon: "iphone.radiowaves.left.and.right",
                            iconColor: .gray,
                            title: "Haptic Feedback",
                            isOn: $viewModel.hapticFeedbackEnabled
                        )
                    }
                    
                    // Queue Management
                    SettingsSection(title: "Queue Management") {
                        // Queue Overflow Threshold
                        SettingsStepperRow(
                            icon: "layers.fill",
                            iconColor: .orange,
                            title: "Queue Overflow Limit",
                            value: Binding(
                                get: { Double(viewModel.queueOverflowThreshold) },
                                set: { viewModel.queueOverflowThreshold = Int($0) }
                            ),
                            range: 5...50,
                            step: 5,
                            format: { "\(Int($0)) Alerts" }
                        )
                        
                        Divider().padding(.leading, 56)
                        
                        // Inter-Alert Delay
                        SettingsStepperRow(
                            icon: "clock.fill",
                            iconColor: .mint,
                            title: "Inter-Alert Delay",
                            value: $viewModel.interAlertDelay,
                            range: 0...5,
                            step: 0.5,
                            format: { String(format: "%.1fs", $0) }
                        )
                    }

                    // Relay & Notifications
                    SettingsSection(title: "Relay & Notifications") {
                        SettingsToggleRow(
                            icon: "bell.badge.fill",
                            iconColor: .orange,
                            title: "Enable Push Alerts",
                            isOn: $viewModel.pushNotificationsEnabled
                        )

                        Divider().padding(.leading, 56)

                        SettingsTextFieldRow(
                            icon: "server.rack",
                            iconColor: .indigo,
                            title: "Relay URL",
                            text: $viewModel.relayBaseURL,
                            placeholder: "https://relay.example.com"
                        )
                    }

                    SettingsSection(title: "Delivery Diagnostics") {
                        SettingsInfoRow(
                            icon: "bell.badge",
                            iconColor: .orange,
                            title: "Push Permission",
                            value: pushManager.authorizationStatus.diagnosticsTitle
                        )

                        Divider().padding(.leading, 56)

                        SettingsInfoRow(
                            icon: "key.fill",
                            iconColor: .teal,
                            title: "APNs Token",
                            value: deviceTokenStatus
                        )

                        Divider().padding(.leading, 56)

                        SettingsInfoRow(
                            icon: "calendar.badge.clock",
                            iconColor: .purple,
                            title: "Token Updated",
                            value: formattedDate(pushManager.deviceTokenRegisteredAt)
                        )

                        Divider().padding(.leading, 56)

                        SettingsInfoRow(
                            icon: "server.rack",
                            iconColor: .indigo,
                            title: "Relay URL",
                            value: RelayClient.shared.diagnosticsBaseURL
                        )

                        Divider().padding(.leading, 56)

                        SettingsInfoRow(
                            icon: "person.crop.circle.badge.checkmark",
                            iconColor: .green,
                            title: "Relay User",
                            value: shortIdentifier(AppSettings.shared.relayUserId)
                        )

                        Divider().padding(.leading, 56)

                        SettingsInfoRow(
                            icon: "antenna.radiowaves.left.and.right",
                            iconColor: .pink,
                            title: "Relay Register",
                            value: relayRegistrationStatus
                        )

                        Divider().padding(.leading, 56)

                        SettingsInfoRow(
                            icon: "tray.and.arrow.down.fill",
                            iconColor: .blue,
                            title: "Push Receipts",
                            value: "\(pushManager.acceptedNotificationCount)/\(pushManager.receivedNotificationCount) accepted"
                        )

                        Divider().padding(.leading, 56)

                        SettingsInfoRow(
                            icon: "link",
                            iconColor: .cyan,
                            title: "Last Correlation",
                            value: pushManager.lastAcceptedAlert?.externalIdentity ?? "None"
                        )

                        Divider().padding(.leading, 56)

                        SettingsInfoRow(
                            icon: "paperplane.fill",
                            iconColor: .blue,
                            title: "Last Relay Test",
                            value: relayTestStatus
                        )

                        Divider().padding(.leading, 56)

                        SettingsInfoRow(
                            icon: "stethoscope",
                            iconColor: .green,
                            title: "MVP Readiness",
                            value: relayReadinessStatus
                        )

                        Divider().padding(.leading, 56)

                        SettingsInfoRow(
                            icon: "server.rack",
                            iconColor: .indigo,
                            title: "Relay Ready",
                            value: relayClient.lastReadinessSummary
                        )

                        Divider().padding(.leading, 56)

                        SettingsInfoRow(
                            icon: "stethoscope",
                            iconColor: .green,
                            title: "Relay Snapshot",
                            value: relayDiagnosticsStatus
                        )

                        Divider().padding(.leading, 56)

                        SettingsInfoRow(
                            icon: "bell.and.waves.left.and.right",
                            iconColor: .orange,
                            title: "Relay APNs",
                            value: relayClient.lastDiagnosticsApnsReadiness
                        )

                        Divider().padding(.leading, 56)

                        SettingsInfoRow(
                            icon: "iphone.gen3",
                            iconColor: .teal,
                            title: "Relay Device",
                            value: relayClient.lastDiagnosticsDeviceTokenStatus
                        )

                        Divider().padding(.leading, 56)

                        SettingsInfoRow(
                            icon: "key.viewfinder",
                            iconColor: .purple,
                            title: "Twitch OAuth",
                            value: relayClient.lastDiagnosticsTwitchOAuthReadiness
                        )

                        Divider().padding(.leading, 56)

                        SettingsInfoRow(
                            icon: "arrow.clockwise.icloud",
                            iconColor: .green,
                            title: "Relay Recovery",
                            value: relayClient.lastDiagnosticsConnectorRecoveryStatus
                        )

                        Divider().padding(.leading, 56)

                        SettingsInfoRow(
                            icon: "message.fill",
                            iconColor: .purple,
                            title: "Twitch Status",
                            value: relayClient.lastDiagnosticsTwitchStatus
                        )

                        Divider().padding(.leading, 56)

                        SettingsInfoRow(
                            icon: "arrow.triangle.2.circlepath",
                            iconColor: .indigo,
                            title: "Twitch Refresh",
                            value: relayClient.lastDiagnosticsTwitchRefreshStatus
                        )

                        Divider().padding(.leading, 56)

                        SettingsInfoRow(
                            icon: "square.stack.3d.down.right",
                            iconColor: .brown,
                            title: "Provider Dedupe",
                            value: relayClient.lastDiagnosticsProviderDedupeStatus
                        )

                        Divider().padding(.leading, 56)

                        SettingsInfoRow(
                            icon: "shippingbox.fill",
                            iconColor: .cyan,
                            title: "Relay Delivery",
                            value: relayClient.lastDiagnosticsDeliveryStatus
                        )

                        Divider().padding(.leading, 56)

                        SettingsInfoRow(
                            icon: "clock.badge.checkmark",
                            iconColor: .mint,
                            title: "Last Received",
                            value: formattedDate(pushManager.lastNotificationReceivedAt)
                        )

                        if let reason = pushManager.lastDroppedAlertReason {
                            Divider().padding(.leading, 56)

                            SettingsInfoRow(
                                icon: "exclamationmark.triangle.fill",
                                iconColor: .yellow,
                                title: "Last Drop",
                                value: reason
                            )
                        }

                        if let error = pushManager.lastRegistrationError {
                            Divider().padding(.leading, 56)

                            SettingsInfoRow(
                                icon: "xmark.octagon.fill",
                                iconColor: .red,
                                title: "APNs Error",
                                value: error
                            )
                        }

                        Divider().padding(.leading, 56)

                        Button {
                            Task { await pushManager.refreshAuthorizationStatus() }
                        } label: {
                            HStack(spacing: 12) {
                                SettingsIcon(icon: "arrow.clockwise", color: .gray)
                                Text("Refresh Push Status")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                            }
                            .padding(16)
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.leading, 56)

                        Button {
                            Task { await relayClient.fetchDiagnostics() }
                        } label: {
                            HStack(spacing: 12) {
                                SettingsIcon(icon: "stethoscope", color: .green)
                                Text(relayClient.isFetchingDiagnostics ? "Refreshing Relay Diagnostics" : "Refresh Relay Diagnostics")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                            }
                            .padding(16)
                        }
                        .buttonStyle(.plain)
                        .disabled(relayClient.isFetchingDiagnostics)

                        Divider().padding(.leading, 56)

                        Button {
                            Task { await relayClient.fetchReadiness() }
                        } label: {
                            HStack(spacing: 12) {
                                SettingsIcon(icon: "checkmark.shield", color: .green)
                                Text(relayClient.isFetchingReadiness ? "Checking MVP Readiness" : "Check MVP Readiness")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                            }
                            .padding(16)
                        }
                        .buttonStyle(.plain)
                        .disabled(relayClient.isFetchingReadiness)

                        Divider().padding(.leading, 56)

                        Button {
                            Task { await relayClient.sendRelayTestAlert() }
                        } label: {
                            HStack(spacing: 12) {
                                SettingsIcon(icon: "paperplane", color: .blue)
                                Text(relayClient.isSendingTestAlert ? "Sending Relay Test" : "Send Relay Test Alert")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                            }
                            .padding(16)
                        }
                        .buttonStyle(.plain)
                        .disabled(relayClient.isSendingTestAlert)

                        Divider().padding(.leading, 56)

                        Button {
                            copyDiagnosticsSnapshot()
                        } label: {
                            HStack(spacing: 12) {
                                SettingsIcon(
                                    icon: diagnosticsCopiedAt == nil ? "doc.on.clipboard" : "checkmark.circle.fill",
                                    color: diagnosticsCopiedAt == nil ? .gray : .green
                                )
                                Text(diagnosticsCopiedAt == nil ? "Copy Diagnostics Snapshot" : "Diagnostics Snapshot Copied")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                            }
                            .padding(16)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Alert Types (Filters)
                    SettingsSection(title: "Enabled Alerts") {
                        ForEach(AlertType.allCases, id: \.self) { type in
                            SettingsToggleRow(
                                icon: type.iconName,
                                iconColor: type.accentColor,
                                title: type.rawValue.capitalized,
                                isOn: Binding(
                                    get: { viewModel.enabledAlertTypes.contains(type) },
                                    set: { _ in viewModel.toggleAlertType(type) }
                                )
                            )
                            if type != AlertType.allCases.last {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                    
                    // Reset Button
                    Button {
                        viewModel.resetToDefaults()
                    } label: {
                        Text("Reset All Settings")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.appCard)
                            .foregroundStyle(.red)
                            .cornerRadius(DesignSystem.Radius.medium)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                                    .stroke(Color.red.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }
                .padding(.bottom, 120) // Tab bar clearance
            }
        }
    }

    private var deviceTokenStatus: String {
        guard let token = pushManager.deviceToken, !token.isEmpty else { return "Missing" }
        return "Available \(shortIdentifier(token))"
    }

    private var relayRegistrationStatus: String {
        if let error = relayClient.lastRegistrationError {
            return error
        }

        if let statusCode = relayClient.lastRegistrationStatusCode {
            return "HTTP \(statusCode)"
        }

        if relayClient.lastRegistrationAttemptAt != nil {
            return "Pending"
        }

        return "Not attempted"
    }

    private var relayTestStatus: String {
        if let error = relayClient.lastTestAlertError {
            return error
        }

        if let correlationId = relayClient.lastTestAlertCorrelationId,
           let statusCode = relayClient.lastTestAlertStatusCode {
            return "\(shortIdentifier(correlationId)) HTTP \(statusCode)"
        }

        if relayClient.isSendingTestAlert {
            return "Sending"
        }

        return "Not sent"
    }

    private var relayReadinessStatus: String {
        if let error = relayClient.lastReadinessError {
            return error
        }

        if let statusCode = relayClient.lastReadinessStatusCode {
            return "\(relayClient.lastUserReadinessSummary) HTTP \(statusCode)"
        }

        if relayClient.isFetchingReadiness {
            return "Fetching"
        }

        return relayClient.lastUserReadinessSummary
    }

    private var relayDiagnosticsStatus: String {
        if let error = relayClient.lastDiagnosticsError {
            return error
        }

        if let statusCode = relayClient.lastDiagnosticsStatusCode {
            return "\(relayClient.lastDiagnosticsSummary) HTTP \(statusCode)"
        }

        if relayClient.isFetchingDiagnostics {
            return "Fetching"
        }

        return relayClient.lastDiagnosticsSummary
    }

    private func shortIdentifier(_ value: String) -> String {
        guard value.count > 12 else { return value }
        return "\(value.prefix(6))...\(value.suffix(6))"
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return date.formatted(date: .omitted, time: .standard)
    }

    private func copyDiagnosticsSnapshot() {
        UIPasteboard.general.string = viewModel.diagnosticsSnapshot(
            pushManager: pushManager,
            relayClient: relayClient
        )
        diagnosticsCopiedAt = Date()
    }
}

// MARK: - Reusable Settings Components

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(1.0)
                .padding(.horizontal, 32)
            
            VStack(spacing: 0) {
                content()
            }
            .background(Color.appCard)
            .cornerRadius(DesignSystem.Radius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
    }
}

struct SettingsIcon: View {
    let icon: String
    let color: Color
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(color)
                .frame(width: 32, height: 32)
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                SettingsIcon(icon: icon, color: iconColor)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
        }
        .tint(DesignSystem.Colors.primaryBlue)
        .padding(16)
    }
}

struct SettingsSliderRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let format: (Float) -> String
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 12) {
                    SettingsIcon(icon: icon, color: iconColor)
                    Text(title)
                        .font(.subheadline.weight(.medium))
                }
                Spacer()
                Text(format(value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DesignSystem.Colors.primaryBlue)
            }
            Slider(value: $value, in: range)
                .tint(DesignSystem.Colors.primaryBlue)
        }
        .padding(16)
    }
}

struct SettingsStepperRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    
    var body: some View {
        HStack {
            HStack(spacing: 12) {
                SettingsIcon(icon: icon, color: iconColor)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            Spacer()
            
            HStack(spacing: 16) {
                Text(format(value))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Stepper("", value: $value, in: range, step: step)
                    .labelsHidden()
            }
        }
        .padding(16)
    }
}

struct SettingsInfoRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(icon: icon, color: iconColor)

            Text(title)
                .font(.subheadline.weight(.medium))

            Spacer(minLength: 12)

            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
        }
        .padding(16)
    }
}

struct SettingsPickerRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    @Binding var selection: String?
    let options: [(id: String, name: String)]
    
    var body: some View {
        HStack {
            HStack(spacing: 12) {
                SettingsIcon(icon: icon, color: iconColor)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            Spacer()
            
            Picker("", selection: Binding(
                get: { selection ?? "" },
                set: { selection = $0.isEmpty ? nil : $0 }
            )) {
                Text("System Default").tag("")
                ForEach(options, id: \.id) { option in
                    Text(option.name).tag(option.id)
                }
            }
            .pickerStyle(.menu)
            .tint(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct SettingsTextFieldRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SettingsIcon(icon: icon, color: iconColor)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }

            TextField(placeholder, text: $text)
                .font(.caption.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(12)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(DesignSystem.Radius.small)
        }
        .padding(16)
    }
}

#Preview {
    SettingsView()
}

private extension UNAuthorizationStatus {
    var diagnosticsTitle: String {
        switch self {
        case .notDetermined: "Not Asked"
        case .denied: "Denied"
        case .authorized: "Authorized"
        case .provisional: "Provisional"
        case .ephemeral: "Ephemeral"
        @unknown default: "Unknown"
        }
    }
}
