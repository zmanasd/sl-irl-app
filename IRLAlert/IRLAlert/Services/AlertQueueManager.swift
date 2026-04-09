import Foundation
import Combine
import os.log

/// Central FIFO queue that processes AlertEvents sequentially:
/// 1. Play sound (if URL provided)
/// 2. Speak TTS (if enabled)
/// 3. Wait inter-alert delay
/// 4. Process next event
///
/// Manages overflow by summarizing/skipping when queue exceeds threshold.
@MainActor
final class AlertQueueManager: ObservableObject {
    
    static let shared = AlertQueueManager()
    
    // MARK: - Published State
    
    @Published private(set) var queueCount: Int = 0
    @Published private(set) var isProcessing = false
    @Published private(set) var currentAlert: AlertEvent?
    @Published private(set) var processedCount: Int = 0
    @Published private(set) var skippedCount: Int = 0
    
    // MARK: - Dependencies
    
    private let audioPlayback = AudioPlaybackService.shared
    private let ttsManager = TTSManager.shared
    private let logger = Logger(subsystem: "com.irlalert.app", category: "AlertQueue")
    
    // MARK: - Internal State
    
    private var queue: [AlertEvent] = []
    private var isCurrentlyProcessing = false
    
    /// Callback fired for each processed event (used by EventLog to record history)
    var onAlertProcessed: ((AlertEvent) -> Void)?
    
    private init() {}
    
    // MARK: - Public API
    
    /// Enqueue a new alert event for processing.
    func enqueue(_ event: AlertEvent) {
        let settings = AppSettings.shared
        
        // Check if this alert type is enabled by the user
        guard settings.enabledAlertTypes.contains(event.type) else {
            logger.info("Alert type \(event.type.rawValue) is disabled, skipping")
            skippedCount += 1
            return
        }
        
        // Check overflow threshold
        if queue.count >= settings.queueOverflowThreshold {
            logger.warning("Queue overflow (\(self.queue.count) >= \(settings.queueOverflowThreshold)), skipping: \(event.type.rawValue) from \(event.username)")
            skippedCount += 1
            return
        }
        
        queue.append(event)
        queueCount = queue.count
        PiPManager.shared.updateStatus(queueCount: queueCount)
        
        logger.info("Enqueued: \(event.type.rawValue) from \(event.username) (queue: \(self.queueCount))")
        
        // Start processing if not already running
        if !isCurrentlyProcessing {
            processNext()
        }
    }
    
    /// Enqueue multiple events at once (e.g. batch from reconnection).
    func enqueue(_ events: [AlertEvent]) {
        for event in events {
            enqueue(event)
        }
    }
    
    /// Clear all pending alerts from the queue.
    func clearQueue() {
        let cleared = queue.count
        queue.removeAll()
        queueCount = 0
        PiPManager.shared.updateStatus(queueCount: 0)
        logger.info("Queue cleared: \(cleared) alerts removed")
    }
    
    /// Skip the currently playing alert and move to the next one.
    func skipCurrent() {
        audioPlayback.stopCurrentPlayback()
        ttsManager.stop()
        // processNext will be called after the current processing chain ends
    }
    
    // MARK: - Processing Pipeline
    
    private func processNext() {
        guard !queue.isEmpty else {
            isCurrentlyProcessing = false
            isProcessing = false
            currentAlert = nil
            PiPManager.shared.updateStatus(queueCount: 0)
            logger.info("Queue empty — processing complete. Processed: \(self.processedCount), Skipped: \(self.skippedCount)")
            return
        }
        
        isCurrentlyProcessing = true
        isProcessing = true
        
        let event = queue.removeFirst()
        queueCount = queue.count
        currentAlert = event
        PiPManager.shared.updateStatus(
            lastAlert: "\(event.type.displayName) • \(event.username)",
            queueCount: queueCount
        )
        
        logger.info("Processing: \(event.type.rawValue) from \(event.username)")
        
        // Step 1: Play sound (if URL provided)
        playSound(for: event) {
            // Step 2: Speak TTS (if enabled)
            self.speakTTS(for: event) {
                // Step 3: Inter-alert delay
                self.interAlertDelay {
                    // Notify listeners
                    self.onAlertProcessed?(event)
                    self.processedCount += 1
                    
                    // Step 4: Process next
                    self.processNext()
                }
            }
        }
    }
    
    // MARK: - Pipeline Steps
    
    private func playSound(for event: AlertEvent, completion: @escaping () -> Void) {
        guard let soundURL = event.soundURL else {
            // No sound URL — skip to TTS
            completion()
            return
        }
        
        let settings = AppSettings.shared
        audioPlayback.playSound(
            from: soundURL,
            volume: Float(settings.alertVolume),
            completion: completion
        )
    }
    
    private func speakTTS(for event: AlertEvent, completion: @escaping () -> Void) {
        let settings = AppSettings.shared
        
        guard settings.ttsEnabled else {
            // TTS disabled — skip
            completion()
            return
        }
        
        let text = event.ttsText
        guard !text.isEmpty else {
            completion()
            return
        }
        
        ttsManager.speak(
            text,
            rate: Float(settings.ttsRate),
            volume: Float(settings.ttsVolume),
            completion: completion
        )
    }
    
    private func interAlertDelay(completion: @escaping () -> Void) {
        let settings = AppSettings.shared
        let delay = settings.interAlertDelay
        
        guard delay > 0 else {
            completion()
            return
        }
        
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            completion()
        }
    }
}
