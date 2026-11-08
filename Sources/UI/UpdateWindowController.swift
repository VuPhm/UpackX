import AppKit
import UniformTypeIdentifiers

public final class UpdateWindowController: NSWindowController, NSWindowDelegate {
    private let updateInfo: UpdateInfo
    private let autoCheckCheckbox = NSButton(checkboxWithTitle: "Tự động kiểm tra bản cập nhật mới", target: nil, action: nil)
    
    public init(updateInfo: UpdateInfo) {
        self.updateInfo = updateInfo
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Cập nhật phần mềm UpackX"
        window.center()
        window.isReleasedWhenClosed = false
        
        super.init(window: window)
        window.delegate = self
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        
        // App Icon
        let iconView = NSImageView(frame: NSRect(x: 24, y: 292, width: 64, height: 64))
        iconView.image = NSApp.applicationIconImage
        contentView.addSubview(iconView)
        
        // Title
        let titleLabel = NSTextField(labelWithString: "Đã có bản cập nhật mới của UpackX!")
        titleLabel.frame = NSRect(x: 104, y: 326, width: 396, height: 24)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 15)
        contentView.addSubview(titleLabel)
        
        // Subtitle & Version Info
        let currentVer = UpdateManager.shared.currentVersionString
        let sizeMBText: String
        if let size = updateInfo.assetSize, size > 0 {
            let mb = Double(size) / 1_048_576.0
            sizeMBText = String(format: " (%.1f MB)", mb)
        } else {
            sizeMBText = ""
        }
        
        let subTitle = "UpackX v\(updateInfo.version.description)\(sizeMBText) đã sẵn sàng để tải về (bạn đang dùng v\(currentVer))."
        let subLabel = NSTextField(labelWithString: subTitle)
        subLabel.frame = NSRect(x: 104, y: 298, width: 396, height: 26)
        subLabel.font = NSFont.systemFont(ofSize: 12)
        subLabel.textColor = .secondaryLabelColor
        subLabel.cell?.wraps = true
        contentView.addSubview(subLabel)
        
        // Release Notes Header
        let notesHeader = NSTextField(labelWithString: "Ghi chú phát hành:")
        notesHeader.frame = NSRect(x: 24, y: 260, width: 200, height: 18)
        notesHeader.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        contentView.addSubview(notesHeader)
        
        // Release Notes Scroll Area
        let scrollView = NSScrollView(frame: NSRect(x: 24, y: 85, width: 472, height: 170))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder
        scrollView.autohidesScrollers = true
        
        let contentSize = scrollView.contentSize
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height))
        textView.minSize = NSSize(width: 0.0, height: contentSize.height)
        textView.maxSize = NSSize(width: Double.greatestFiniteMagnitude, height: Double.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: Double.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 12)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.string = updateInfo.releaseNotes
        
        scrollView.documentView = textView
        contentView.addSubview(scrollView)
        
        // Auto-check Checkbox
        autoCheckCheckbox.frame = NSRect(x: 24, y: 52, width: 300, height: 20)
        autoCheckCheckbox.state = UpdateManager.shared.isAutoCheckEnabled ? .on : .off
        autoCheckCheckbox.target = self
        autoCheckCheckbox.action = #selector(autoCheckToggled)
        contentView.addSubview(autoCheckCheckbox)
        
        // Action Buttons Row
        let laterButton = NSButton(title: "Để sau", target: self, action: #selector(laterClicked))
        laterButton.frame = NSRect(x: 180, y: 14, width: 95, height: 32)
        laterButton.bezelStyle = .rounded
        laterButton.keyEquivalent = "\u{1b}" // Escape
        contentView.addSubview(laterButton)
        
        let githubButton = NSButton(title: "Xem trên GitHub", target: self, action: #selector(githubClicked))
        githubButton.frame = NSRect(x: 280, y: 14, width: 135, height: 32)
        githubButton.bezelStyle = .rounded
        contentView.addSubview(githubButton)
        
        let downloadButton = NSButton(title: "Tải bản cập nhật", target: self, action: #selector(downloadClicked))
        downloadButton.frame = NSRect(x: 420, y: 14, width: 140, height: 32)
        downloadButton.frame.origin.x = 496 - 130
        downloadButton.frame.size.width = 130
        downloadButton.bezelStyle = .rounded
        downloadButton.keyEquivalent = "\r" // Enter
        contentView.addSubview(downloadButton)
    }
    
    @objc private func autoCheckToggled() {
        UpdateManager.shared.isAutoCheckEnabled = (autoCheckCheckbox.state == .on)
    }
    
    @objc private func downloadClicked() {
        if let downloadURL = updateInfo.downloadURL {
            NSWorkspace.shared.open(downloadURL)
        } else {
            NSWorkspace.shared.open(updateInfo.htmlURL)
        }
        window?.close()
    }
    
    @objc private func githubClicked() {
        NSWorkspace.shared.open(updateInfo.htmlURL)
    }
    
    @objc private func laterClicked() {
        window?.close()
    }
}

