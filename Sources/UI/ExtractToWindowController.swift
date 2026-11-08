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
    
    private let pathTextField = NSTextField()
    private let browseButton = NSButton(title: "Chọn...", target: nil, action: nil)
    private let enclosingFolderCheckbox = NSButton(checkboxWithTitle: "Tạo thư mục bao ngoài", target: nil, action: nil)
    private let conflictPopUp = NSPopUpButton()
    private let infoLabel = NSTextField(labelWithString: "Đang đọc thông tin archive...")
    
    public init(archiveURL: URL, totalArchives: Int = 1) {
        self.archiveURL = archiveURL
        self.totalArchives = totalArchives
        self.selectedDestinationURL = archiveURL.deletingLastPathComponent()
        
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
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        // Background Drop Area for Folders
        let bgView = ExtractToBackgroundView(frame: contentView.bounds)
        bgView.autoresizingMask = [.width, .height]
        bgView.onFolderDropped = { [weak self] folderURL in
            self?.selectedDestinationURL = folderURL
            self?.pathTextField.stringValue = folderURL.path
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
        contentView.addSubview(pathTextField)
        
        browseButton.frame = NSRect(x: 388, y: 129, width: 82, height: 28)
        browseButton.bezelStyle = .rounded
        browseButton.target = self
        browseButton.action = #selector(browseClicked)
        contentView.addSubview(browseButton)
        
        // Enclosing folder checkbox (Default: OFF per Section 0.3 & 2.2.B)
        let folderName = archiveURL.deletingPathExtension().lastPathComponent
        if totalArchives > 1 {
            enclosingFolderCheckbox.title = "Tạo thư mục bao ngoài cho từng archive"
        } else {
            enclosingFolderCheckbox.title = "Tạo thư mục bao ngoài (/\(folderName))"
        }
        enclosingFolderCheckbox.state = .off
        enclosingFolderCheckbox.frame = NSRect(x: 20, y: 100, width: 450, height: 20)
        contentView.addSubview(enclosingFolderCheckbox)
        
        // Conflict policy (Default: Ask per Section 0.3)
        let conflictTitle = NSTextField(labelWithString: "Xử lý file trùng:")
        conflictTitle.frame = NSRect(x: 20, y: 70, width: 120, height: 20)
        conflictTitle.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        contentView.addSubview(conflictTitle)
        
        conflictPopUp.frame = NSRect(x: 140, y: 67, width: 240, height: 24)
        for strategy in ConflictStrategy.allCases {
            conflictPopUp.addItem(withTitle: strategy.displayName)
            conflictPopUp.lastItem?.representedObject = strategy
        }
        conflictPopUp.selectItem(at: 0) // Default: Ask ("Hỏi khi trùng")
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
                    self?.selectedDestinationURL = url
                    self?.pathTextField.stringValue = url.path
                }
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            selectedDestinationURL = url
            pathTextField.stringValue = url.path
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
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("file://") {
            if let u = URL(string: s) {
                return u.path
            }
            s = String(s.dropFirst(7))
        }
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            s = String(s.dropFirst().dropLast())
        }
        s = s.replacingOccurrences(of: "\\ ", with: " ")
        s = (s as NSString).expandingTildeInPath
        return URL(fileURLWithPath: s).standardized.path
    }
    
    private func validateAndProceed() {
        let rawPath = pathTextField.stringValue
        let cleaned = Self.cleanPathString(rawPath)
        guard !cleaned.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "Đường dẫn không hợp lệ"
            alert.informativeText = "Vui lòng nhập đường dẫn thư mục giải nén."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            pathTextField.becomeFirstResponder()
            return
        }
        
        let targetURL = URL(fileURLWithPath: cleaned).standardized
        
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
                pathTextField.becomeFirstResponder()
                return
            }
            // Directory exists, proceed
            self.selectedDestinationURL = targetURL
            executeProceed()
        } else {
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
                    pathTextField.becomeFirstResponder()
                }
            } else {
                pathTextField.becomeFirstResponder()
            }
        }
    }
    
    private func executeProceed() {
        isConfirmed = true
        let strategy = (conflictPopUp.selectedItem?.representedObject as? ConflictStrategy) ?? .ask
        let createFolder = (enclosingFolderCheckbox.state == .on)
        
        let options = ExtractionOptions(
            destinationDirectory: selectedDestinationURL,
            createEnclosingFolder: createFolder,
            conflictStrategy: strategy,
            conflictResolver: { ConflictDialog.prompt(for: $0) }
        )
        
        window?.close()
        onConfirm?(options)
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
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let first = items.first else { return [] }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir) && isDir.boolValue {
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
        
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let first = items.first else { return false }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir) && isDir.boolValue {
            onFolderDropped?(first)
            return true
        }
        return false
    }
}
