import AppKit
import UserNotifications

public final class NotificationHelper: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationHelper()
    
    public static let categorySuccessID = "UPACKX_SUCCESS"
    public static let actionShowInFinderID = "SHOW_IN_FINDER"
    
    private override init() {
        super.init()
        setupNotificationCategories()
        requestAuthorization()
        UNUserNotificationCenter.current().delegate = self
    }
    
    public func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    private func setupNotificationCategories() {
        let showInFinderAction = UNNotificationAction(
            identifier: Self.actionShowInFinderID,
            title: "Xem trong Finder",
            options: [.foreground]
        )
        let successCategory = UNNotificationCategory(
            identifier: Self.categorySuccessID,
            actions: [showInFinderAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([successCategory])
    }
    
    public func notifySuccess(archiveName: String, destinationURL: URL, extractedCount: Int, elapsedTime: TimeInterval) {
        let (title, body) = GoogleDriveHelper.completionMessage(
            for: archiveName,
            destinationURL: destinationURL,
            fileCount: extractedCount,
            elapsedTime: elapsedTime
        )
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.categorySuccessID
        content.userInfo = ["destinationPath": destinationURL.path]
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    public func notifyBatchSummary(completed: Int, failed: Int, lastDestinationURL: URL? = nil) {
        let content = UNMutableNotificationContent()
        content.title = "Hoàn tất giải nén hàng loạt"
        if failed == 0 {
            content.body = "Đã giải nén thành công toàn bộ \(completed) archive."
            content.sound = .default
        } else {
            content.body = "Hoàn tất \(completed) archive. Thất bại: \(failed) archive."
            content.sound = .defaultCritical
        }
        
        if let dest = lastDestinationURL {
            content.categoryIdentifier = Self.categorySuccessID
            content.userInfo = ["destinationPath": dest.path]
        }
        
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
    
    public func notifyCompressionSuccess(archiveURL: URL, totalItems: Int, archiveSize: Int64, elapsedTime: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "Nén hoàn tất"
        let mb = Double(archiveSize) / 1_048_576.0
        let sizeText: String
        if mb < 0.1 {
            let kb = Double(archiveSize) / 1024.0
            sizeText = String(format: "%.1f KB", kb)
        } else {
            sizeText = String(format: "%.1f MB", mb)
        }
        content.body = "\(archiveURL.lastPathComponent): Đã nén \(totalItems) mục (\(sizeText)) trong \(String(format: "%.1fs", elapsedTime))."
        content.sound = .default
        content.categoryIdentifier = Self.categorySuccessID
        content.userInfo = ["destinationPath": archiveURL.path]
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    public func notifyCompressionFailure(archiveName: String, error: Error) {
        let content = UNMutableNotificationContent()
        content.title = "Nén thất bại"
        content.body = "\(archiveName): \(error.localizedDescription)"
        content.sound = .defaultCritical
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    
    public static func showInFinder(url: URL) {
        DispatchQueue.main.async {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let destPath = response.notification.request.content.userInfo["destinationPath"] as? String {
            let url = URL(fileURLWithPath: destPath)
            Self.showInFinder(url: url)
        }
        completionHandler()
    }
    
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
