import SwiftUI

/// Placeholder for the main dashboard screen.
/// Will be fully implemented in Phase 4.
struct DashboardView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 64))
                .foregroundStyle(.primary)
            Text("Dashboard")
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
    DashboardView()
}
