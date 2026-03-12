import SwiftUI

/// Placeholder for the settings screen.
/// Will be fully implemented in Phase 4.
struct SettingsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 64))
                .foregroundStyle(.primary)
            Text("Settings")
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
    SettingsView()
}
