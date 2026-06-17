import Foundation
import Combine

/// ViewModel for the Dashboard screen.
/// Provides queue status and session metrics.
@MainActor
final class DashboardVM: ObservableObject {
    
    // MARK: - Published State
    
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
    
    private let queueManager = AlertQueueManager.shared
    
    init() {
        bindQueueManager()
    }
    
    // MARK: - Bindings
    
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
