import Foundation
import UserNotifications
import os.log

/// Monitors service connections and fires a local notification if any service
/// has been disconnected longer than the user-configured timeout.
///
/// Used by `ConnectionManager` to track connect/disconnect events per service.
@MainActor
final class DisconnectMonitor: ObservableObject {
    
    static let shared = DisconnectMonitor()
    
    // MARK: - Published State
    
    /// Services currently in a disconnected/reconnecting state
    @Published private(set) var disconnectedServices: Set<ServiceIdentifier> = []
    
    /// Timestamp of the last disconnect event (for UI display)
    @Published private(set) var lastDisconnectDate: Date?
    
    // MARK: - Private State
    
    private let logger = Logger(subsystem: "com.irlalert.app", category: "DisconnectMonitor")
    private var disconnectTimers: [ServiceIdentifier: Task<Void, Never>] = [:]
    
    private init() {
        requestNotificationPermission()
    }
    
    // MARK: - Public API
    
    /// Called by `ConnectionManager` when a service disconnects or begins reconnecting.
    func serviceDidDisconnect(_ serviceId: ServiceIdentifier) {
        guard !disconnectedServices.contains(serviceId) else { return }
        
        disconnectedServices.insert(serviceId)
        lastDisconnectDate = Date()
        
        logger.warning("Service disconnected: \(serviceId.rawValue)")
        
        // Start a timer to fire a notification after the configured timeout
        startDisconnectTimer(for: serviceId)
    }
    
    /// Called by `ConnectionManager` when a service reconnects successfully.
    func serviceDidConnect(_ serviceId: ServiceIdentifier) {
        disconnectedServices.remove(serviceId)
        
        // Cancel pending notification timer
        disconnectTimers[serviceId]?.cancel()
        disconnectTimers.removeValue(forKey: serviceId)
        
        // Remove any pending notifications for this service
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["disconnect_\(serviceId.rawValue)"]
        )
        
        if disconnectedServices.isEmpty {
            lastDisconnectDate = nil
        }
        
        logger.info("Service reconnected: \(serviceId.rawValue)")
    }
    
    /// Cancel all monitoring (e.g. when user manually disconnects).
    func cancelAll() {
        for (_, timer) in disconnectTimers {
            timer.cancel()
        }
        disconnectTimers.removeAll()
        disconnectedServices.removeAll()
        lastDisconnectDate = nil
    }
    
    // MARK: - Notification Timer
    
    private func startDisconnectTimer(for serviceId: ServiceIdentifier) {
        // Cancel any existing timer for this service
        disconnectTimers[serviceId]?.cancel()
        
        let timeout = AppSettings.shared.disconnectNotificationTimeout
        
        disconnectTimers[serviceId] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            
            // Check if still disconnected
            guard let self, self.disconnectedServices.contains(serviceId) else { return }
            
            self.logger.warning("Disconnect timeout reached for \(serviceId.rawValue) (\(timeout)s)")
            self.fireDisconnectNotification(for: serviceId)
        }
    }
    
    // MARK: - Local Notifications
    
    private func requestNotificationPermission() {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                logger.info("Notification permission \(granted ? "granted" : "denied")")
            } catch {
                logger.error("Notification permission request failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func fireDisconnectNotification(for serviceId: ServiceIdentifier) {
        let content = UNMutableNotificationContent()
        content.title = "Connection Lost"
        content.body = "\(serviceId.displayName) has been disconnected for over \(Int(AppSettings.shared.disconnectNotificationTimeout)) seconds. You may be missing alerts."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        
        let request = UNNotificationRequest(
            identifier: "disconnect_\(serviceId.rawValue)",
            content: content,
            trigger: nil // Fire immediately
        )
        
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                self?.logger.error("Failed to deliver disconnect notification: \(error.localizedDescription)")
            } else {
                self?.logger.info("Disconnect notification sent for \(serviceId.rawValue)")
            }
        }
    }
}
