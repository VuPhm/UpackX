import AppKit
import UserNotifications

public final class NotificationHelper: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationHelper()
    
    public static let categorySuccessID = "UPACKX_SUCCESS"
    public static let actionShowInFinderID = "SHOW_IN_FINDER"
    
    public private(set) var lastNotificationTitle: String?
    public private(set) var lastNotificationBody: String?
    
    private var canUseNotificationCenter: Bool {
        return Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }
    
    private override init() {
        super.init()
        guard canUseNotificationCenter else { return }
        setupNotificationCategories()
        requestAuthorization()
        UNUserNotificationCenter.current().delegate = self
    }
    
    public func requestAuthorization() {
        guard canUseNotificationCenter else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    private func setupNotificationCategories() {
        guard canUseNotificationCenter else { return }
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
        lastNotificationTitle = title
        lastNotificationBody = body
        guard canUseNotificationCenter else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.categorySuccessID
        content.userInfo = ["destinationPath": destinationURL.path]
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    public func notifyExtractionSkipped(archiveName: String, destinationURL: URL, skippedCount: Int) {
        let title = "Đã bỏ qua giải nén"
        let body = "\(archiveName): Đã bỏ qua \(skippedCount) file trùng tên tại \(destinationURL.lastPathComponent) (giữ nguyên dữ liệu hiện có)."
        lastNotificationTitle = title
        lastNotificationBody = body
        guard canUseNotificationCenter else { return }
        
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
        guard canUseNotificationCenter else { return }
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
        guard canUseNotificationCenter else { return }
        let content = UNMutableNotificationContent()
        content.title = "Giải nén thất bại"
        content.body = "\(archiveName): \(error.localizedDescription)"
        content.sound = .defaultCritical
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    public func notifyCompressionSuccess(archiveURL: URL, totalItems: Int, archiveSize: Int64, elapsedTime: TimeInterval) {
        let title = "Nén hoàn tất"
        let mb = Double(archiveSize) / 1_048_576.0
        let sizeText: String
        if mb < 0.1 {
            let kb = Double(archiveSize) / 1024.0
            sizeText = String(format: "%.1f KB", kb)
        } else {
            sizeText = String(format: "%.1f MB", mb)
        }
        let body = "\(archiveURL.lastPathComponent): Đã nén \(totalItems) mục (\(sizeText)) trong \(String(format: "%.1fs", elapsedTime))."
        lastNotificationTitle = title
        lastNotificationBody = body
        guard canUseNotificationCenter else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.categorySuccessID
        content.userInfo = ["destinationPath": archiveURL.path]
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    public func notifyCompressionSkipped(archiveURL: URL) {
        let title = "Đã bỏ qua nén file"
        let body = "\(archiveURL.lastPathComponent): Đã bỏ qua tạo file nén mới vì file đích đã tồn tại (giữ nguyên file hiện có)."
        lastNotificationTitle = title
        lastNotificationBody = body
        guard canUseNotificationCenter else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.categorySuccessID
        content.userInfo = ["destinationPath": archiveURL.path]
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    public func notifyCompressionFailure(archiveName: String, error: Error) {
        guard canUseNotificationCenter else { return }
        let content = UNMutableNotificationContent()
        content.title = "Nén thất bại"
        content.body = "\(archiveName): \(error.localizedDescription)"
        content.sound = .defaultCritical
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    public func notifyUpdateAvailable(version: String, releaseNotes: String) {
        guard canUseNotificationCenter else { return }
        let content = UNMutableNotificationContent()
        content.title = "Đã có bản cập nhật mới (v\(version))"
        content.body = "UpackX v\(version) đã sẵn sàng. Nhấn để xem chi tiết và tải về."
        content.sound = .default
        
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
