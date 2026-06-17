import SwiftUI

/// Minimal PiP overlay view to render inside a video layer.
struct PiPStatusView: View {
    let alertTitle: String
    let connectionHealthy: Bool
    let queueCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(connectionHealthy ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(connectionHealthy ? "Connected" : "Disconnected")
                    .font(.caption.weight(.semibold))
            }

            Text(alertTitle)
                .font(.headline.weight(.bold))
                .lineLimit(1)

            Text("Queue: \(queueCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.black.opacity(0.6))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
