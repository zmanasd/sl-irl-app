import SwiftUI

/// A reusable pill component that displays the current number of alerts
/// waiting in the queue, along with a pulsing indicator when processing.
struct QueueStatusView: View {
    @ObservedObject var queueManager = AlertQueueManager.shared
    
    // Animation state for the pulsing dot
    @State private var isPulsing = false
    
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
                        .scaleEffect(isPulsing ? 1.5 : 0.8)
                        .opacity(isPulsing ? 0 : 1)
                        .animation(
                            .easeOut(duration: 1.5).repeatForever(autoreverses: false),
                            value: isPulsing
                        )
                }
            }
            .frame(width: 16, height: 16)
            
            // Queue Count Text
            Text("\(queueManager.queueCount) in queue")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.secondary)
                .textCase(.uppercase)
                .contentTransition(.numericText()) // iOS 16+ smooth number changes
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
        .onChange(of: queueManager.isProcessing) { _, isProcessing in
            if isProcessing {
                isPulsing = true
            } else {
                isPulsing = false
            }
        }
        .onAppear {
            if queueManager.isProcessing {
                isPulsing = true
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
