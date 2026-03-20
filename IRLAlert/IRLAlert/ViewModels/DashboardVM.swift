import Foundation
import Combine

/// ViewModel for the Dashboard screen.
/// Provides live connection health, queue status, and session metrics.
@MainActor
final class DashboardVM: ObservableObject {
    
    // MARK: - Published State
    
    /// Per-service connection health
    @Published private(set) var serviceStates: [ServiceIdentifier: ConnectionState] = [:]
    
    /// Whether any service is currently connected
    @Published private(set) var hasActiveConnection = false
    
    /// Count of active (connected) services
    @Published private(set) var activeServiceCount = 0
    
    /// Current queue depth
    @Published private(set) var queueCount = 0
    
    /// Whether the queue is actively processing
    @Published private(set) var isProcessing = false
    
    /// Total alerts processed this session
    @Published private(set) var processedCount = 0
    
    /// Total alerts skipped this session
    @Published private(set) var skippedCount = 0
    
    /// Session start time (for uptime display)
    let sessionStartDate = Date()
    
    /// Formatted session uptime string
    var uptimeString: String {
        let interval = Date().timeIntervalSince(sessionStartDate)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        return String(format: "%dm %02ds", minutes, seconds)
    }
    
    // MARK: - Dependencies
    
    private let connectionManager = ConnectionManager.shared
    private let queueManager = AlertQueueManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        bindConnectionManager()
        bindQueueManager()
    }
    
    // MARK: - Bindings
    
    private func bindConnectionManager() {
        connectionManager.$serviceStates
            .assign(to: &$serviceStates)
        
        connectionManager.$hasActiveConnection
            .assign(to: &$hasActiveConnection)
        
        connectionManager.$activeServiceCount
            .assign(to: &$activeServiceCount)
    }
    
    private func bindQueueManager() {
        queueManager.$queueCount
            .assign(to: &$queueCount)
        
        queueManager.$isProcessing
            .assign(to: &$isProcessing)
        
        queueManager.$processedCount
            .assign(to: &$processedCount)
        
        queueManager.$skippedCount
            .assign(to: &$skippedCount)
    }
}
