import SwiftUI

/// Placeholder for the alert testing / simulation screen.
/// Will be wired to the AlertQueueManager in Phase 2.
struct AlertTestingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "flask.fill")
                .font(.system(size: 64))
                .foregroundStyle(.primary)
            Text("Alert Testing")
                .font(.title2)
                .fontWeight(.bold)
            Text("Coming in Phase 2")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    AlertTestingView()
}
