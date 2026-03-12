import SwiftUI

/// Placeholder for the connections management screen.
/// Will be fully implemented in Phase 4.
struct ConnectionsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.primary)
            Text("Connections")
                .font(.title2)
                .fontWeight(.bold)
            Text("Coming in Phase 3–4")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ConnectionsView()
}
