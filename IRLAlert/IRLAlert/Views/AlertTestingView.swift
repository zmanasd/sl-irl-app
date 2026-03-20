import SwiftUI

/// Alert testing screen — fire mock alerts through the queue engine to test audio/UI integration.
struct AlertTestingView: View {
    @StateObject private var viewModel = AlertTestingVM()
    @EnvironmentObject var settings: AppSettings
    @State private var selectedAlertType: AlertType = .donation
    
    // For haptic feedback
    private let impactMed = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Test Control Center")
                        .font(.title2.weight(.bold))
                        .tracking(-0.5)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 16)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Readiness Section
                        readinessSection
                        
                        // Alert Types Grid
                        alertSelectionGrid
                        
                        // Config Section (Visual placeholders from HTML)
                        configSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 120) // Space for fixed deploy button + tab bar
                }
            }
            
            // Fixed Deploy Button above Tab Bar
            VStack {
                Spacer()
                Button(action: deployTestAlert) {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                        Text("Deploy Test Alert")
                            .font(.headline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(DesignSystem.Colors.primaryBlue)
                    .foregroundColor(.white)
                    .cornerRadius(DesignSystem.Radius.medium)
                    .shadow(color: DesignSystem.Colors.primaryBlue.opacity(0.3), radius: 10, y: 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 80) // Above tab bar
            }
        }
    }
    
    // MARK: - Subcomponents
    
    private var readinessSection: some View {
        VStack(spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(DesignSystem.Colors.primaryBlue)
                    Text("SYSTEM READINESS")
                        .font(.caption.weight(.bold))
                        .tracking(1.0)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(viewModel.isReady ? "ONLINE" : "OFFLINE")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(viewModel.isReady ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                    .foregroundColor(viewModel.isReady ? .green : .red)
                    .clipShape(Capsule())
            }
            
            VStack(spacing: 8) {
                HStack {
                    Text("Signal Integrity")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(viewModel.isReady ? "100%" : "0%")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(DesignSystem.Colors.primaryBlue)
                }
                
                // Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.2))
                        Capsule()
                            .fill(viewModel.isReady ? DesignSystem.Colors.primaryBlue : Color.gray)
                            .frame(width: viewModel.isReady ? geo.size.width : 0)
                    }
                }
                .frame(height: 8)
            }
            
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.caption)
                Text(viewModel.isReady ? "Testing engine connected and ready for deployment." : "Waiting for active service connection.")
                    .font(.caption)
                    .lineLimit(2)
            }
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(Color.appCard)
        .cornerRadius(DesignSystem.Radius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
    
    private var alertSelectionGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SIMULATE ALERT TYPES")
                .font(.caption.weight(.bold))
                .tracking(1.0)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
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
                        .fill(color.opacity(isSelected ? 0.2 : 0.05))
                        .frame(width: 40, height: 40)
                    Image(systemName: type.iconName)
                        .foregroundColor(color)
                        .font(.system(size: 20))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(type.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Text(mockDescription(for: type))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(isSelected ? Color.appCard : Color.appBackground)
            .cornerRadius(DesignSystem.Radius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                    .stroke(isSelected ? color : Color.secondary.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var configSection: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $settings.ttsEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Text-to-Speech")
                        .font(.body.weight(.medium))
                    Text("Read mock alert payload out loud")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .tint(DesignSystem.Colors.primaryBlue)
            .padding(16)
            
            Divider().padding(.leading, 16)
            
            Toggle(isOn: .constant(true)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Force Audio Override")
                        .font(.body.weight(.medium))
                    Text("Bypass Do Not Disturb (Simulation only)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .tint(DesignSystem.Colors.primaryBlue)
            .padding(16)
            .disabled(true)
        }
        .background(Color.appCard)
        .cornerRadius(DesignSystem.Radius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
    
    // MARK: - Actions
    
    private func deployTestAlert() {
        if settings.hapticFeedbackEnabled { impactHeavy.impactOccurred() }
        viewModel.sendTestAlert(type: selectedAlertType)
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
