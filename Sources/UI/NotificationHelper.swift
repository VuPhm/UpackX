import AppKit
import UserNotifications

public final class NotificationHelper {
    public static let shared = NotificationHelper()
    
    private init() {
        requestAuthorization()
    }
    
    public func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    public func notifySuccess(archiveName: String, destinationURL: URL, extractedCount: Int, elapsedTime: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "Giải nén hoàn tất"
        let timeStr = String(format: "%.1fs", elapsedTime)
        content.body = "Đã giải nén \(extractedCount) file từ \(archiveName) vào \(destinationURL.lastPathComponent) (\(timeStr))."
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    public func notifyFailure(archiveName: String, error: Error) {
        let content = UNMutableNotificationContent()
        content.title = "Giải nén thất bại"
        content.body = "\(archiveName): \(error.localizedDescription)"
        content.sound = .defaultCritical
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
