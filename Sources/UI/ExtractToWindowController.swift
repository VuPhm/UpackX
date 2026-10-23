import AppKit
import UniformTypeIdentifiers

public final class ExtractToWindowController: NSWindowController {
    public var onConfirm: ((ExtractionOptions) -> Void)?
    public var onCancel: (() -> Void)?
    
    private let archiveURL: URL
    private let totalArchives: Int
    private var selectedDestinationURL: URL
    
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
        window.level = .floating
        window.isReleasedWhenClosed = false
        
        super.init(window: window)
        setupUI()
        loadArchiveInfo()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
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
        
        pathTextField.frame = NSRect(x: 20, y: 133, width: 360, height: 22)
        pathTextField.stringValue = selectedDestinationURL.path
        pathTextField.isEditable = false
        pathTextField.lineBreakMode = .byTruncatingHead
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
    
    @objc private func cancelClicked() {
        window?.close()
        onCancel?()
    }
    
    @objc private func extractClicked() {
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
