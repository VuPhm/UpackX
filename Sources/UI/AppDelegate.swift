import AppKit

/// Explicit destination semantics per extraction task to guarantee zero state leakage between operations.
public enum ExtractionDestinationMode: Equatable {
    /// Quick Extract: Always extract directly beside the archive (`archiveURL.deletingLastPathComponent()`), never creating an enclosing folder.
    case quickBesideArchive
    /// Extract To: Extract into an explicit destination directory with an explicit enclosing folder preference.
    case customDirectory(URL, createEnclosingFolder: Bool)
}

public struct ExtractionQueueJob {
    public let task: ExtractionTaskItem
    public let destinationMode: ExtractionDestinationMode
    public let conflictStrategy: ConflictStrategy?
    
    public init(task: ExtractionTaskItem,
                destinationMode: ExtractionDestinationMode,
                conflictStrategy: ConflictStrategy? = nil) {
        self.task = task
        self.destinationMode = destinationMode
        self.conflictStrategy = conflictStrategy
    }
}

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var extractToController: ExtractToWindowController?
    private var compressToController: CompressToWindowController?
    private var activeProgressWC: ProgressWindowController?
    private var updateWindowController: UpdateWindowController?
    
    private let initialWorkingDirectory: URL
    private var isCommandLineInvocation: Bool = false
    private var isServiceInvocation: Bool = false
    private var isRightClickInvocation: Bool = false
    private var isHeadless: Bool = false
    private var isInteractiveDialogSession: Bool = false
    public var suppressAutoTerminationForTesting: Bool = false
    public var isHeadlessMode: Bool {
        get { isHeadless }
        set { isHeadless = newValue }
    }
    
    // Sequential Queue State (Extraction & Compression)
    private var taskQueue: [ExtractionQueueJob] = []
    private var currentTaskIndex: Int = 0
    private var isProcessingExtractionQueue: Bool = false
    private var activeCompressionCount: Int = 0
    private var completedCount: Int = 0
    private var failedCount: Int = 0
    private var isCancelled: Bool = false
    private var lastDestinationURL: URL? = nil
    
    public override init() {
        self.initialWorkingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        super.init()
        let nonSystemArgs = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }
        if !nonSystemArgs.isEmpty {
            self.isCommandLineInvocation = true
        }
    }
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.servicesProvider = self
        setupMainMenu()
        
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
        
        // Periodic non-intrusive background update check
        UpdateManager.shared.checkInBackgroundIfNeeded()
        
        // Give services and openFiles a moment to dispatch on startup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            if !self.isCommandLineInvocation &&
                !self.isServiceInvocation &&
                !self.isRightClickInvocation &&
                !self.isProcessingExtractionQueue &&
                self.activeCompressionCount == 0 &&
                self.taskQueue.isEmpty &&
                self.extractToController == nil &&
                self.compressToController == nil &&
                self.activeProgressWC == nil {
                self.showMainWindow()
            }
        }
    }
    
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if isProcessingExtractionQueue ||
            !taskQueue.isEmpty ||
            activeCompressionCount > 0 ||
            activeProgressWC != nil ||
            extractToController != nil ||
            compressToController != nil ||
            updateWindowController != nil {
            return false
        }
        return true
    }
    
    private func showMainWindow() {
        if mainWindowController == nil {
            let mwc = MainWindowController()
            mwc.onFilesSelected = { [weak self] urls, isQuick in
                let tasks = MultipartDetector.groupArchives(urls)
                if isQuick {
                    self?.startQuickExtraction(tasks: tasks, explicitConflictStrategy: nil)
                } else {
                    self?.showExtractToDialogForTasks(tasks)
                }
            }
            mwc.onFileSelected = { [weak self] url, isQuick in
                let tasks = MultipartDetector.groupArchives([url])
                if isQuick {
                    self?.startQuickExtraction(tasks: tasks, explicitConflictStrategy: nil)
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
        
        if args.contains("--check-update") {
            print("Đang kiểm tra bản cập nhật UpackX (Hiện tại: v\(UpdateManager.shared.currentVersionString))...")
            UpdateManager.shared.checkForUpdates { result in
                switch result {
                case .upToDate(let cur):
                    print("UpackX v\(cur) là phiên bản mới nhất.")
                    exit(0)
                case .updateAvailable(let info):
                    print("Đã có phiên bản mới: v\(info.version) (\(info.title))")
                    if let d = info.downloadURL {
                        print("Tải về: \(d.absoluteString)")
                    }
                    print("Trang phát hành: \(info.htmlURL.absoluteString)")
                    exit(0)
                case .error(let err):
                    fputs("Lỗi kiểm tra cập nhật: \(err)\n", stderr)
                    exit(1)
                }
            }
            CFRunLoopRun()
            return
        }
        
        var isCompression = false
        var isQuick = true
        var explicitQuickFlag = false
        var createEnclosingFolder = false
        var conflictStrategy: ConflictStrategy? = nil
        var compressionLevel: CompressionLevel = .normal
        var rawCustomOutput: String? = nil
        var filePaths: [String] = []
        
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "--compress" || arg == "-c" {
                isCompression = true
            } else if arg == "--quick" {
                isQuick = true
                explicitQuickFlag = true
            } else if arg == "--extract-to" {
                isQuick = false
                isCompression = false
            } else if arg == "--compress-to" {
                isQuick = false
                isCompression = true
            } else if arg == "--enclosing-folder" {
                createEnclosingFolder = true
            } else if arg == "--no-enclosing-folder" {
                createEnclosingFolder = false
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
                rawCustomOutput = args[i]
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
        
        var urls: [URL] = []
        for rawPath in filePaths {
            do {
                let resolved = try PathSecurity.resolveInputFileURL(rawPath, baseDirectory: initialWorkingDirectory)
                urls.append(resolved)
            } catch {
                fputs("UpackX Error: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        
        var customOutputURL: URL? = nil
        if let rawOut = rawCustomOutput {
            do {
                if isCompression {
                    customOutputURL = try PathSecurity.resolveInputFileURL(rawOut, baseDirectory: initialWorkingDirectory)
                } else {
                    customOutputURL = try PathSecurity.resolveDestinationDirectoryURL(rawOut, baseDirectory: initialWorkingDirectory)
                }
            } catch {
                fputs("UpackX Output Path Error: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        
        if isCompression {
            if isQuick || isHeadless || customOutputURL != nil {
                startQuickCompression(sources: urls, explicitDestination: customOutputURL, level: compressionLevel, conflictStrategy: conflictStrategy)
            } else {
                showCompressToDialog(sources: urls)
            }
        } else {
            let tasks = MultipartDetector.groupArchives(urls)
            if let customDest = customOutputURL {
                // Explicit destination directory provided via -o / --output
                startSequentialExtraction(
                    tasks: tasks,
                    explicitConflictStrategy: conflictStrategy,
                    customDestination: customDest,
                    createEnclosingFolder: createEnclosingFolder
                )
            } else if isQuick || (explicitQuickFlag && customOutputURL == nil) {
                // Quick Extract: strictly beside each archive, no enclosing folder
                startQuickExtraction(tasks: tasks, explicitConflictStrategy: conflictStrategy)
            } else if isHeadless {
                // Headless --extract-to without -o defaults to each archive's parent directory
                startSequentialExtraction(
                    tasks: tasks,
                    explicitConflictStrategy: conflictStrategy,
                    customDestination: nil,
                    createEnclosingFolder: createEnclosingFolder
                )
            } else {
                showExtractToDialogForTasks(tasks)
            }
        }
    }
    
    // MARK: - Open Files (Finder Double-click or Open With)
    
    public func application(_ application: NSApplication, openFiles filenames: [String]) {
        guard !isCommandLineInvocation else { return }
        self.isRightClickInvocation = true
        let urls = filenames.map { PathSecurity.normalizeFileURL(URL(fileURLWithPath: $0)) }
        
        // If all items are recognized archives, extract. Otherwise, compress.
        let allArchives = urls.allSatisfy { ArchiveFormat.detect(from: $0) != .unknown || MultipartDetector.detectMultipartType(from: $0) != .none }
        if allArchives {
            let tasks = MultipartDetector.groupArchives(urls)
            startQuickExtraction(tasks: tasks, explicitConflictStrategy: nil)
        } else {
            startQuickCompression(sources: urls)
        }
    }
    
    // MARK: - Cocoa NSServices Endpoints
    
    @objc public func quickExtractService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        isServiceInvocation = true
        isRightClickInvocation = true
        let urls = extractURLs(from: pboard)
        guard !urls.isEmpty else {
            error.pointee = "Không tìm thấy file hợp lệ trong pasteboard." as NSString
            checkTerminationIfNeeded()
            return
        }
        let tasks = MultipartDetector.groupArchives(urls)
        startQuickExtraction(tasks: tasks, explicitConflictStrategy: nil)
    }
    
    @objc public func extractToService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        isServiceInvocation = true
        isRightClickInvocation = true
        let urls = extractURLs(from: pboard)
        guard !urls.isEmpty else {
            error.pointee = "Không tìm thấy file hợp lệ trong pasteboard." as NSString
            checkTerminationIfNeeded()
            return
        }
        let tasks = MultipartDetector.groupArchives(urls)
        showExtractToDialogForTasks(tasks)
    }
    
    @objc public func quickCompressService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        isServiceInvocation = true
        isRightClickInvocation = true
        let urls = extractURLs(from: pboard)
        guard !urls.isEmpty else {
            error.pointee = "Không tìm thấy file hoặc thư mục hợp lệ trong pasteboard." as NSString
            checkTerminationIfNeeded()
            return
        }
        startQuickCompression(sources: urls)
    }
    
    @objc public func compressToService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        isServiceInvocation = true
        isRightClickInvocation = true
        let urls = extractURLs(from: pboard)
        guard !urls.isEmpty else {
            error.pointee = "Không tìm thấy file hoặc thư mục hợp lệ trong pasteboard." as NSString
            checkTerminationIfNeeded()
            return
        }
        showCompressToDialog(sources: urls)
    }
    
    private func extractURLs(from pboard: NSPasteboard) -> [URL] {
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: [
            NSPasteboard.ReadingOptionKey.urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty {
            return urls.map { PathSecurity.normalizeFileURL($0) }
        }
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            return urls.map { PathSecurity.normalizeFileURL($0) }
        }
        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if let files = pboard.propertyList(forType: filenamesType) as? [String], !files.isEmpty {
            return files.map { PathSecurity.normalizeFileURL(URL(fileURLWithPath: $0)) }
        }
        if let items = pboard.pasteboardItems {
            var results: [URL] = []
            for item in items {
                if let string = item.string(forType: .fileURL), let url = URL(string: string) {
                    results.append(PathSecurity.normalizeFileURL(url))
                } else if let string = item.string(forType: filenamesType) {
                    results.append(PathSecurity.normalizeFileURL(URL(fileURLWithPath: string)))
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
        sources rawSources: [URL],
        explicitDestination: URL? = nil,
        level: CompressionLevel = .normal,
        conflictStrategy: ConflictStrategy? = nil
    ) {
        let sources = rawSources.map { PathSecurity.normalizeFileURL($0) }
        guard !sources.isEmpty else {
            checkTerminationIfNeeded()
            return
        }
        
        let parentDir = PathSecurity.defaultCompressionDirectory(for: sources)
        let defaultArchiveName = PathSecurity.defaultArchiveFileName(for: sources)
        
        let targetDest: URL
        if let explicit = explicitDestination {
            let normExplicit = PathSecurity.normalizeFileURL(explicit)
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: normExplicit.path, isDirectory: &isDir)
            if (exists && isDir.boolValue && normExplicit.pathExtension.lowercased() != "zip") || explicit.hasDirectoryPath {
                targetDest = PathSecurity.normalizeDirectoryURL(normExplicit).appendingPathComponent(defaultArchiveName, isDirectory: false)
            } else {
                targetDest = normExplicit
            }
        } else {
            targetDest = parentDir.appendingPathComponent(defaultArchiveName, isDirectory: false)
        }
        
        let strategy = conflictStrategy ?? .rename
        
        let nonInteractiveCLI = isHeadless || (isCommandLineInvocation && !isInteractiveDialogSession)
        let options = CompressionOptions(
            destinationURL: targetDest,
            compressionLevel: level,
            conflictStrategy: strategy,
            conflictResolver: nonInteractiveCLI ? nil : { ConflictDialog.prompt(for: $0) }
        )
        
        executeCompression(sources: sources, options: options)
    }
    
    public func showCompressToDialog(sources rawSources: [URL]) {
        let sources = rawSources.map { PathSecurity.normalizeFileURL($0) }
        guard !sources.isEmpty else {
            checkTerminationIfNeeded()
            return
        }
        isInteractiveDialogSession = true
        
        let dialog = CompressToWindowController(sources: sources)
        self.compressToController = dialog
        
        dialog.onConfirm = { [weak self] destinationURL, level in
            guard let self = self else { return }
            self.compressToController = nil
            let options = CompressionOptions(
                destinationURL: PathSecurity.normalizeFileURL(destinationURL),
                compressionLevel: level,
                conflictStrategy: .ask,
                conflictResolver: { ConflictDialog.prompt(for: $0) }
            )
            self.executeCompression(sources: sources, options: options)
        }
        
        dialog.onCancel = { [weak self] in
            self?.compressToController = nil
            self?.checkTerminationIfNeeded()
        }
        
        dialog.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func executeCompression(sources: [URL], options: CompressionOptions) {
        activeCompressionCount += 1
        
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
                        self?.activeCompressionCount = max(0, (self?.activeCompressionCount ?? 1) - 1)
                        
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
    
    /// Starts Quick Extract for one or more archive tasks.
    /// Strictly independent: each archive extracts directly beside itself with `createEnclosingFolder = false`,
    /// never inheriting any custom destination or enclosing folder state from prior operations.
    public func startQuickExtraction(
        tasks: [ExtractionTaskItem],
        explicitConflictStrategy: ConflictStrategy? = nil
    ) {
        let jobs = tasks.map { task in
            ExtractionQueueJob(
                task: task,
                destinationMode: .quickBesideArchive,
                conflictStrategy: explicitConflictStrategy
            )
        }
        enqueueExtractionJobs(jobs)
    }
    
    /// Starts extraction for a batch of tasks with explicit destination and enclosing folder options.
    public func startSequentialExtraction(
        tasks: [ExtractionTaskItem],
        explicitConflictStrategy: ConflictStrategy?,
        customDestination: URL? = nil,
        createEnclosingFolder: Bool = false
    ) {
        let jobs = tasks.map { task -> ExtractionQueueJob in
            let mode: ExtractionDestinationMode
            if let customDest = customDestination {
                mode = .customDirectory(PathSecurity.normalizeDirectoryURL(customDest), createEnclosingFolder: createEnclosingFolder)
            } else if createEnclosingFolder {
                let archiveDir = PathSecurity.defaultExtractionDirectory(for: task.archiveURL)
                mode = .customDirectory(archiveDir, createEnclosingFolder: true)
            } else {
                mode = .quickBesideArchive
            }
            return ExtractionQueueJob(
                task: task,
                destinationMode: mode,
                conflictStrategy: explicitConflictStrategy
            )
        }
        enqueueExtractionJobs(jobs)
    }
    
    public func enqueueExtractionJobs(_ jobs: [ExtractionQueueJob]) {
        guard !jobs.isEmpty else {
            checkTerminationIfNeeded()
            return
        }
        
        if isProcessingExtractionQueue {
            // Append independent jobs to active queue without altering any existing job's destination mode
            self.taskQueue.append(contentsOf: jobs)
            return
        }
        
        self.taskQueue = jobs
        self.currentTaskIndex = 0
        self.completedCount = 0
        self.failedCount = 0
        self.isCancelled = false
        self.lastDestinationURL = nil
        self.isProcessingExtractionQueue = true
        
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
        
        let job = taskQueue[currentTaskIndex]
        let task = job.task
        let archiveURL = PathSecurity.normalizeFileURL(task.archiveURL)
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
        
        // 3. Configure extraction options strictly from the job's own destinationMode
        let destDir: URL
        let createEnclosing: Bool
        switch job.destinationMode {
        case .quickBesideArchive:
            destDir = PathSecurity.defaultExtractionDirectory(for: archiveURL)
            createEnclosing = false
        case .customDirectory(let customDir, let enclosing):
            destDir = PathSecurity.normalizeDirectoryURL(customDir)
            createEnclosing = enclosing
        }
        
        let nonInteractiveCLI = isHeadless || (isCommandLineInvocation && !isInteractiveDialogSession)
        let strategy = job.conflictStrategy ?? (nonInteractiveCLI ? .skip : .ask)
        
        let options = ExtractionOptions(
            destinationDirectory: destDir,
            createEnclosingFolder: createEnclosing,
            conflictStrategy: strategy,
            conflictResolver: nonInteractiveCLI ? nil : { ConflictDialog.prompt(for: $0) },
            passwordProvider: nonInteractiveCLI ? nil : { PasswordDialog.prompt(for: archiveURL) }
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
        
        isProcessingExtractionQueue = false
        taskQueue.removeAll()
        currentTaskIndex = 0
        lastDestinationURL = nil
        checkTerminationIfNeeded()
    }
    
    public func showExtractToDialogForTasks(_ tasks: [ExtractionTaskItem]) {
        guard let firstTask = tasks.first else {
            checkTerminationIfNeeded()
            return
        }
        isInteractiveDialogSession = true
        
        let dialog = ExtractToWindowController(archiveURL: firstTask.archiveURL, totalArchives: tasks.count)
        self.extractToController = dialog
        
        dialog.onConfirm = { [weak self] options in
            guard let self = self else { return }
            self.extractToController = nil
            self.startSequentialExtraction(
                tasks: tasks,
                explicitConflictStrategy: options.conflictStrategy,
                customDestination: PathSecurity.normalizeDirectoryURL(options.destinationDirectory),
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
        guard !suppressAutoTerminationForTesting else { return }
        if (isCommandLineInvocation || isServiceInvocation || isRightClickInvocation) &&
            !isProcessingExtractionQueue &&
            activeCompressionCount == 0 &&
            activeProgressWC == nil &&
            extractToController == nil &&
            compressToController == nil &&
            taskQueue.isEmpty {
            if isCommandLineInvocation {
                exit(failedCount > 0 ? 1 : (isCancelled ? 130 : 0))
            } else {
                mainWindowController?.close()
                mainWindowController = nil
                NSApp.terminate(nil)
            }
        }
    }
    
    // MARK: - Native Application Menu & Updates
    
    public func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // 1. App Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        
        let appName = "UpackX"
        let aboutItem = NSMenuItem(title: "Giới thiệu \(appName)", action: #selector(showAboutWindow), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        
        let updateItem = NSMenuItem(title: "Kiểm tra cập nhật...", action: #selector(checkForUpdatesClicked), keyEquivalent: "")
        updateItem.target = self
        appMenu.addItem(updateItem)
        
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Ẩn \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = NSMenuItem(title: "Ẩn các ứng dụng khác", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(withTitle: "Hiện tất cả", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Thoát \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        
        // 2. Edit Menu (Crucial for Cut, Copy, Paste, Select All in Text Fields)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Chỉnh sửa")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Hoàn tác", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Làm lại", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cắt", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Sao chép", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Dán", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Chọn tất cả", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        
        // 3. Window Menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Cửa sổ")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Thu nhỏ", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Phóng to", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Đóng cửa sổ", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        
        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }
    
    @objc public func showAboutWindow() {
        let credits = NSMutableAttributedString(string: "UpackX — Trình nén & giải nén Native cho macOS\nBản quyền © 2026 UpackX. All rights reserved.")
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "UpackX",
            .applicationVersion: UpdateManager.shared.currentVersionString,
            .version: "\(UpdateManager.shared.currentVersionString) (Build 7)",
            .credits: credits
        ]
        NSApp.orderFrontStandardAboutPanel(options)
    }
    
    @objc public func checkForUpdatesClicked() {
        UpdateManager.shared.checkForUpdates { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .updateAvailable(let info):
                let uwc = UpdateWindowController(updateInfo: info)
                self.updateWindowController = uwc
                uwc.showWindow(nil)
                NSApp.activate(ignoringOtherApps: true)
                
            case .upToDate(let ver):
                let alert = NSAlert()
                alert.messageText = "Đang ở phiên bản mới nhất"
                alert.informativeText = "UpackX v\(ver) là phiên bản mới nhất hiện có."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
                
            case .error(let msg):
                let alert = NSAlert()
                alert.messageText = "Lỗi kiểm tra cập nhật"
                alert.informativeText = msg
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
}
