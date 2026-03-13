import SwiftUI

/// Alert testing screen — fire mock alerts through the queue engine.
struct AlertTestingView: View {
    @State private var selectedAlertType: AlertType = .donation
    @ObservedObject var queueManager = AlertQueueManager.shared
    @EnvironmentObject var settings: AppSettings
    
    // For haptic feedback
    private let impactMed = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    
    // Columns for the 2x3 grid
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Test Control Center")
                        .font(.system(size: 20, weight: .semibold, design: .default))
                        .tracking(-0.5)
                    Spacer()
                    QueueStatusView()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
                
                ScrollView {
                    VStack(spacing: 24) {
                        readinessSection
                        alertSelectionGrid
                        configSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 120) // Space for bottom tab bar + CTA
                }
            }
            
            // Floating Deploy Button
            VStack {
                Spacer()
                Button(action: deployTestAlert) {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                        Text("Deploy Test Alert")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(DesignSystem.Colors.primaryBlue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: DesignSystem.Colors.primaryBlue.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }
    
    // MARK: - Subviews
    
    private var readinessSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(DesignSystem.Colors.primaryBlue)
                    Text("SYSTEM READINESS")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("ONLINE")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .clipShape(Capsule())
            }
            
            VStack(spacing: 8) {
                HStack {
                    Text("Signal Integrity")
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Text("100%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.primaryBlue)
                }
                
                // Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.2))
                        Capsule()
                            .fill(DesignSystem.Colors.primaryBlue)
                            .frame(width: geo.size.width)
                    }
                }
                .frame(height: 8)
            }
            
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                Text("Audio session active. Testing engine ready.")
                    .font(.system(size: 12))
            }
            .foregroundColor(.secondary)
        }
        .padding(20)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var alertSelectionGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SIMULATE ALERT TYPES")
                .font(.system(size: 12, weight: .bold))
                .tracking(1.5)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(AlertType.allCases) { type in
                    alertTypeButton(for: type)
                }
            }
        }
    }
    
    private func alertTypeButton(for type: AlertType) -> some View {
        let isSelected = selectedAlertType == type
        let color = type.accentColor
        
        return Button {
            if settings.hapticFeedbackEnabled { impactMed.impactOccurred() }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedAlertType = type
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(isSelected ? 0.2 : 0.1))
                        .frame(width: 40, height: 40)
                    Image(systemName: type.iconName)
                        .foregroundColor(color)
                        .font(.system(size: 20))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(type.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(mockDescription(for: type))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.appCard)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? color : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
        }
    }
    
    private var configSection: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $settings.ttsEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Read Alert Text (TTS)")
                        .font(.system(size: 16, weight: .medium))
                    Text("Speak the alert message out loud")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 16)
            
            Divider().padding(.leading, 0)
            
            Toggle(isOn: .constant(true)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bypass Audio Filters")
                        .font(.system(size: 16, weight: .medium))
                    Text("Play over other active audio sources")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 16)
            .disabled(true) // Just visual for now
        }
        .padding(.horizontal, 20)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Actions
    
    private func deployTestAlert() {
        if settings.hapticFeedbackEnabled { impactHeavy.impactOccurred() }
        
        let mockEvent: AlertEvent
        switch selectedAlertType {
        case .donation:
            mockEvent = .mockDonation()
        case .follow:
            mockEvent = .mockFollow()
        case .subscription:
            mockEvent = .mockSubscription()
        case .bits:
            mockEvent = .mockBits()
        case .host:
            // Custom host mock since we don't have a factory for it yet
            mockEvent = AlertEvent(type: .host, username: "BigStreamer", amount: 1234, source: .mock)
        case .raid:
            mockEvent = .mockRaid()
        }
        
        // Ensure this alert type is enabled in settings for testing
        if !settings.enabledAlertTypes.contains(selectedAlertType) {
            settings.enabledAlertTypes.insert(selectedAlertType)
        }
        
        queueManager.enqueue(mockEvent)
    }
    
    private func mockDescription(for type: AlertType) -> String {
        switch type {
        case .donation: return "Simulate $5.00 tip"
        case .follow: return "New follower alert"
        case .subscription: return "Tier 1 Sub alert"
        case .bits: return "100 Bits cheer"
        case .host: return "Inbound host"
        case .raid: return "Incoming raid (25+)"
        }
    }
}

#Preview {
    AlertTestingView()
        .environmentObject(AppSettings())
}
