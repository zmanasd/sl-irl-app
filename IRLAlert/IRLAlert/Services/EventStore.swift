import Foundation
import os.log

/// Persists recent alert events to a local JSON file for the Event Log UI.
///
/// Features:
/// - Thread-safe access via actor isolation
/// - Automatic cap at `maxEvents` (default 500)
/// - Oldest events pruned when cap is exceeded
/// - File-based persistence in the app's Application Support directory
actor EventStore {
    
    // MainActor-safe shared instance accessor
    @MainActor static let shared = EventStore()
    
    private let logger = Logger(subsystem: "com.irlalert.app", category: "EventStore")
    private let maxEvents: Int
    private var events: [AlertEvent] = []
    private let fileURL: URL
    
    init(maxEvents: Int = 500) {
        self.maxEvents = maxEvents
        
        // Store in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("IRL Alert", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("event_store.json")
        
        // Load persisted events on init
        Task { await loadFromDisk() }
    }
    
    // MARK: - Public API
    
    /// Add a new event. Prunes oldest events if over capacity.
    func add(_ event: AlertEvent) {
        events.append(event)
        
        // Prune if over capacity
        if events.count > maxEvents {
            let overage = events.count - maxEvents
            events.removeFirst(overage)
            logger.info("Pruned \(overage) old events (cap: \(self.maxEvents))")
        }
        
        saveToDisk()
    }
    
    /// Add multiple events at once (e.g. from batch restoration).
    func add(_ newEvents: [AlertEvent]) {
        events.append(contentsOf: newEvents)
        
        if events.count > maxEvents {
            let overage = events.count - maxEvents
            events.removeFirst(overage)
        }
        
        saveToDisk()
    }
    
    /// Retrieve all stored events, newest first.
    func allEvents() -> [AlertEvent] {
        events.reversed()
    }
    
    /// Retrieve events filtered by type.
    func events(ofType type: AlertType) -> [AlertEvent] {
        events.filter { $0.type == type }.reversed()
    }
    
    /// Retrieve the most recent N events.
    func recentEvents(limit: Int = 50) -> [AlertEvent] {
        Array(events.suffix(limit).reversed())
    }
    
    /// Total number of stored events.
    var count: Int {
        events.count
    }
    
    /// Clear all stored events.
    func clearAll() {
        events.removeAll()
        saveToDisk()
        logger.info("Event store cleared")
    }
    
    // MARK: - Persistence
    
    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(events)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save events: \(error.localizedDescription)")
        }
    }
    
    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.info("No existing event store found, starting fresh")
            return
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            events = try JSONDecoder().decode([AlertEvent].self, from: data)
            logger.info("Loaded \(self.events.count) events from disk")
        } catch {
            logger.error("Failed to load events: \(error.localizedDescription)")
            events = []
        }
    }
}
