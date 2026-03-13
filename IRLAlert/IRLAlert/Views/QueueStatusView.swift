import SwiftUI

/// A reusable pill component that displays the current number of alerts
/// waiting in the queue, along with a pulsing indicator when processing.
struct QueueStatusView: View {
    @ObservedObject var queueManager = AlertQueueManager.shared
    
    // Animation state for the pulsing ring
    @State private var pulseScale: CGFloat = 0.8
    @State private var pulseOpacity: Double = 1.0
    
    var body: some View {
        HStack(spacing: 8) {
            // Processing Dot
            ZStack {
                Circle()
                    .fill(queueManager.isProcessing ? DesignSystem.Colors.alertGreen : Color.secondary)
                    .frame(width: 8, height: 8)
                
                if queueManager.isProcessing {
                    Circle()
                        .stroke(DesignSystem.Colors.alertGreen, lineWidth: 2)
                        .frame(width: 16, height: 16)
                        .scaleEffect(pulseScale)
                        .opacity(pulseOpacity)
                }
            }
            .frame(width: 16, height: 16)
            
            // Queue Count Text
            Text("\(queueManager.queueCount) in queue")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.secondary)
                .textCase(.uppercase)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(Color.appCard)
                .overlay(
                    Capsule().stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
        .task(id: queueManager.isProcessing) {
            guard queueManager.isProcessing else {
                // Reset to idle state cleanly
                pulseScale = 0.8
                pulseOpacity = 1.0
                return
            }
            // Run pulse loop while processing
            while !Task.isCancelled {
                withAnimation(.easeOut(duration: 1.2)) {
                    pulseScale = 1.5
                    pulseOpacity = 0
                }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard !Task.isCancelled else { break }
                pulseScale = 0.8
                pulseOpacity = 1.0
            }
        }
    }
}

#Preview {
    ZStack {
        Color.appBackground.ignoresSafeArea()
        QueueStatusView()
    }
}
