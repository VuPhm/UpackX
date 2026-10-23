import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var progressControllers: [URL: ProgressWindowController] = [:]
    private var extractToController: ExtractToWindowController?
    private var isCommandLineInvocation: Bool = false
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.servicesProvider = self
        
        // Parse launch arguments
        let args = CommandLine.arguments
        if args.count > 1 {
            isCommandLineInvocation = true
            handleCommandLineArguments(Array(args.dropFirst()))
            return
        }
        
        // Normal interactive launch: show main drag-and-drop window
        showMainWindow()
    }
    
    private func showMainWindow() {
        if mainWindowController == nil {
            let mwc = MainWindowController()
            mwc.onFileSelected = { [weak self] url, isQuick in
                if isQuick {
                    self?.performQuickExtract(archiveURL: url)
                } else {
                    self?.showExtractToDialog(archiveURL: url)
                }
            }
            mainWindowController = mwc
        }
        mainWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Command Line / Quick Action Routing
    
    private func handleCommandLineArguments(_ args: [String]) {
        if args.contains("--install-services") {
            do {
                try FinderIntegrationManager.shared.installQuickActions()
                print("Finder Quick Actions installed successfully.")
                NSApp.terminate(nil)
            } catch {
                fputs("Error installing services: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }
        
        var isQuick = true
        var conflictStrategy: ConflictStrategy? = nil
        var filePaths: [String] = []
        
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "--quick" {
                isQuick = true
            } else if arg == "--extract-to" {
                isQuick = false
            } else if arg == "--overwrite" {
                conflictStrategy = .overwrite
            } else if arg == "--skip" {
                conflictStrategy = .skip
            } else if arg == "--rename" {
                conflictStrategy = .rename
            } else if !arg.hasPrefix("-") {
                filePaths.append(arg)
            }
            i += 1
        }
        
        if filePaths.isEmpty {
            showMainWindow()
            return
        }
        
        let urls = filePaths.map { URL(fileURLWithPath: $0) }
        
        // Multi-part volume grouping (Stage 2 architectural integration)
        let (primaryURLs, _) = MultipartDetector.groupArchives(urls)
        
        for url in primaryURLs {
            if isQuick {
                performQuickExtract(archiveURL: url, explicitConflictStrategy: conflictStrategy)
            } else {
                showExtractToDialog(archiveURL: url)
            }
        }
    }
    
    // MARK: - Open Files (Finder Double-click or Open With)
    
    public func application(_ application: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        let (primaryURLs, _) = MultipartDetector.groupArchives(urls)
        
        for url in primaryURLs {
            // Default action on double-click/open: Quick Extract
            performQuickExtract(archiveURL: url)
        }
    }
    
    // MARK: - Cocoa NSServices Endpoints
    
    @objc public func quickExtractService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty else {
            error.pointee = "Không tìm thấy file hợp lệ trong pasteboard." as NSString
            return
        }
        let (primaryURLs, _) = MultipartDetector.groupArchives(urls)
        for url in primaryURLs {
            performQuickExtract(archiveURL: url)
        }
    }
    
    @objc public func extractToService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty else {
            error.pointee = "Không tìm thấy file hợp lệ trong pasteboard." as NSString
            return
        }
        let (primaryURLs, _) = MultipartDetector.groupArchives(urls)
        for url in primaryURLs {
            showExtractToDialog(archiveURL: url)
        }
    }
    
    // MARK: - Extraction Workflows
    
    public func performQuickExtract(archiveURL: URL, explicitConflictStrategy: ConflictStrategy? = nil) {
        let progressWC: ProgressWindowController? = isCommandLineInvocation ? nil : ProgressWindowController(archiveName: archiveURL.lastPathComponent)
        if let wc = progressWC {
            progressControllers[archiveURL] = wc
            wc.showWindow(nil)
        }
        
        var cancelled = false
        progressWC?.onCancel = {
            cancelled = true
        }
        
        let parentDir = archiveURL.deletingLastPathComponent()
        let strategy = explicitConflictStrategy ?? (isCommandLineInvocation ? .rename : .ask)
        
        let options = ExtractionOptions(
            destinationDirectory: parentDir,
            createEnclosingFolder: false, // Requirement 2.2.A: No enclosing folder
            conflictStrategy: strategy,
            conflictResolver: isCommandLineInvocation ? nil : { ConflictDialog.prompt(for: $0) }
        )
        
        ExtractionManager.shared.execute(
            archiveURL: archiveURL,
            options: options,
            progress: { [weak progressWC] progress in
                if cancelled || (progressWC?.isCancelled ?? false) {
                    return false
                }
                progressWC?.update(progress: progress)
                return true
            },
            completion: { [weak self, weak progressWC] result in
                guard let self = self else { return }
                progressWC?.close()
                self.progressControllers.removeValue(forKey: archiveURL)
                
                switch result {
                case .success(let extractionResult):
                    NotificationHelper.shared.notifySuccess(
                        archiveName: archiveURL.lastPathComponent,
                        destinationURL: extractionResult.destinationURL,
                        extractedCount: extractionResult.extractedCount,
                        elapsedTime: extractionResult.elapsedTime
                    )
                    if self.isCommandLineInvocation {
                        print("UpackX: Extracted \(extractionResult.extractedCount) files to \(extractionResult.destinationURL.path)")
                        exit(0)
                    }
                case .failure(let err):
                    if case ExtractionError.cancelled = err {
                        if self.isCommandLineInvocation {
                            fputs("UpackX: Extraction cancelled.\n", stderr)
                            exit(130)
                        }
                    } else {
                        NotificationHelper.shared.notifyFailure(archiveName: archiveURL.lastPathComponent, error: err)
                        if self.isCommandLineInvocation {
                            fputs("UpackX Error: \(err.localizedDescription)\n", stderr)
                            exit(1)
                        } else {
                            let alert = NSAlert(error: err)
                            alert.runModal()
                        }
                    }
                }
                
                self.checkTerminationIfNeeded()
            }
        )
    }
    
    public func showExtractToDialog(archiveURL: URL) {
        let dialog = ExtractToWindowController(archiveURL: archiveURL)
        self.extractToController = dialog
        
        dialog.onConfirm = { [weak self] options in
            self?.executeWithOptions(archiveURL: archiveURL, options: options)
        }
        
        dialog.onCancel = { [weak self] in
            self?.checkTerminationIfNeeded()
        }
        
        dialog.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func executeWithOptions(archiveURL: URL, options: ExtractionOptions) {
        let progressWC = ProgressWindowController(archiveName: archiveURL.lastPathComponent)
        progressControllers[archiveURL] = progressWC
        progressWC.showWindow(nil)
        
        var cancelled = false
        progressWC.onCancel = {
            cancelled = true
        }
        
        ExtractionManager.shared.extractTo(
            archiveURL: archiveURL,
            options: options,
            progress: { [weak progressWC] progress in
                if cancelled || (progressWC?.isCancelled ?? false) {
                    return false
                }
                progressWC?.update(progress: progress)
                return true
            },
            completion: { [weak self, weak progressWC] result in
                guard let self = self else { return }
                progressWC?.close()
                self.progressControllers.removeValue(forKey: archiveURL)
                
                switch result {
                case .success(let extractionResult):
                    NotificationHelper.shared.notifySuccess(
                        archiveName: archiveURL.lastPathComponent,
                        destinationURL: extractionResult.destinationURL,
                        extractedCount: extractionResult.extractedCount,
                        elapsedTime: extractionResult.elapsedTime
                    )
                case .failure(let err):
                    if case ExtractionError.cancelled = err {
                        // Cancelled by user
                    } else {
                        NotificationHelper.shared.notifyFailure(archiveName: archiveURL.lastPathComponent, error: err)
                        let alert = NSAlert(error: err)
                        alert.runModal()
                    }
                }
                
                self.checkTerminationIfNeeded()
            }
        )
    }
    
    private func checkTerminationIfNeeded() {
        if isCommandLineInvocation && progressControllers.isEmpty && extractToController == nil {
            // CLI/Quick Action operation complete: terminate cleanly
            NSApp.terminate(nil)
        }
    }
}
