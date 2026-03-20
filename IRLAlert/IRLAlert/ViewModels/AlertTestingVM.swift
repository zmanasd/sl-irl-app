import Foundation
import Combine

/// ViewModel for the Alert Testing screen.
/// Provides mock alert generation and connection readiness checks.
@MainActor
final class AlertTestingVM: ObservableObject {
    
    // MARK: - Published State
    
    /// Whether at least one service is connected (ready to receive real alerts)
    @Published private(set) var isReady = false
    
    /// Whether the queue is currently processing an alert
    @Published private(set) var isProcessing = false
    
    /// Current queue count
    @Published private(set) var queueCount = 0
    
    /// Number of active connections
    @Published private(set) var activeServiceCount = 0
    
    /// Last test alert sent (for confirmation UI)
    @Published private(set) var lastTestAlert: AlertEvent?
    
    // MARK: - Dependencies
    
    private let queueManager = AlertQueueManager.shared
    private let connectionManager = ConnectionManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        bindState()
    }
    
    // MARK: - Public API
    
    /// Send a test alert of the given type into the processing queue.
    func sendTestAlert(type: AlertType) {
        let event: AlertEvent
        switch type {
        case .donation:
            event = .mockDonation(
                username: "TestDonator",
                amount: Double.random(in: 1...100),
                message: "Test donation from IRL Alert!"
            )
        case .follow:
            event = .mockFollow(username: "TestFollower")
        case .subscription:
            event = .mockSubscription(username: "TestSubscriber")
        case .bits:
            event = .mockBits(username: "TestBitsUser", bits: Int.random(in: 100...1000))
        case .host:
            event = AlertEvent(
                type: .host,
                username: "TestHost",
                amount: Double(Int.random(in: 5...200)),
                source: .mock
            )
        case .raid:
            event = .mockRaid(username: "TestRaider", viewers: Int.random(in: 10...500))
        }
        
        lastTestAlert = event
        queueManager.enqueue(event)
    }
    
    /// Send a burst of test alerts to stress-test the queue.
    func sendTestBurst(count: Int = 5) {
        let types = AlertType.allCases
        for i in 0..<count {
            let type = types[i % types.count]
            sendTestAlert(type: type)
        }
    }
    
    /// Skip the currently processing alert.
    func skipCurrent() {
        queueManager.skipCurrent()
    }
    
    /// Clear the entire queue.
    func clearQueue() {
        queueManager.clearQueue()
    }
    
    // MARK: - Bindings
    
    private func bindState() {
        connectionManager.$hasActiveConnection
            .assign(to: &$isReady)
        
        connectionManager.$activeServiceCount
            .assign(to: &$activeServiceCount)
        
        queueManager.$isProcessing
            .assign(to: &$isProcessing)
        
        queueManager.$queueCount
            .assign(to: &$queueCount)
    }
}
