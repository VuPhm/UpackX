import AppKit
import UniformTypeIdentifiers

public final class ExtractToWindowController: NSWindowController, NSWindowDelegate {
    public var onConfirm: ((ExtractionOptions) -> Void)?
    public var onCancel: (() -> Void)?
    
    private let archiveURL: URL
    private let totalArchives: Int
    private var selectedDestinationURL: URL
    private var isConfirmed = false
    private var isCancelled = false
    
    private let pathTextField = DestinationPathTextField()
    private let pathFieldEditor = DestinationPathFieldEditor()
    private let browseButton = NSButton(title: "Chọn...", target: nil, action: nil)
    private let enclosingFolderCheckbox = NSButton(checkboxWithTitle: "Tạo thư mục bao ngoài", target: nil, action: nil)
    private let conflictPopUp = NSPopUpButton()
    private let infoLabel = NSTextField(labelWithString: "Đang đọc thông tin archive...")
    
    public init(archiveURL: URL, totalArchives: Int = 1) {
        let normalizedArchive = PathSecurity.normalizeFileURL(archiveURL)
        self.archiveURL = normalizedArchive
        self.totalArchives = totalArchives
        self.selectedDestinationURL = PathSecurity.defaultExtractionDirectory(for: normalizedArchive)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 490, height: 265),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "UpackX — Tùy chọn giải nén"
        window.center()
        window.isReleasedWhenClosed = false
        
        super.init(window: window)
        window.delegate = self
        setupUI()
        loadArchiveInfo()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func applyDroppedOrSelectedFolder(_ folderURL: URL) {
        let cleanFolder = PathSecurity.normalizeDirectoryURL(folderURL)
        window?.endEditing(for: nil)
        selectedDestinationURL = cleanFolder
        pathTextField.stringValue = cleanFolder.path
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        // Background Drop Area for Folders
        let bgView = ExtractToBackgroundView(frame: contentView.bounds)
        bgView.autoresizingMask = [.width, .height]
        bgView.onFolderDropped = { [weak self] folderURL in
            self?.applyDroppedOrSelectedFolder(folderURL)
        }
        contentView.addSubview(bgView, positioned: .below, relativeTo: nil)
        
        let iconView = NSImageView(frame: NSRect(x: 20, y: 195, width: 48, height: 48))
        let ext = archiveURL.pathExtension
        let iconType = UTType(filenameExtension: ext) ?? .archive
        iconView.image = NSWorkspace.shared.icon(for: iconType)
        contentView.addSubview(iconView)
        
        let displayName: String
        if totalArchives > 1 {
            displayName = "\(archiveURL.lastPathComponent) (+ \(totalArchives - 1) archive khác)"
        } else {
            displayName = archiveURL.lastPathComponent
        }
        
        let nameLabel = NSTextField(labelWithString: displayName)
        nameLabel.frame = NSRect(x: 80, y: 220, width: 390, height: 20)
        nameLabel.font = NSFont.boldSystemFont(ofSize: 14)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        contentView.addSubview(nameLabel)
        
        infoLabel.frame = NSRect(x: 80, y: 200, width: 390, height: 18)
        infoLabel.font = NSFont.systemFont(ofSize: 11)
        infoLabel.textColor = .secondaryLabelColor
        contentView.addSubview(infoLabel)
        
        // Destination directory
        let destTitle = NSTextField(labelWithString: "Thư mục đích:")
        destTitle.frame = NSRect(x: 20, y: 160, width: 120, height: 18)
        destTitle.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        contentView.addSubview(destTitle)
        
        pathTextField.frame = NSRect(x: 20, y: 133, width: 360, height: 24)
        pathTextField.stringValue = selectedDestinationURL.path
        pathTextField.isEditable = true
        pathTextField.isSelectable = true
        pathTextField.isEnabled = true
        pathTextField.isBezeled = true
        pathTextField.bezelStyle = .roundedBezel
        pathTextField.focusRingType = .default
        pathTextField.font = NSFont.systemFont(ofSize: 12)
        pathTextField.drawsBackground = true
        pathTextField.backgroundColor = .textBackgroundColor
        pathTextField.textColor = .labelColor
        pathTextField.lineBreakMode = .byClipping
        pathTextField.cell?.wraps = false
        pathTextField.cell?.isScrollable = true
        pathTextField.placeholderString = "Nhập, dán hoặc kéo thả thư mục vào đây..."
        pathTextField.target = self
        pathTextField.action = #selector(extractClicked)
        pathTextField.onFolderDropped = { [weak self] folderURL in
            self?.applyDroppedOrSelectedFolder(folderURL)
        }
        pathFieldEditor.onFolderDropped = { [weak self] folderURL in
            self?.applyDroppedOrSelectedFolder(folderURL)
        }
        contentView.addSubview(pathTextField)
        
        browseButton.frame = NSRect(x: 388, y: 129, width: 82, height: 28)
        browseButton.bezelStyle = .rounded
        browseButton.target = self
        browseButton.action = #selector(browseClicked)
        contentView.addSubview(browseButton)
        
        // Enclosing folder checkbox (Default: OFF)
        let folderName = PathSecurity.archiveBaseName(for: archiveURL)
        if totalArchives > 1 {
            enclosingFolderCheckbox.title = "Tạo thư mục bao ngoài cho từng archive"
        } else {
            enclosingFolderCheckbox.title = "Tạo thư mục bao ngoài (/\(folderName))"
        }
        enclosingFolderCheckbox.state = .off
        enclosingFolderCheckbox.frame = NSRect(x: 20, y: 100, width: 450, height: 20)
        contentView.addSubview(enclosingFolderCheckbox)
        
        // Conflict policy (Default: Ask)
        let conflictTitle = NSTextField(labelWithString: "Xử lý file trùng:")
        conflictTitle.frame = NSRect(x: 20, y: 70, width: 120, height: 20)
        conflictTitle.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        contentView.addSubview(conflictTitle)
        
        conflictPopUp.frame = NSRect(x: 140, y: 67, width: 240, height: 24)
        for strategy in ConflictStrategy.allCases {
            conflictPopUp.addItem(withTitle: strategy.displayName)
            conflictPopUp.lastItem?.representedObject = strategy
        }
        conflictPopUp.selectItem(at: 0) // Default: Ask ("Hỏi khi trùng tên")
        contentView.addSubview(conflictPopUp)
        
        // Action buttons
        let cancelButton = NSButton(title: "Hủy", target: self, action: #selector(cancelClicked))
        cancelButton.frame = NSRect(x: 300, y: 18, width: 80, height: 30)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}" // Escape
        contentView.addSubview(cancelButton)
        
        let extractButton = NSButton(title: "Giải nén", target: self, action: #selector(extractClicked))
        extractButton.frame = NSRect(x: 390, y: 18, width: 80, height: 30)
        extractButton.bezelStyle = .rounded
        extractButton.keyEquivalent = "\r" // Enter
        contentView.addSubview(extractButton)
    }
    
    public func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        if (client as AnyObject) === pathTextField {
            pathFieldEditor.isFieldEditor = true
            return pathFieldEditor
        }
        return nil
    }
    
    public override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.window?.makeFirstResponder(self.pathTextField)
            self.pathTextField.currentEditor()?.selectAll(nil)
        }
    }
    
    private func loadArchiveInfo() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let info = try ExtractionManager.shared.inspect(archiveURL: self.archiveURL)
                let mb = Double(info.totalUncompressedSize) / 1_048_576.0
                let formatStr = info.format.rawValue
                let text: String
                if self.totalArchives > 1 {
                    text = "Tổng số: \(self.totalArchives) archive • Định dạng đầu: \(formatStr)"
                } else if info.totalEntries > 0 {
                    text = String(format: "Định dạng: %@ • %d file • Dung lượng giải nén: %.1f MB%@", formatStr, info.totalEntries, mb, info.isEncrypted ? " (Có mật khẩu)" : "")
                } else {
                    text = "Định dạng: \(formatStr)\(info.isEncrypted ? " • Có mật khẩu" : "")"
                }
                DispatchQueue.main.async {
                    self.infoLabel.stringValue = text
                }
            } catch {
                DispatchQueue.main.async {
                    let countText = self.totalArchives > 1 ? "Tổng số: \(self.totalArchives) archive • " : ""
                    self.infoLabel.stringValue = "\(countText)Định dạng: \(ArchiveFormat.detect(from: self.archiveURL).rawValue)"
                }
            }
        }
    }
    
    @objc private func browseClicked() {
        window?.endEditing(for: nil)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Chọn thư mục"
        panel.directoryURL = selectedDestinationURL
        
        if let window = self.window {
            panel.beginSheetModal(for: window) { [weak self] response in
                if response == .OK, let url = panel.url {
                    self?.applyDroppedOrSelectedFolder(url)
                }
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            applyDroppedOrSelectedFolder(url)
        }
    }
    
    private func notifyCancelIfNeeded() {
        guard !isConfirmed && !isCancelled else { return }
        isCancelled = true
        onCancel?()
    }
    
    @objc private func cancelClicked() {
        notifyCancelIfNeeded()
        window?.close()
    }
    
    public func windowWillClose(_ notification: Notification) {
        notifyCancelIfNeeded()
    }
    
    @objc private func extractClicked() {
        validateAndProceed()
    }
    
    public static func cleanPathString(_ raw: String) -> String {
        return PathSecurity.cleanUserInputPath(raw)
    }
    
    private func validateAndProceed() {
        window?.endEditing(for: nil)
        let rawPath = pathTextField.stringValue
        
        let targetURL: URL
        do {
            targetURL = try PathSecurity.resolveDestinationDirectoryURL(rawPath, baseDirectory: nil)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Đường dẫn không hợp lệ"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            window?.makeFirstResponder(pathTextField)
            return
        }
        
        pathTextField.stringValue = targetURL.path
        
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: targetURL.path, isDirectory: &isDir)
        
        if exists {
            if !isDir.boolValue {
                let alert = NSAlert()
                alert.messageText = "Đường dẫn không hợp lệ"
                alert.informativeText = "Đường dẫn \"\(targetURL.lastPathComponent)\" đã tồn tại nhưng là một tệp tin, không phải thư mục.\nVui lòng chỉ định một thư mục khác."
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
                window?.makeFirstResponder(pathTextField)
                return
            }
            self.selectedDestinationURL = targetURL
            executeProceed()
        } else {
            // Check if targetURL is a broken symlink via lstat
            var isSymlink = false
            if PathSecurity.itemExistsIncludingSymlink(at: targetURL, isDirectory: nil, isSymlink: &isSymlink) && isSymlink {
                let alert = NSAlert()
                alert.messageText = "Đường dẫn không hợp lệ"
                alert.informativeText = "Đường dẫn \"\(targetURL.lastPathComponent)\" là một liên kết tượng trưng (symlink) bị hỏng.\nVui lòng chọn thư mục khác."
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
                window?.makeFirstResponder(pathTextField)
                return
            }
            
            // Directory does not exist: ask to create
            let alert = NSAlert()
            alert.messageText = "Thư mục chưa tồn tại"
            alert.informativeText = "Thư mục đích:\n\(targetURL.path)\n\nchưa tồn tại. Bạn có muốn tạo thư mục này không?"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Tạo thư mục")
            alert.addButton(withTitle: "Hủy")
            
            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                do {
                    try fm.createDirectory(at: targetURL, withIntermediateDirectories: true, attributes: nil)
                    self.selectedDestinationURL = targetURL
                    self.executeProceed()
                } catch {
                    let errAlert = NSAlert()
                    errAlert.messageText = "Không thể tạo thư mục"
                    errAlert.informativeText = "Lỗi khi tạo thư mục đích:\n\(error.localizedDescription)"
                    errAlert.alertStyle = .critical
                    errAlert.addButton(withTitle: "OK")
                    NSApp.activate(ignoringOtherApps: true)
                    errAlert.runModal()
                    window?.makeFirstResponder(pathTextField)
                }
            } else {
                window?.makeFirstResponder(pathTextField)
            }
        }
    }
    
    private func executeProceed() {
        isConfirmed = true
        let strategy = (conflictPopUp.selectedItem?.representedObject as? ConflictStrategy) ?? .ask
        let createFolder = (enclosingFolderCheckbox.state == .on)
        
        let options = ExtractionOptions(
            destinationDirectory: PathSecurity.normalizeDirectoryURL(selectedDestinationURL),
            createEnclosingFolder: createFolder,
            conflictStrategy: strategy,
            conflictResolver: { ConflictDialog.prompt(for: $0) }
        )
        
        let confirmCallback = onConfirm
        onConfirm = nil
        window?.orderOut(nil)
        confirmCallback?(options)
        window?.close()
    }
}

// MARK: - DestinationPathTextField & DestinationPathFieldEditor (Safe Folder Drag & Paste)

public final class DestinationPathTextField: NSTextField {
    public var onFolderDropped: ((URL) -> Void)?
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if Self.extractDroppedDirectory(from: sender.draggingPasteboard) != nil {
            return .copy
        }
        return []
    }
    
    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let dirURL = Self.extractDroppedDirectory(from: sender.draggingPasteboard) else {
            return false
        }
        window?.endEditing(for: nil)
        stringValue = dirURL.path
        onFolderDropped?(dirURL)
        return true
    }
    
    public static func extractDroppedDirectory(from pboard: NSPasteboard) -> URL? {
        let urls = (pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ??
                   (pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
        guard let first = urls.first else { return nil }
        let normalized = PathSecurity.normalizeFileURL(first)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: normalized.path, isDirectory: &isDir) && isDir.boolValue {
            return PathSecurity.normalizeDirectoryURL(normalized)
        }
        return nil
    }
}

public final class DestinationPathFieldEditor: NSTextView {
    public var onFolderDropped: ((URL) -> Void)?
    
    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if DestinationPathTextField.extractDroppedDirectory(from: sender.draggingPasteboard) != nil {
            return .copy
        }
        return super.draggingEntered(sender)
    }
    
    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let dirURL = DestinationPathTextField.extractDroppedDirectory(from: sender.draggingPasteboard) {
            self.string = dirURL.path
            didChangeText()
            onFolderDropped?(dirURL)
            return true
        }
        return super.performDragOperation(sender)
    }
    
    public override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        // When a user copies a folder in Finder with Cmd+C, Finder places the full URL in .fileURL
        // and only the bare folder name (without '/') in .string. Resolve the full directory path!
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let first = urls.first {
            let normalized = PathSecurity.normalizeFileURL(first)
            let plainStr = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if plainStr.isEmpty || plainStr == normalized.lastPathComponent || !plainStr.contains("/") {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: normalized.path, isDirectory: &isDir) {
                    let targetDir = isDir.boolValue ? normalized : normalized.deletingLastPathComponent()
                    self.string = targetDir.path
                    didChangeText()
                    onFolderDropped?(PathSecurity.normalizeDirectoryURL(targetDir))
                    return
                }
            }
        }
        super.paste(sender)
    }
}

// MARK: - ExtractToBackgroundView (Drag & Drop Folder Support)

public final class ExtractToBackgroundView: NSView {
    public var onFolderDropped: ((URL) -> Void)?
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if DestinationPathTextField.extractDroppedDirectory(from: sender.draggingPasteboard) != nil {
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.borderWidth = 2
            needsDisplay = true
            return .copy
        }
        return []
    }
    
    public override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.borderWidth = 0
        needsDisplay = true
    }
    
    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderWidth = 0
        needsDisplay = true
        
        guard let dirURL = DestinationPathTextField.extractDroppedDirectory(from: sender.draggingPasteboard) else {
            return false
        }
        onFolderDropped?(dirURL)
        return true
    }
}
