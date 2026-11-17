import AppKit
import UniformTypeIdentifiers

public final class CompressToWindowController: NSWindowController, NSWindowDelegate {
    public var onConfirm: ((URL, CompressionLevel) -> Void)?
    public var onCancel: (() -> Void)?
    
    private let sources: [URL]
    private var selectedDestinationDirectory: URL
    private var validatedArchiveFileName: String = "Archive.zip"
    private var isConfirmed = false
    private var isCancelled = false
    
    private let nameTextField = NSTextField()
    private let pathTextField = DestinationPathTextField()
    private let pathFieldEditor = DestinationPathFieldEditor()
    private let browseButton = NSButton(title: "Chọn...", target: nil, action: nil)
    private let levelPopUp = NSPopUpButton()
    private let infoLabel = NSTextField(labelWithString: "Đang tính toán dung lượng nguồn...")
    
    public init(sources: [URL]) {
        let normalizedSources = sources.map { PathSecurity.normalizeFileURL($0) }
        self.sources = normalizedSources
        self.selectedDestinationDirectory = PathSecurity.defaultCompressionDirectory(for: normalizedSources)
        self.validatedArchiveFileName = PathSecurity.defaultArchiveFileName(for: normalizedSources)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 490, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "UpackX — Tùy chọn nén ZIP"
        window.center()
        window.isReleasedWhenClosed = false
        
        super.init(window: window)
        window.delegate = self
        setupUI()
        calculateSourceInfo()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func applyDroppedOrSelectedFolder(_ folderURL: URL) {
        let cleanFolder = PathSecurity.normalizeDirectoryURL(folderURL)
        window?.endEditing(for: nil)
        selectedDestinationDirectory = cleanFolder
        pathTextField.stringValue = cleanFolder.path
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        // Background Drop Area for Destination Folders
        let bgView = ExtractToBackgroundView(frame: contentView.bounds)
        bgView.autoresizingMask = [.width, .height]
        bgView.onFolderDropped = { [weak self] folderURL in
            self?.applyDroppedOrSelectedFolder(folderURL)
        }
        contentView.addSubview(bgView, positioned: .below, relativeTo: nil)
        
        // Icon
        let iconView = NSImageView(frame: NSRect(x: 20, y: 210, width: 48, height: 48))
        if sources.count == 1, let first = sources.first {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir)
            if exists && isDir.boolValue {
                iconView.image = NSWorkspace.shared.icon(for: .folder)
            } else {
                let ext = first.pathExtension
                let type = UTType(filenameExtension: ext) ?? .data
                iconView.image = NSWorkspace.shared.icon(for: type)
            }
        } else {
            iconView.image = NSWorkspace.shared.icon(for: .folder)
        }
        contentView.addSubview(iconView)
        
        // Summary title
        let displayName: String
        if sources.count == 1, let first = sources.first {
            displayName = first.lastPathComponent
        } else {
            displayName = "Nén \(sources.count) mục được chọn"
        }
        
        let titleLabel = NSTextField(labelWithString: displayName)
        titleLabel.frame = NSRect(x: 80, y: 235, width: 390, height: 20)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        contentView.addSubview(titleLabel)
        
        infoLabel.frame = NSRect(x: 80, y: 215, width: 390, height: 18)
        infoLabel.font = NSFont.systemFont(ofSize: 11)
        infoLabel.textColor = .secondaryLabelColor
        contentView.addSubview(infoLabel)
        
        // Archive File Name
        let nameTitle = NSTextField(labelWithString: "Tên file nén (.zip):")
        nameTitle.frame = NSRect(x: 20, y: 175, width: 140, height: 18)
        nameTitle.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        contentView.addSubview(nameTitle)
        
        nameTextField.frame = NSRect(x: 160, y: 173, width: 310, height: 22)
        nameTextField.stringValue = validatedArchiveFileName
        nameTextField.isEditable = true
        nameTextField.isSelectable = true
        nameTextField.isBezeled = true
        nameTextField.bezelStyle = .roundedBezel
        nameTextField.lineBreakMode = .byClipping
        nameTextField.cell?.wraps = false
        nameTextField.cell?.isScrollable = true
        nameTextField.placeholderString = "Nhập tên file nén (.zip)..."
        nameTextField.target = self
        nameTextField.action = #selector(compressClicked)
        contentView.addSubview(nameTextField)
        
        // Destination directory
        let destTitle = NSTextField(labelWithString: "Lưu vào:")
        destTitle.frame = NSRect(x: 20, y: 135, width: 120, height: 18)
        destTitle.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        contentView.addSubview(destTitle)
        
        pathTextField.frame = NSRect(x: 20, y: 108, width: 360, height: 22)
        pathTextField.stringValue = selectedDestinationDirectory.path
        pathTextField.isEditable = true
        pathTextField.isSelectable = true
        pathTextField.isBezeled = true
        pathTextField.bezelStyle = .roundedBezel
        pathTextField.lineBreakMode = .byClipping
        pathTextField.cell?.wraps = false
        pathTextField.cell?.isScrollable = true
        pathTextField.placeholderString = "Nhập, dán hoặc kéo thả thư mục lưu..."
        pathTextField.target = self
        pathTextField.action = #selector(compressClicked)
        pathTextField.onFolderDropped = { [weak self] folderURL in
            self?.applyDroppedOrSelectedFolder(folderURL)
        }
        pathFieldEditor.onFolderDropped = { [weak self] folderURL in
            self?.applyDroppedOrSelectedFolder(folderURL)
        }
        contentView.addSubview(pathTextField)
        
        browseButton.frame = NSRect(x: 388, y: 104, width: 82, height: 28)
        browseButton.bezelStyle = .rounded
        browseButton.target = self
        browseButton.action = #selector(browseClicked)
        contentView.addSubview(browseButton)
        
        // Compression level
        let levelTitle = NSTextField(labelWithString: "Mức độ nén:")
        levelTitle.frame = NSRect(x: 20, y: 72, width: 120, height: 20)
        levelTitle.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        contentView.addSubview(levelTitle)
        
        levelPopUp.frame = NSRect(x: 160, y: 69, width: 220, height: 24)
        for level in CompressionLevel.allCases {
            levelPopUp.addItem(withTitle: level.title)
            levelPopUp.lastItem?.representedObject = level
        }
        levelPopUp.selectItem(at: 1) // Default: Normal
        contentView.addSubview(levelPopUp)
        
        // Action buttons
        let cancelButton = NSButton(title: "Hủy", target: self, action: #selector(cancelClicked))
        cancelButton.frame = NSRect(x: 300, y: 18, width: 80, height: 30)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}" // Escape
        contentView.addSubview(cancelButton)
        
        let compressButton = NSButton(title: "Nén", target: self, action: #selector(compressClicked))
        compressButton.frame = NSRect(x: 390, y: 18, width: 80, height: 30)
        compressButton.bezelStyle = .rounded
        compressButton.keyEquivalent = "\r" // Enter
        contentView.addSubview(compressButton)
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
            self.window?.makeFirstResponder(self.nameTextField)
            self.nameTextField.currentEditor()?.selectAll(nil)
        }
    }
    
    private func calculateSourceInfo() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var totalBytes: Int64 = 0
            var fileCount = 0
            let fm = FileManager.default
            
            for src in self.sources {
                var isDir: ObjCBool = false
                let exists = fm.fileExists(atPath: src.path, isDirectory: &isDir)
                if exists && isDir.boolValue {
                    if let enumerator = fm.enumerator(at: src, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [.skipsHiddenFiles], errorHandler: nil) {
                        for case let fileURL as URL in enumerator {
                            let isSubDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                            if !isSubDir {
                                let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                                totalBytes += Int64(size)
                                fileCount += 1
                            }
                        }
                    }
                } else if exists {
                    let size = (try? src.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    totalBytes += Int64(size)
                    fileCount += 1
                }
            }
            
            let mb = Double(totalBytes) / 1_048_576.0
            let infoText: String
            if mb < 0.1 {
                let kb = Double(totalBytes) / 1024.0
                infoText = String(format: "Dung lượng nguồn: %.1f KB • %d tệp", kb, fileCount)
            } else {
                infoText = String(format: "Dung lượng nguồn: %.1f MB • %d tệp", mb, fileCount)
            }
            
            DispatchQueue.main.async {
                self.infoLabel.stringValue = infoText
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
        panel.prompt = "Chọn thư mục lưu"
        panel.directoryURL = selectedDestinationDirectory
        
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
    
    @objc private func compressClicked() {
        validateAndProceed()
    }
    
    private func validateAndProceed() {
        window?.endEditing(for: nil)
        
        // 1. Validate Archive Filename (forbid hierarchical separators and empty names)
        let normalizedArchiveName: String
        do {
            normalizedArchiveName = try PathSecurity.validateAndNormalizeArchiveFileName(nameTextField.stringValue)
            nameTextField.stringValue = normalizedArchiveName
            self.validatedArchiveFileName = normalizedArchiveName
        } catch {
            let alert = NSAlert()
            alert.messageText = "Tên file nén không hợp lệ"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            window?.makeFirstResponder(nameTextField)
            return
        }
        
        // 2. Validate Destination Directory Path
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
            self.selectedDestinationDirectory = targetURL
            executeProceed()
        } else {
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
            
            let alert = NSAlert()
            alert.messageText = "Thư mục chưa tồn tại"
            alert.informativeText = "Thư mục lưu:\n\(targetURL.path)\n\nchưa tồn tại. Bạn có muốn tạo thư mục này không?"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Tạo thư mục")
            alert.addButton(withTitle: "Hủy")
            
            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                do {
                    try fm.createDirectory(at: targetURL, withIntermediateDirectories: true, attributes: nil)
                    self.selectedDestinationDirectory = targetURL
                    self.executeProceed()
                } catch {
                    let errAlert = NSAlert()
                    errAlert.messageText = "Không thể tạo thư mục"
                    errAlert.informativeText = "Lỗi khi tạo thư mục lưu:\n\(error.localizedDescription)"
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
        let destDir = PathSecurity.normalizeDirectoryURL(selectedDestinationDirectory)
        let destinationURL = destDir.appendingPathComponent(validatedArchiveFileName, isDirectory: false)
        
        // Prevent colliding with an existing directory named "<Archive>.zip"
        var isExistingDestDir: ObjCBool = false
        var isExistingDestSymlink: Bool = false
        if PathSecurity.itemExistsIncludingSymlink(at: destinationURL, isDirectory: &isExistingDestDir, isSymlink: &isExistingDestSymlink),
           isExistingDestDir.boolValue && !isExistingDestSymlink {
            let alert = NSAlert()
            alert.messageText = "Trùng tên với thư mục hiện có"
            alert.informativeText = "Tại thư mục đích đã tồn tại một thư mục có tên \"\(validatedArchiveFileName)\".\nVui lòng đặt tên file nén khác."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            window?.makeFirstResponder(nameTextField)
            return
        }
        
        let selectedLevel = (levelPopUp.selectedItem?.representedObject as? CompressionLevel) ?? .normal
        
        isConfirmed = true
        let confirmCallback = onConfirm
        onConfirm = nil
        window?.orderOut(nil)
        confirmCallback?(destinationURL, selectedLevel)
        window?.close()
    }
}
