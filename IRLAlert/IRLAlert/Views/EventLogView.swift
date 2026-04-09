import SwiftUI

/// Main event log screen showing historical alerts and current queue status.
struct EventLogView: View {
    @StateObject private var viewModel = EventLogVM()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Area (Sticky)
            VStack(spacing: 16) {
                // Title Row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LIVE STREAM")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(DesignSystem.Colors.primaryBlue)
                            .tracking(2.0)
                        
                        Text("Event Log")
                            .font(.largeTitle.weight(.black))
                            .tracking(-0.5)
                    }
                    
                    Spacer()
                    
                    // Action Buttons
                    HStack(spacing: 8) {
                        ActionButton(icon: "trash") {
                            viewModel.clearAll()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                // Queue Status Indicator
                QueueStatusBanner(
                    count: viewModel.queueCount,
                    isProcessing: viewModel.isProcessing
                )
                .padding(.horizontal, 20)
                
                // Filter Tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(EventLogVM.EventFilter.allCases) { filter in
                            FilterTab(
                                title: filter.rawValue,
                                isSelected: viewModel.selectedFilter == filter
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    viewModel.selectedFilter = filter
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }
            .background(
                Color.appBackground.opacity(0.95)
                    .background(Material.bar)
                    .ignoresSafeArea(.all, edges: .top)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 8, y: 4)
            .zIndex(1)
            
            // Main Content Area
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.events.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "tray")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary.opacity(0.5))
                            Text("No events found")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 60)
                    } else {
                        ForEach(viewModel.events) { event in
                            AlertCardView(event: event)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .scale.combined(with: .opacity)
                                ))
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 100) // Tab bar clearance
            }
            .background(Color.appBackground)
        }
    }
}

// MARK: - Subcomponents

struct ActionButton: View {
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
    }
}

struct QueueStatusBanner: View {
    let count: Int
    let isProcessing: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Minimal pulsing dot relative to queue
            ZStack {
                if count > 0 {
                    Circle()
                        .fill(DesignSystem.Colors.primaryBlue.opacity(0.4))
                        .frame(width: 12, height: 12)
                        .scaleEffect(isProcessing ? 1.5 : 1.0)
                        .opacity(isProcessing ? 0 : 1)
                        .animation(isProcessing ? .easeInOut(duration: 1).repeatForever(autoreverses: false) : .default, value: isProcessing)
                }
                
                Circle()
                    .fill(count > 0 ? DesignSystem.Colors.primaryBlue : Color.secondary)
                    .frame(width: 12, height: 12)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(count > 0 ? "\(count) Pending Alerts" : "Queue Empty")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(count > 0 ? DesignSystem.Colors.primaryBlue : .secondary)
                
                Text(count > 0 ? "Processing queue in background" : "Waiting for new events")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(count > 0 ? DesignSystem.Colors.primaryBlue.opacity(0.1) : Color.secondary.opacity(0.1))
        .cornerRadius(DesignSystem.Radius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .stroke(count > 0 ? DesignSystem.Colors.primaryBlue.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }
}

struct FilterTab: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(isSelected ? DesignSystem.Colors.primaryBlue : Color.secondary.opacity(0.1))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
                .shadow(color: isSelected ? DesignSystem.Colors.primaryBlue.opacity(0.3) : .clear, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}

struct AlertCardView: View {
    let event: AlertEvent
    
    // Format timestamp nicely
    private var timeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: event.timestamp, relativeTo: Date())
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left Accent Bar
            Rectangle()
                .fill(event.type.accentColor)
                .frame(width: 6)
            
            VStack(alignment: .leading, spacing: 12) {
                // Top Row: Icon, User, Time, Amount
                HStack(alignment: .top) {
                    // Icon Box
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(event.type.accentColor.opacity(0.15))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: event.type.iconName)
                            .font(.system(size: 18))
                            .foregroundStyle(event.type.accentColor)
                    }
                    
                    // User & Platform Context
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.type.displayName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                        
                        HStack(spacing: 4) {
                            Text(timeString)
                            Text("•")
                            Text(event.source.rawValue.capitalized.replacingOccurrences(of: "_", with: " "))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 8)
                    
                    Spacer()
                    
                    // Big Value (Amount/Viewers/Bits)
                    if let value = displayValue {
                        Text(value)
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(event.type.accentColor)
                    }
                }
                
                // Main Narrative Text
                Text(narrativeText)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                
                // Message block (if provided, usually donations)
                if let message = event.message, !message.isEmpty {
                    Text("\"\(message)\"")
                        .font(.system(size: 13, weight: .medium).italic())
                        .foregroundStyle(.primary.opacity(0.8))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                        .overlay(
                            Rectangle()
                                .fill(event.type.accentColor.opacity(0.3))
                                .frame(width: 2),
                            alignment: .leading
                        )
                }
            }
            .padding(16)
        }
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .stroke(Color.secondary.opacity(0.05), lineWidth: 1)
        )
    }
    
    // Computed narrative to match UI designs
    private var narrativeText: AttributedString {
        var str = AttributedString(event.username)
        str.font = .system(size: 14, weight: .bold)
        str.foregroundColor = event.type.accentColor
        
        let suffix: AttributedString
        switch event.type {
        case .raid:
            let viewers = event.amount.map { "\(Int($0)) viewers" } ?? "viewers"
            suffix = AttributedString(" is raiding with \(viewers)!")
        case .donation:
            suffix = AttributedString(" tipped the stream.")
        case .subscription:
            suffix = AttributedString(" just subscribed!")
        case .bits:
            let bits = event.amount.map { "\(Int($0))" } ?? "some"
            suffix = AttributedString(" cheered \(bits) bits.")
        case .follow:
            suffix = AttributedString(" became a follower.")
        case .host:
            let viewers = event.amount.map { "\(Int($0)) viewers" } ?? "viewers"
            suffix = AttributedString(" is hosting with \(viewers).")
        }
        
        var full = str
        var suf = suffix
        suf.foregroundColor = .primary
        full.append(suf)
        return full
    }
    
    // Computed right-aligned mega value
    private var displayValue: String? {
        if let formatted = event.formattedAmount { return formatted }
        guard let amt = event.amount else { return nil }
        
        switch event.type {
        case .donation: return String(format: "$%.2f", amt)
        case .raid, .host: return "\(Int(amt))"
        case .bits: return "\(Int(amt))"
        default: return nil
        }
    }
}

#Preview {
    EventLogView()
}
