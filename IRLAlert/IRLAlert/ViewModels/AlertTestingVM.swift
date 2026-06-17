import Foundation
import Combine

/// ViewModel for the Alert Testing screen.
/// Provides mock alert generation and connection readiness checks.
@MainActor
final class AlertTestingVM: ObservableObject {
    
    // MARK: - Published State
    
    /// Whether the Twitch/APNs proof path is ready to validate.
    @Published private(set) var isReady = false
    
    /// Whether the queue is currently processing an alert
    @Published private(set) var isProcessing = false
    
    /// Current queue count
    @Published private(set) var queueCount = 0
    
    /// Last test alert sent (for confirmation UI)
    @Published private(set) var lastTestAlert: AlertEvent?
    
    // MARK: - Dependencies
    
    private let queueManager = AlertQueueManager.shared
    private let settings = AppSettings.shared
    private let pushManager = PushNotificationManager.shared
    private let relayClient = RelayClient.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        bindState()
    }
    
    // MARK: - Public API
    
    /// Send a test alert of the given type into the processing queue.
    func sendTestAlert(type: AlertType) {
        let event: AlertEvent
        switch type {
        case .follow:
            event = .mockFollow(username: "TestFollower")
        case .subscription:
            event = .mockSubscription(username: "TestSubscriber")
        case .bits:
            event = .mockBits(username: "TestBitsUser", bits: Int.random(in: 100...1000))
        case .raid:
            event = .mockRaid(username: "TestRaider", viewers: Int.random(in: 10...500))
        case .channelPoints:
            event = .mockChannelPoints(username: "TestRedeemer", reward: "Hydrate")
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
        Publishers.CombineLatest4(
            settings.$pushNotificationsEnabled,
            pushManager.$deviceToken,
            relayClient.$lastRegistrationStatusCode,
            relayClient.$lastUserReadinessOk
        )
        .map { pushEnabled, deviceToken, statusCode, userReady in
            pushEnabled
                && deviceToken != nil
                && statusCode.map { (200..<300).contains($0) } == true
                && userReady
        }
        .assign(to: &$isReady)
        
        queueManager.$isProcessing
            .assign(to: &$isProcessing)
        
        queueManager.$queueCount
            .assign(to: &$queueCount)
    }
}
