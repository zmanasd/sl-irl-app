import SwiftUI

/// Settings screen for configuring app behavior and alerts.
struct SettingsView: View {
    @StateObject private var viewModel = SettingsVM()
    
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
                            Text("IRL Alert Basic")
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
                        
                        Divider().padding(.leading, 56)
                        
                        // Disconnect Timeout
                        SettingsStepperRow(
                            icon: "wifi.slash",
                            iconColor: .indigo,
                            title: "Disconnect Timeout",
                            value: $viewModel.disconnectNotificationTimeout,
                            range: 10...300,
                            step: 10,
                            format: { "\(Int($0))s" }
                        )
                    }

                    // Background & Notifications
                    SettingsSection(title: "Background & Notifications") {
                        SettingsToggleRow(
                            icon: "pip",
                            iconColor: .purple,
                            title: "Enable PiP on Background",
                            isOn: $viewModel.pipEnabled
                        )

                        Divider().padding(.leading, 56)

                        SettingsToggleRow(
                            icon: "bell.badge.fill",
                            iconColor: .orange,
                            title: "Enable Push Alerts",
                            isOn: $viewModel.pushNotificationsEnabled
                        )
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

#Preview {
    SettingsView()
}
