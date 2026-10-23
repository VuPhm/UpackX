import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var extractToController: ExtractToWindowController?
    private var compressToController: CompressToWindowController?
    private var activeProgressWC: ProgressWindowController?
    
    private var isCommandLineInvocation: Bool = false
    private var isServiceInvocation: Bool = false
    private var isHeadless: Bool = false
    
    // Sequential Queue State (Extraction)
    private var taskQueue: [ExtractionTaskItem] = []
    private var currentTaskIndex: Int = 0
    private var queueConflictStrategy: ConflictStrategy? = nil
    private var queueCustomDestination: URL? = nil
    private var queueCreateEnclosing: Bool = false
    private var completedCount: Int = 0
    private var failedCount: Int = 0
    private var isCancelled: Bool = false
    private var lastDestinationURL: URL? = nil
    
    public override init() {
        super.init()
        let nonSystemArgs = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }
        if !nonSystemArgs.isEmpty {
            self.isCommandLineInvocation = true
        }
    }
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.servicesProvider = self
        
        let nonSystemArgs = Array(CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") })
        if !nonSystemArgs.isEmpty {
            handleCommandLineArguments(nonSystemArgs)
            return
        }
        
        // Automatically ensure Finder services are active if installed in /Applications
        if Bundle.main.bundlePath == "/Applications/UpackX.app" {
            if !FinderIntegrationManager.shared.isServicesConfigured() {
                _ = try? FinderIntegrationManager.shared.installServices()
            }
        }
        
        // Give services and openFiles a moment to dispatch on startup
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if !self.isCommandLineInvocation && !self.isServiceInvocation && self.taskQueue.isEmpty && self.extractToController == nil && self.compressToController == nil {
                self.showMainWindow()
            }
        }
    }
    
    private func showMainWindow() {
        if mainWindowController == nil {
            let mwc = MainWindowController()
            mwc.onFileSelected = { [weak self] url, isQuick in
                let tasks = MultipartDetector.groupArchives([url])
                if isQuick {
                    self?.startSequentialExtraction(tasks: tasks, explicitConflictStrategy: nil)
                } else {
                    self?.showExtractToDialogForTasks(tasks)
                }
            }
            mwc.onCompressSelected = { [weak self] urls, isQuick in
                if isQuick {
                    self?.startQuickCompression(sources: urls)
                } else {
                    self?.showCompressToDialog(sources: urls)
                }
            }
            mainWindowController = mwc
        }
        mainWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Command Line Routing
    
    private func handleCommandLineArguments(_ args: [String]) {
        if args.contains("--install-services") {
            do {
                try FinderIntegrationManager.shared.installQuickActions()
                print("Finder Quick Actions installed successfully.")
                exit(0)
            } catch {
                fputs("Error installing services: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        
        var isCompression = false
        var isQuick = true
        var conflictStrategy: ConflictStrategy? = nil
        var compressionLevel: CompressionLevel = .normal
        var customOutput: URL? = nil
        var filePaths: [String] = []
        
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "--compress" || arg == "-c" {
                isCompression = true
            } else if arg == "--quick" {
                isQuick = true
            } else if arg == "--extract-to" {
                isQuick = false
                isCompression = false
            } else if arg == "--compress-to" {
                isQuick = false
                isCompression = true
            } else if arg == "--level" && i + 1 < args.count {
                i += 1
                let lvlStr = args[i].lowercased()
                if lvlStr == "fast" || lvlStr == "1" {
                    compressionLevel = .fast
                } else if lvlStr == "max" || lvlStr == "maximum" || lvlStr == "9" {
                    compressionLevel = .maximum
                } else {
                    compressionLevel = .normal
                }
            } else if (arg == "-o" || arg == "--output") && i + 1 < args.count {
                i += 1
                customOutput = URL(fileURLWithPath: args[i])
            } else if arg == "--overwrite" {
                conflictStrategy = .overwrite
            } else if arg == "--skip" {
                conflictStrategy = .skip
            } else if arg == "--rename" {
                conflictStrategy = .rename
            } else if arg == "--test-fault-disk-full" {
                ZipCompressorFaults.simulateDiskFull = true
            } else if arg == "--test-fault-data-write" {
                ZipCompressorFaults.failDataWrite = true
            } else if arg == "--test-fault-close" {
                ZipCompressorFaults.failClose = true
            } else if arg == "--test-fault-header" {
                ZipCompressorFaults.failHeaderWrite = true
            } else if arg == "--test-fault-commit" {
                ZipCompressorFaults.simulateCommitFailure = true
            } else if arg == "--headless" {
                isHeadless = true
            } else if !arg.hasPrefix("-") {
                filePaths.append(arg)
            }
            i += 1
        }
        
        if filePaths.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.showMainWindow()
            }
            return
        }
        
        isCommandLineInvocation = true
        let urls = filePaths.map { URL(fileURLWithPath: $0) }
        
        if isCompression {
            if isQuick || isHeadless {
                startQuickCompression(sources: urls, explicitDestination: customOutput, level: compressionLevel, conflictStrategy: conflictStrategy)
            } else {
                showCompressToDialog(sources: urls)
            }
        } else {
            let tasks = MultipartDetector.groupArchives(urls)
            if isQuick {
                startSequentialExtraction(tasks: tasks, explicitConflictStrategy: conflictStrategy, customDestination: customOutput)
            } else {
                showExtractToDialogForTasks(tasks)
            }
        }
    }
    
    // MARK: - Open Files (Finder Double-click or Open With)
    
    public func application(_ application: NSApplication, openFiles filenames: [String]) {
        guard !isCommandLineInvocation else { return }
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        
        // If all items are recognized archives, extract. Otherwise, compress.
        let allArchives = urls.allSatisfy { ArchiveFormat.detect(from: $0) != .unknown }
        if allArchives {
            let tasks = MultipartDetector.groupArchives(urls)
            startSequentialExtraction(tasks: tasks, explicitConflictStrategy: nil)
        } else {
            startQuickCompression(sources: urls)
        }
    }
    
    // MARK: - Cocoa NSServices Endpoints
    
    @objc public func quickExtractService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        isServiceInvocation = true
        let urls = extractURLs(from: pboard)
        guard !urls.isEmpty else {
            error.pointee = "Không tìm thấy file hợp lệ trong pasteboard." as NSString
            return
        }
        let tasks = MultipartDetector.groupArchives(urls)
        startSequentialExtraction(tasks: tasks, explicitConflictStrategy: nil)
    }
    
    @objc public func extractToService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        isServiceInvocation = true
        let urls = extractURLs(from: pboard)
        guard !urls.isEmpty else {
            error.pointee = "Không tìm thấy file hợp lệ trong pasteboard." as NSString
            return
        }
        let tasks = MultipartDetector.groupArchives(urls)
        showExtractToDialogForTasks(tasks)
    }
    
    @objc public func quickCompressService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        isServiceInvocation = true
        let urls = extractURLs(from: pboard)
        guard !urls.isEmpty else {
            error.pointee = "Không tìm thấy file hoặc thư mục hợp lệ trong pasteboard." as NSString
            return
        }
        startQuickCompression(sources: urls)
    }
    
    @objc public func compressToService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        isServiceInvocation = true
        let urls = extractURLs(from: pboard)
        guard !urls.isEmpty else {
            error.pointee = "Không tìm thấy file hoặc thư mục hợp lệ trong pasteboard." as NSString
            return
        }
        showCompressToDialog(sources: urls)
    }
    
    private func extractURLs(from pboard: NSPasteboard) -> [URL] {
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: [
            NSPasteboard.ReadingOptionKey.urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty {
            return urls
        }
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            return urls
        }
        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if let files = pboard.propertyList(forType: filenamesType) as? [String] {
            return files.map { URL(fileURLWithPath: $0) }
        }
        if let items = pboard.pasteboardItems {
            var results: [URL] = []
            for item in items {
                if let string = item.string(forType: .fileURL), let url = URL(string: string) {
                    results.append(url)
                } else if let string = item.string(forType: filenamesType) {
                    results.append(URL(fileURLWithPath: string))
                }
            }
            if !results.isEmpty {
                return results
            }
        }
        return []
    }
    
    // MARK: - Compression Workflows
    
    public func startQuickCompression(
        sources: [URL],
        explicitDestination: URL? = nil,
        level: CompressionLevel = .normal,
        conflictStrategy: ConflictStrategy? = nil
    ) {
        guard !sources.isEmpty else {
            checkTerminationIfNeeded()
            return
        }
        
        let firstSource = sources[0]
        let parentDir = firstSource.deletingLastPathComponent()
        let defaultArchiveName: String
        if sources.count == 1 {
            let base = firstSource.deletingPathExtension().lastPathComponent
            defaultArchiveName = base.isEmpty ? "Archive.zip" : "\(base).zip"
        } else {
            defaultArchiveName = "Archive.zip"
        }
        
        let targetDest = explicitDestination ?? parentDir.appendingPathComponent(defaultArchiveName)
        let strategy = conflictStrategy ?? (isHeadless ? .rename : .rename)
        
        let options = CompressionOptions(
            destinationURL: targetDest,
            compressionLevel: level,
            conflictStrategy: strategy,
            conflictResolver: isHeadless ? nil : { ConflictDialog.prompt(for: $0) }
        )
        
        executeCompression(sources: sources, options: options)
    }
    
    public func showCompressToDialog(sources: [URL]) {
        guard !sources.isEmpty else {
            checkTerminationIfNeeded()
            return
        }
        
        let dialog = CompressToWindowController(sources: sources)
        self.compressToController = dialog
        
        dialog.onConfirm = { [weak self] destinationURL, level in
            self?.compressToController = nil
            let options = CompressionOptions(
                destinationURL: destinationURL,
                compressionLevel: level,
                conflictStrategy: .ask,
                conflictResolver: { ConflictDialog.prompt(for: $0) }
            )
            self?.executeCompression(sources: sources, options: options)
        }
        
        dialog.onCancel = { [weak self] in
            self?.compressToController = nil
            self?.checkTerminationIfNeeded()
        }
        
        dialog.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func executeCompression(sources: [URL], options: CompressionOptions) {
        let displayName: String
        if sources.count == 1 {
            displayName = sources[0].lastPathComponent
        } else {
            displayName = "Nén \(sources.count) mục"
        }
        
        let progressWC: ProgressWindowController?
        if isHeadless {
            progressWC = nil
        } else {
            progressWC = ProgressWindowController(archiveName: displayName, isCompressing: true)
            self.activeProgressWC = progressWC
            progressWC?.showWindow(nil)
        }
        
        var cancelled = false
        progressWC?.onCancel = {
            cancelled = true
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak progressWC] in
            ZipCompressor.shared.compress(
                sources: sources,
                options: options,
                progress: { prog in
                    if cancelled || (progressWC?.isCancelled ?? false) {
                        return false
                    }
                    progressWC?.update(compressionProgress: prog)
                    return true
                },
                completion: { result in
                    DispatchQueue.main.async {
                        progressWC?.close()
                        self?.activeProgressWC = nil
                        
                        switch result {
                        case .success(let compResult):
                            NotificationHelper.shared.notifyCompressionSuccess(
                                archiveURL: compResult.destinationURL,
                                totalItems: compResult.totalItemsCompressed,
                                archiveSize: compResult.archiveSize,
                                elapsedTime: compResult.elapsedTime
                            )
                            if self?.isCommandLineInvocation ?? false {
                                print("UpackX: Compressed \(compResult.totalItemsCompressed) items to \(compResult.destinationURL.path)")
                            }
                            self?.checkTerminationIfNeeded()
                            
                        case .failure(let err):
                            if case CompressionError.cancelled = err {
                                if self?.isCommandLineInvocation ?? false {
                                    fputs("UpackX: Compression cancelled.\n", stderr)
                                }
                                self?.isCancelled = true
                            } else {
                                NotificationHelper.shared.notifyCompressionFailure(
                                    archiveName: options.destinationURL.lastPathComponent,
                                    error: err
                                )
                                if self?.isCommandLineInvocation ?? false {
                                    fputs("UpackX Compression Error: \(err.localizedDescription)\n", stderr)
                                } else if !(self?.isHeadless ?? false) {
                                    let alert = NSAlert(error: err)
                                    alert.runModal()
                                }
                                self?.failedCount += 1
                            }
                            self?.checkTerminationIfNeeded()
                        }
                    }
                }
            )
        }
    }
    
    // MARK: - Queue & Extraction Workflows
    
    public func startSequentialExtraction(
        tasks: [ExtractionTaskItem],
        explicitConflictStrategy: ConflictStrategy?,
        customDestination: URL? = nil,
        createEnclosingFolder: Bool = false
    ) {
        guard !tasks.isEmpty else {
            checkTerminationIfNeeded()
            return
        }
        
        self.taskQueue = tasks
        self.currentTaskIndex = 0
        self.queueConflictStrategy = explicitConflictStrategy
        self.queueCustomDestination = customDestination
        self.queueCreateEnclosing = createEnclosingFolder
        self.completedCount = 0
        self.failedCount = 0
        self.isCancelled = false
        
        processNextQueueItem()
    }
    
    private func processNextQueueItem() {
        guard !isCancelled else {
            finishQueue()
            return
        }
        
        guard currentTaskIndex < taskQueue.count else {
            finishQueue()
            return
        }
        
        let task = taskQueue[currentTaskIndex]
        let archiveURL = task.archiveURL
        let total = taskQueue.count
        
        // 1. Multipart integrity validation
        if task.isMultipart, let group = task.multipartGroup, !group.isComplete {
            let missingList = group.missingPartNames.joined(separator: ", ")
            let err = ExtractionError.corruptedArchive("Bộ nén chia phần '\(group.baseName)' không hoàn chỉnh. Thiếu các file volume: \(missingList)")
            NotificationHelper.shared.notifyFailure(archiveName: archiveURL.lastPathComponent, error: err)
            failedCount += 1
            
            if isCommandLineInvocation {
                fputs("UpackX Error (\(archiveURL.lastPathComponent)): \(err.localizedDescription)\n", stderr)
            } else if !isHeadless {
                let alert = NSAlert(error: err)
                alert.runModal()
            }
            
            // Advance to next archive in queue (one failure does not cancel entire batch)
            currentTaskIndex += 1
            DispatchQueue.main.async { [weak self] in
                self?.processNextQueueItem()
            }
            return
        }
        
        // 2. Prepare Progress HUD
        let displayName: String
        if total > 1 {
            displayName = "[\(currentTaskIndex + 1)/\(total)] \(archiveURL.lastPathComponent)"
        } else {
            displayName = archiveURL.lastPathComponent
        }
        
        let progressWC: ProgressWindowController?
        if isHeadless {
            progressWC = nil
        } else {
            progressWC = ProgressWindowController(archiveName: displayName)
            self.activeProgressWC = progressWC
            progressWC?.showWindow(nil)
        }
        
        progressWC?.onCancel = { [weak self] in
            self?.isCancelled = true
        }
        
        // 3. Configure extraction options
        let destDir = queueCustomDestination ?? archiveURL.deletingLastPathComponent()
        let strategy = queueConflictStrategy ?? (isCommandLineInvocation && isHeadless ? .skip : .ask)
        
        let options = ExtractionOptions(
            destinationDirectory: destDir,
            createEnclosingFolder: queueCreateEnclosing,
            conflictStrategy: strategy,
            conflictResolver: isHeadless ? nil : { ConflictDialog.prompt(for: $0) },
            passwordProvider: isHeadless ? nil : { PasswordDialog.prompt(for: archiveURL) }
        )
        
        ExtractionManager.shared.execute(
            archiveURL: archiveURL,
            options: options,
            progress: { [weak self, weak progressWC] progress in
                if self?.isCancelled ?? false || (progressWC?.isCancelled ?? false) {
                    return false
                }
                progressWC?.update(progress: progress)
                return true
            },
            completion: { [weak self, weak progressWC] result in
                guard let self = self else { return }
                progressWC?.close()
                self.activeProgressWC = nil
                
                switch result {
                case .success(let extractionResult):
                    self.completedCount += 1
                    self.lastDestinationURL = extractionResult.destinationURL
                    if total == 1 {
                        NotificationHelper.shared.notifySuccess(
                            archiveName: archiveURL.lastPathComponent,
                            destinationURL: extractionResult.destinationURL,
                            extractedCount: extractionResult.extractedCount,
                            elapsedTime: extractionResult.elapsedTime
                        )
                    }
                    if self.isCommandLineInvocation {
                        print("UpackX: Extracted \(extractionResult.extractedCount) files to \(extractionResult.destinationURL.path)")
                    }
                    
                case .failure(let err):
                    if case ExtractionError.cancelled = err {
                        self.isCancelled = true
                        if self.isCommandLineInvocation {
                            fputs("UpackX: Extraction cancelled.\n", stderr)
                        }
                    } else {
                        self.failedCount += 1
                        NotificationHelper.shared.notifyFailure(archiveName: archiveURL.lastPathComponent, error: err)
                        if self.isCommandLineInvocation {
                            fputs("UpackX Error (\(archiveURL.lastPathComponent)): \(err.localizedDescription)\n", stderr)
                        } else if !self.isHeadless {
                            let alert = NSAlert(error: err)
                            alert.runModal()
                        }
                    }
                }
                
                self.currentTaskIndex += 1
                self.processNextQueueItem()
            }
        )
    }
    
    private func finishQueue() {
        let total = taskQueue.count
        if total > 1 {
            NotificationHelper.shared.notifyBatchSummary(completed: completedCount, failed: failedCount, lastDestinationURL: lastDestinationURL)
        }
        
        taskQueue.removeAll()
        checkTerminationIfNeeded()
    }
    
    public func showExtractToDialogForTasks(_ tasks: [ExtractionTaskItem]) {
        guard let firstTask = tasks.first else {
            checkTerminationIfNeeded()
            return
        }
        
        let dialog = ExtractToWindowController(archiveURL: firstTask.archiveURL, totalArchives: tasks.count)
        self.extractToController = dialog
        
        dialog.onConfirm = { [weak self] options in
            self?.extractToController = nil
            self?.startSequentialExtraction(
                tasks: tasks,
                explicitConflictStrategy: options.conflictStrategy,
                customDestination: options.destinationDirectory,
                createEnclosingFolder: options.createEnclosingFolder
            )
        }
        
        dialog.onCancel = { [weak self] in
            self?.extractToController = nil
            self?.checkTerminationIfNeeded()
        }
        
        dialog.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func checkTerminationIfNeeded() {
        if (isCommandLineInvocation || isServiceInvocation) &&
            activeProgressWC == nil &&
            extractToController == nil &&
            compressToController == nil &&
            taskQueue.isEmpty {
            if isCommandLineInvocation {
                exit(failedCount > 0 ? 1 : (isCancelled ? 130 : 0))
            } else {
                NSApp.terminate(nil)
            }
        }
    }
}
