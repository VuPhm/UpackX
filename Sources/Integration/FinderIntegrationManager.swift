import Foundation
import AppKit

public final class FinderIntegrationManager {
    public static let shared = FinderIntegrationManager()
    
    private let servicesDirectory: URL
    
    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.servicesDirectory = home.appendingPathComponent("Library/Services", isDirectory: true)
    }
    
    public var isInstalled: Bool {
        let quick = servicesDirectory.appendingPathComponent("UpackX - Giải nén nhanh.workflow")
        let to = servicesDirectory.appendingPathComponent("UpackX - Giải nén….workflow")
        return FileManager.default.fileExists(atPath: quick.path) && FileManager.default.fileExists(atPath: to.path)
    }
    
    /// Installs the two Quick Actions directly into ~/Library/Services
    @discardableResult
    public func installQuickActions() throws -> Bool {
        let fm = FileManager.default
        try fm.createDirectory(at: servicesDirectory, withIntermediateDirectories: true, attributes: nil)
        
        // Find current executable URL or /Applications/UpackX.app
        let executablePath: String
        if let bundlePath = Bundle.main.executablePath, bundlePath.contains(".app") {
            executablePath = bundlePath
        } else {
            executablePath = "/Applications/UpackX.app/Contents/MacOS/UpackX"
        }
        
        // 1. Quick Extract Workflow
        let quickWorkflowURL = servicesDirectory.appendingPathComponent("UpackX - Giải nén nhanh.workflow")
        try createWorkflow(at: quickWorkflowURL,
                           serviceName: "Giải nén nhanh với UpackX",
                           commandFlag: "--quick",
                           executablePath: executablePath)
        
        // 2. Extract To... Workflow
        let toWorkflowURL = servicesDirectory.appendingPathComponent("UpackX - Giải nén….workflow")
        try createWorkflow(at: toWorkflowURL,
                           serviceName: "Giải nén… với UpackX",
                           commandFlag: "--extract-to",
                           executablePath: executablePath)
        
        // Refresh LaunchServices
        refreshLaunchServices()
        
        return true
    }
    
    private func createWorkflow(at workflowURL: URL, serviceName: String, commandFlag: String, executablePath: String) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: workflowURL.path) {
            try? fm.removeItem(at: workflowURL)
        }
        
        let contentsURL = workflowURL.appendingPathComponent("Contents", isDirectory: true)
        try fm.createDirectory(at: contentsURL, withIntermediateDirectories: true, attributes: nil)
        
        // Info.plist
        let infoPlistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleName</key>
            <string>\(serviceName)</string>
            <key>CFBundleDevelopmentRegion</key>
            <string>vi</string>
            <key>CFBundleIdentifier</key>
            <string>com.upackx.services.\(commandFlag.replacingOccurrences(of: "--", with: ""))</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0</string>
            <key>NSServices</key>
            <array>
                <dict>
                    <key>NSMenuItem</key>
                    <dict>
                        <key>default</key>
                        <string>\(serviceName)</string>
                    </dict>
                    <key>NSMessage</key>
                    <string>runWorkflowAsService</string>
                    <key>NSSendFileTypes</key>
                    <array>
                        <string>public.item</string>
                        <string>public.data</string>
                        <string>public.archive</string>
                        <string>com.pkware.zip-archive</string>
                        <string>org.7-zip.7-zip-archive</string>
                        <string>com.rarlab.rar-archive</string>
                        <string>org.gnu.gnu-tar-archive</string>
                    </array>
                </dict>
            </array>
        </dict>
        </plist>
        """
        try infoPlistContent.write(to: contentsURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        
        // document.wflow
        let script = """
        if [ -x "\(executablePath)" ]; then
            "\(executablePath)" \(commandFlag) "$@"
        elif [ -x "/Applications/UpackX.app/Contents/MacOS/UpackX" ]; then
            "/Applications/UpackX.app/Contents/MacOS/UpackX" \(commandFlag) "$@"
        else
            open -a UpackX --args \(commandFlag) "$@"
        fi
        """
        
        let escapedScript = script.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        
        let wflowContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>AMApplicationBuild</key>
            <string>523</string>
            <key>AMApplicationVersion</key>
            <string>2.10</string>
            <key>AMDocumentVersion</key>
            <string>2</string>
            <key>actions</key>
            <array>
                <dict>
                    <key>action</key>
                    <dict>
                        <key>AMAccepts</key>
                        <dict>
                            <key>Container</key>
                            <string>List</string>
                            <key>Types</key>
                            <array>
                                <string>com.apple.cocoa.path</string>
                            </array>
                        </dict>
                        <key>AMActionVersion</key>
                        <string>2.0.3</string>
                        <key>AMParameterProperties</key>
                        <dict>
                            <key>COMMAND_STRING</key>
                            <dict/>
                            <key>inputMethod</key>
                            <dict/>
                            <key>shell</key>
                            <dict/>
                            <key>source</key>
                            <dict/>
                        </dict>
                        <key>AMProvides</key>
                        <dict>
                            <key>Container</key>
                            <string>List</string>
                            <key>Types</key>
                            <array>
                                <string>com.apple.cocoa.path</string>
                            </array>
                        </dict>
                        <key>ActionBundlePath</key>
                        <string>/System/Library/Automator/Run Shell Script.action</string>
                        <key>ActionName</key>
                        <string>Run Shell Script</string>
                        <key>ActionParameters</key>
                        <dict>
                            <key>COMMAND_STRING</key>
                            <string>\(escapedScript)</string>
                            <key>inputMethod</key>
                            <integer>1</integer>
                            <key>shell</key>
                            <string>/bin/bash</string>
                            <key>source</key>
                            <string></string>
                        </dict>
                        <key>BundleIdentifier</key>
                        <string>com.apple.RunShellScript</string>
                        <key>CFBundleVersion</key>
                        <string>2.0.3</string>
                    </dict>
                </dict>
            </array>
            <key>connectors</key>
            <dict/>
            <key>workflowMetaData</key>
            <dict>
                <key>workflowTypeIdentifier</key>
                <string>com.apple.Automator.servicesMenu</string>
            </dict>
        </dict>
        </plist>
        """
        try wflowContent.write(to: contentsURL.appendingPathComponent("document.wflow"), atomically: true, encoding: .utf8)
    }
    
    public func refreshLaunchServices() {
        let lsregisterPaths = [
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
            "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
        ]
        
        for path in lsregisterPaths {
            if FileManager.default.fileExists(atPath: path) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = ["-f", servicesDirectory.path]
                try? process.run()
                process.waitUntilExit()
                break
            }
        }
    }
}
