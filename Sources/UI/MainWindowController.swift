import AppKit
import UniformTypeIdentifiers

public final class MainWindowController: NSWindowController {
    public var onFileSelected: ((URL, Bool) -> Void)? // Extraction: URL, isQuickExtract
    public var onCompressSelected: (([URL], Bool) -> Void)? // Compression: URLs, isQuickCompress
    
    private let dropZone = DropZoneView()
    private let statusLabel = NSTextField(labelWithString: "Hỗ trợ Nén ZIP & Giải nén ZIP, 7Z, RAR, TAR, GZ • Native Intel x86_64")
    private let extractButton = NSButton(title: "Chọn file giải nén...", target: nil, action: nil)
    private let compressButton = NSButton(title: "Chọn file/thư mục nén...", target: nil, action: nil)
    private let installFinderButton = NSButton(title: "Cài đặt Finder Services", target: nil, action: nil)
    
    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 350),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "UpackX — Native macOS Extractor & Compressor"
        window.center()
        window.isReleasedWhenClosed = false
        
        super.init(window: window)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        
        // Drop zone view
        dropZone.frame = NSRect(x: 24, y: 120, width: 452, height: 210)
        dropZone.onFileDropped = { [weak self] url in
            self?.handleDroppedItem(url)
        }
        contentView.addSubview(dropZone)
        
        // Status label
        statusLabel.frame = NSRect(x: 20, y: 88, width: 460, height: 18)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        contentView.addSubview(statusLabel)
        
        // Action Buttons Row 1
        extractButton.frame = NSRect(x: 35, y: 48, width: 205, height: 32)
        extractButton.bezelStyle = .rounded
        extractButton.target = self
        extractButton.action = #selector(selectExtractClicked)
        contentView.addSubview(extractButton)
        
        compressButton.frame = NSRect(x: 260, y: 48, width: 205, height: 32)
        compressButton.bezelStyle = .rounded
        compressButton.target = self
        compressButton.action = #selector(selectCompressClicked)
        contentView.addSubview(compressButton)
        
        // Action Button Row 2: Finder Services Manager
        installFinderButton.frame = NSRect(x: 120, y: 12, width: 260, height: 28)
        installFinderButton.bezelStyle = .rounded
        installFinderButton.target = self
        installFinderButton.action = #selector(installFinderClicked)
        contentView.addSubview(installFinderButton)
        
        updateStatusDisplay()
    }
    
    public func updateStatusDisplay() {
        let isConfigured = FinderIntegrationManager.shared.isServicesConfigured()
        let isInstalled = Bundle.main.bundlePath == "/Applications/UpackX.app"
        
        if isConfigured {
            statusLabel.stringValue = "Finder Services: Đang hoạt động (4 mục: 2 nén, 2 giải nén) • Intel x86_64"
            installFinderButton.title = "Kiểm tra Finder Services"
        } else {
            statusLabel.stringValue = isInstalled ? "Finder Services: Chưa bật đủ 4 mục • Nhấn để kích hoạt ngay" : "Khuyên dùng: Kéo UpackX vào /Applications để tích hợp Finder"
            installFinderButton.title = "Kích hoạt Finder Services (4 mục)"
        }
    }
    
    @objc private func selectExtractClicked() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Chọn file giải nén"
        
        if panel.runModal() == .OK, let url = panel.url {
            promptExtractAction(for: url)
        }
    }
    
    @objc private func selectCompressClicked() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Chọn mục nén"
        
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            promptCompressAction(for: panel.urls)
        }
    }
    
    @objc private func installFinderClicked() {
        do {
            try FinderIntegrationManager.shared.installServices()
            updateStatusDisplay()
            let alert = NSAlert()
            alert.messageText = "Finder Services đã sẵn sàng!"
            alert.informativeText = "UpackX đã thiết lập đúng 4 mục trong menu ngữ cảnh chuột phải của Finder:\n\n1. 'Giải nén nhanh với UpackX'\n2. 'Giải nén… với UpackX'\n3. 'Nén nhanh với UpackX'\n4. 'Nén… với UpackX'\n\nBạn có thể nhấp chuột phải vào bất kỳ file hoặc thư mục nào để sử dụng."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Lỗi kích hoạt Finder Services"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    private func handleDroppedItem(_ url: URL) {
        let isArchive = ArchiveFormat.detect(from: url) != .unknown
        if isArchive {
            promptExtractAction(for: url)
        } else {
            promptCompressAction(for: [url])
        }
    }
    
    private func promptExtractAction(for url: URL) {
        let alert = NSAlert()
        alert.messageText = "Giải nén: \(url.lastPathComponent)"
        alert.informativeText = "Chọn hình thức giải nén mong muốn:"
        alert.addButton(withTitle: "Giải nén nhanh")
        alert.addButton(withTitle: "Giải nén… (Tùy chọn)")
        alert.addButton(withTitle: "Hủy")
        
        let res = alert.runModal()
        if res == .alertFirstButtonReturn {
            onFileSelected?(url, true)
        } else if res == .alertSecondButtonReturn {
            onFileSelected?(url, false)
        }
    }
    
    private func promptCompressAction(for urls: [URL]) {
        let alert = NSAlert()
        let displayName = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) mục"
        alert.messageText = "Nén ZIP: \(displayName)"
        alert.informativeText = "Chọn hình thức nén ZIP mong muốn:"
        alert.addButton(withTitle: "Nén nhanh")
        alert.addButton(withTitle: "Nén… (Tùy chọn)")
        alert.addButton(withTitle: "Hủy")
        
        let res = alert.runModal()
        if res == .alertFirstButtonReturn {
            onCompressSelected?(urls, true)
        } else if res == .alertSecondButtonReturn {
            onCompressSelected?(urls, false)
        }
    }
}

// MARK: - DropZoneView

public final class DropZoneView: NSView {
    public var onFileDropped: ((URL) -> Void)?
    private var isHighlighted: Bool = false
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.separatorColor.cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let icon = NSWorkspace.shared.icon(for: .archive)
        let iconSize = NSSize(width: 56, height: 56)
        let iconOrigin = NSPoint(x: (bounds.width - iconSize.width) / 2, y: bounds.height / 2)
        icon.draw(in: NSRect(origin: iconOrigin, size: iconSize))
        
        let title = "Kéo thả file nén hoặc thư mục vào đây"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let titleSize = title.size(withAttributes: attrs)
        let titleOrigin = NSPoint(x: (bounds.width - titleSize.width) / 2, y: bounds.height / 2 - 35)
        title.draw(at: titleOrigin, withAttributes: attrs)
        
        let subtitle = "Tự động nhận diện: Giải nén archive hoặc Nén thành ZIP"
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let subSize = subtitle.size(withAttributes: subAttrs)
        let subOrigin = NSPoint(x: (bounds.width - subSize.width) / 2, y: bounds.height / 2 - 55)
        subtitle.draw(at: subOrigin, withAttributes: subAttrs)
    }
    
    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isHighlighted = true
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        needsDisplay = true
        return .copy
    }
    
    public override func draggingExited(_ sender: NSDraggingInfo?) {
        isHighlighted = false
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = nil
        needsDisplay = true
    }
    
    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isHighlighted = false
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = nil
        needsDisplay = true
        
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let first = items.first else {
            return false
        }
        
        onFileDropped?(first)
        return true
    }
}
