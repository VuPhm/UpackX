import Foundation
import AppKit

public final class FinderIntegrationManager {
    public static let shared = FinderIntegrationManager()
    
    public let servicesDirectory: URL
    
    public static let expectedServiceNames = [
        "Giải nén nhanh với UpackX",
        "Giải nén… với UpackX",
        "Nén nhanh với UpackX",
        "Nén… với UpackX"
    ]
    
    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.servicesDirectory = home.appendingPathComponent("Library/Services", isDirectory: true)
    }
    
    public var isInstalledInApplications: Bool {
        return Bundle.main.bundlePath == "/Applications/UpackX.app" || FileManager.default.fileExists(atPath: "/Applications/UpackX.app")
    }
    
    /// Removes any legacy Automator workflows (.workflow) to prevent duplicate context menus
    public func cleanLegacyWorkflows() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: servicesDirectory.path) else { return }
        let items = (try? fm.contentsOfDirectory(atPath: servicesDirectory.path)) ?? []
        for item in items {
            if item.hasPrefix("UpackX") && item.hasSuffix(".workflow") {
                let fullPath = servicesDirectory.appendingPathComponent(item)
                try? fm.removeItem(at: fullPath)
            }
        }
    }
    
    /// Checks whether all 4 NSServices are declared in the application's Info.plist
    public func isServicesDeclaredInBundle() -> Bool {
        guard let services = Bundle.main.infoDictionary?["NSServices"] as? [[String: Any]] else {
            return false
        }
        let messages = services.compactMap { $0["NSMessage"] as? String }
        return messages.contains("quickExtractService") &&
               messages.contains("extractToService") &&
               messages.contains("quickCompressService") &&
               messages.contains("compressToService")
    }
    
    /// Refreshes macOS Services subsystem dynamically using Apple's official AppKit API
    @discardableResult
    public func refreshServices() -> Bool {
        cleanLegacyWorkflows()
        // Standard AppKit API notifying macOS that dynamic services have updated
        NSUpdateDynamicServices()
        return true
    }
    
    /// Backward-compatibility aliases
    @discardableResult
    public func installServices() throws -> Bool {
        return refreshServices()
    }
    
    @discardableResult
    public func installQuickActions() throws -> Bool {
        return refreshServices()
    }
    
    /// Verifies whether UpackX bundle is configured for Services
    public func isServicesConfigured() -> Bool {
        return isInstalledInApplications && isServicesDeclaredInBundle()
    }
    
    /// Opens macOS System Settings directly to Keyboard Shortcuts -> Services
    public static func openSystemSettingsKeyboardServices() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Checks and refreshes Finder Integration
    public func verifyAndRepair() -> (isValid: Bool, message: String) {
        refreshServices()
        if isInstalledInApplications {
            return (true, "Đã làm mới Finder Services thành công.")
        } else {
            return (false, "Ứng dụng chưa được đặt trong /Applications. Hãy kéo UpackX vào /Applications để tích hợp Finder hoạt động ổn định nhất.")
        }
    }
}
