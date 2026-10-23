import Foundation
import AppKit

public final class FinderIntegrationManager {
    public static let shared = FinderIntegrationManager()
    
    public let servicesDirectory: URL
    
    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.servicesDirectory = home.appendingPathComponent("Library/Services", isDirectory: true)
    }
    
    public var isInstalled: Bool {
        return FileManager.default.fileExists(atPath: "/Applications/UpackX.app")
    }
    
    /// Configures and enables native Cocoa NSServices for UpackX, removing any legacy Automator workflows
    @discardableResult
    public func installServices() throws -> Bool {
        // 1. Clean up all legacy Automator workflows from ~/Library/Services to prevent duplicate menus
        cleanLegacyWorkflows()
        
        let appBundlePath = "/Applications/UpackX.app"
        
        // 2. Refresh LaunchServices registration
        refreshLaunchServices(appBundlePath: appBundlePath)
        
        // 3. Configure and activate services in pbs domain
        enableServicesInPreferences()
        
        return true
    }
    
    /// Backward-compatibility alias
    @discardableResult
    public func installQuickActions() throws -> Bool {
        return try installServices()
    }
    
    /// Removes any legacy UpackX Automator workflows from ~/Library/Services
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
    
    private func refreshLaunchServices(appBundlePath: String) {
        let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        guard FileManager.default.fileExists(atPath: lsregisterPath) else { return }
        
        // Unregister debug build if present to prevent double registration
        let debugApp = FileManager.default.currentDirectoryPath + "/build/UpackX.app"
        if FileManager.default.fileExists(atPath: debugApp) {
            let pUnreg = Process()
            pUnreg.executableURL = URL(fileURLWithPath: lsregisterPath)
            pUnreg.arguments = ["-u", debugApp]
            try? pUnreg.run()
            pUnreg.waitUntilExit()
        }
        
        // Register /Applications/UpackX.app
        let p = Process()
        p.executableURL = URL(fileURLWithPath: lsregisterPath)
        p.arguments = ["-f", appBundlePath]
        try? p.run()
        p.waitUntilExit()
    }
    
    private func enableServicesInPreferences() {
        // Ensure services are explicitly enabled in pbs domain
        let quickKey = "com.upackx.extractor - Giải nén nhanh với UpackX - quickExtractService"
        let toKey = "com.upackx.extractor - Giải nén… với UpackX - extractToService"
        
        let pbsConfig = """
        {
            "enabled_context_menu" = 1;
            "enabled_services_menu" = 1;
            "presentation_modes" = {
                ContextMenu = 1;
                FinderPreview = 1;
                ServicesMenu = 1;
            };
        }
        """
        
        let p1 = Process()
        p1.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p1.arguments = ["write", "pbs", "NSServicesStatus", "-dict-add", quickKey, pbsConfig]
        try? p1.run()
        p1.waitUntilExit()
        
        let p2 = Process()
        p2.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p2.arguments = ["write", "pbs", "NSServicesStatus", "-dict-add", toKey, pbsConfig]
        try? p2.run()
        p2.waitUntilExit()
        
        // Flush and update pbs cache
        let pFlush = Process()
        pFlush.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/pbs")
        pFlush.arguments = ["-flush"]
        try? pFlush.run()
        pFlush.waitUntilExit()
        
        let pUpdate = Process()
        pUpdate.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/pbs")
        pUpdate.arguments = ["-update"]
        try? pUpdate.run()
        pUpdate.waitUntilExit()
    }
    
    /// Verifies if both native Cocoa NSServices are currently configured in pbs
    public func isServicesConfigured() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p.arguments = ["read", "pbs", "NSServicesStatus"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return false }
            return output.contains("quickExtractService") && output.contains("extractToService")
        } catch {
            return false
        }
    }
    
    /// Checks and repairs Finder Integration if broken
    public func verifyAndRepair() -> (isValid: Bool, message: String) {
        do {
            try installServices()
            return (true, "Đã làm mới và kích hoạt Finder NSServices thành công.")
        } catch {
            return (false, "Lỗi kích hoạt Finder Integration: \(error.localizedDescription)")
        }
    }
}
