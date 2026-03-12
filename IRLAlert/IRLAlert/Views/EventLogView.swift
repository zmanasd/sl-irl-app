import SwiftUI

/// Placeholder for the event log / alerts list screen.
/// Will be fully implemented in Phase 4.
struct EventLogView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 64))
                .foregroundStyle(.primary)
            Text("Event Log")
                .font(.title2)
                .fontWeight(.bold)
            Text("Coming in Phase 4")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EventLogView()
}
