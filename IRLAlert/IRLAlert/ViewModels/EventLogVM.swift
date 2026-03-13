import Foundation
import Combine

/// ViewModel for the Event Log screen.
/// Provides a filterable, auto-updating list of recent alert events from the EventStore.
@MainActor
final class EventLogVM: ObservableObject {
    
    // MARK: - Published State
    
    /// Currently displayed events (filtered)
    @Published private(set) var events: [AlertEvent] = []
    
    /// Currently selected filter tab
    @Published var selectedFilter: EventFilter = .all {
        didSet { refreshEvents() }
    }
    
    /// Total events in the store
    @Published private(set) var totalCount: Int = 0
    
    /// Whether the queue is currently processing
    @Published private(set) var isProcessing = false
    
    /// Current queue depth
    @Published private(set) var queueCount = 0
    
    // MARK: - Filter Options
    
    enum EventFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case donation = "Donations"
        case subscription = "Subs"
        case bits = "Bits"
        case follow = "Follows"
        case raid = "Raids"
        
        var id: String { rawValue }
        
        var alertType: AlertType? {
            switch self {
            case .all: return nil
            case .donation: return .donation
            case .subscription: return .subscription
            case .bits: return .bits
            case .follow: return .follow
            case .raid: return .raid
            }
        }
    }
    
    // MARK: - Dependencies
    
    private let eventStore = EventStore.shared
    private let queueManager = AlertQueueManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        bindQueueManager()
        startAutoRefresh()
        refreshEvents()
    }
    
    // MARK: - Public API
    
    /// Force refresh events from the store.
    func refreshEvents() {
        Task {
            if let type = selectedFilter.alertType {
                events = await eventStore.events(ofType: type)
            } else {
                events = await eventStore.allEvents()
            }
            totalCount = await eventStore.count
        }
    }
    
    /// Clear all events from the store.
    func clearAll() {
        Task {
            await eventStore.clearAll()
            refreshEvents()
        }
    }
    
    // MARK: - Bindings
    
    private func bindQueueManager() {
        queueManager.$isProcessing
            .assign(to: &$isProcessing)
        
        queueManager.$queueCount
            .assign(to: &$queueCount)
    }
    
    /// Periodically refresh events (every 2s) to pick up new entries.
    private func startAutoRefresh() {
        Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshEvents()
            }
            .store(in: &cancellables)
    }
}
