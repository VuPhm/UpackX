import AppKit
import UniformTypeIdentifiers

public final class CompressToWindowController: NSWindowController {
    public var onConfirm: ((URL, CompressionLevel) -> Void)?
    public var onCancel: (() -> Void)?
    
    private let sources: [URL]
    private var selectedDestinationDirectory: URL
    
    private let nameTextField = NSTextField()
    private let pathTextField = NSTextField()
    private let browseButton = NSButton(title: "Chọn...", target: nil, action: nil)
    private let levelPopUp = NSPopUpButton()
    private let infoLabel = NSTextField(labelWithString: "Đang tính toán dung lượng nguồn...")
    
    public init(sources: [URL]) {
        self.sources = sources
        let firstSource = sources.first ?? FileManager.default.homeDirectoryForCurrentUser
        self.selectedDestinationDirectory = firstSource.deletingLastPathComponent()
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 490, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "UpackX — Tùy chọn nén ZIP"
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        
        super.init(window: window)
        setupUI()
        calculateSourceInfo()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        // Icon
        let iconView = NSImageView(frame: NSRect(x: 20, y: 210, width: 48, height: 48))
        if sources.count == 1, let first = sources.first {
            let isDir = (try? first.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
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
        let defaultName: String
        if sources.count == 1, let first = sources.first {
            let base = first.deletingPathExtension().lastPathComponent
            defaultName = base.isEmpty ? "Archive.zip" : "\(base).zip"
        } else {
            defaultName = "Archive.zip"
        }
        nameTextField.stringValue = defaultName
        contentView.addSubview(nameTextField)
        
        // Destination directory
        let destTitle = NSTextField(labelWithString: "Lưu vào:")
        destTitle.frame = NSRect(x: 20, y: 135, width: 120, height: 18)
        destTitle.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        contentView.addSubview(destTitle)
        
        pathTextField.frame = NSRect(x: 20, y: 108, width: 360, height: 22)
        pathTextField.stringValue = selectedDestinationDirectory.path
        pathTextField.isEditable = false
        pathTextField.lineBreakMode = .byTruncatingHead
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
    
    public override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    
    private func calculateSourceInfo() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var totalBytes: Int64 = 0
            var fileCount = 0
            let fm = FileManager.default
            
            for src in self.sources {
                let isDir = (try? src.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isDir {
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
                } else {
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
                    self?.selectedDestinationDirectory = url
                    self?.pathTextField.stringValue = url.path
                }
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            selectedDestinationDirectory = url
            pathTextField.stringValue = url.path
        }
    }
    
    @objc private func cancelClicked() {
        window?.close()
        onCancel?()
    }
    
    @objc private func compressClicked() {
        var rawName = nameTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawName.isEmpty {
            rawName = "Archive.zip"
        }
        if !rawName.lowercased().hasSuffix(".zip") {
            rawName += ".zip"
        }
        
        let destinationURL = selectedDestinationDirectory.appendingPathComponent(rawName)
        let selectedLevel = (levelPopUp.selectedItem?.representedObject as? CompressionLevel) ?? .normal
        
        window?.close()
        onConfirm?(destinationURL, selectedLevel)
    }
}
