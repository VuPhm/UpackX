import AppKit
import UniformTypeIdentifiers

public final class MainWindowController: NSWindowController {
    public var onFileSelected: ((URL, Bool) -> Void)? // URL, isQuickExtract
    
    private let dropZone = DropZoneView()
    private let statusLabel = NSTextField(labelWithString: "Hỗ trợ ZIP, 7Z, RAR, TAR, GZ, BZ2, XZ • Native Intel x86_64")
    private let selectFileButton = NSButton(title: "Chọn file nén...", target: nil, action: nil)
    private let installFinderButton = NSButton(title: "Cài đặt Finder Quick Actions", target: nil, action: nil)
    
    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "UpackX — Lightweight macOS Archive Extractor"
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
        dropZone.frame = NSRect(x: 24, y: 90, width: 432, height: 200)
        dropZone.onFileDropped = { [weak self] url in
            self?.handleFile(url)
        }
        contentView.addSubview(dropZone)
        
        // Status label
        statusLabel.frame = NSRect(x: 24, y: 56, width: 432, height: 18)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        contentView.addSubview(statusLabel)
        
        // Buttons
        selectFileButton.frame = NSRect(x: 40, y: 16, width: 170, height: 32)
        selectFileButton.bezelStyle = .rounded
        selectFileButton.target = self
        selectFileButton.action = #selector(selectFileClicked)
        contentView.addSubview(selectFileButton)
        
        installFinderButton.frame = NSRect(x: 220, y: 16, width: 220, height: 32)
        installFinderButton.bezelStyle = .rounded
        installFinderButton.target = self
        installFinderButton.action = #selector(installFinderClicked)
        contentView.addSubview(installFinderButton)
    }
    
    @objc private func selectFileClicked() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Chọn file"
        
        if panel.runModal() == .OK, let url = panel.url {
            handleFile(url)
        }
    }
    
    @objc private func installFinderClicked() {
        do {
            try FinderIntegrationManager.shared.installQuickActions()
            let alert = NSAlert()
            alert.messageText = "Đã cài đặt Finder Quick Actions!"
            alert.informativeText = "Hai thao tác:\n1. 'Giải nén nhanh với UpackX'\n2. 'Giải nén… với UpackX'\nđã được thêm vào menu chuột phải (Quick Actions / Thao tác nhanh) trong Finder."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Lỗi cài đặt Finder Actions"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    private func handleFile(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = "Giải nén: \(url.lastPathComponent)"
        alert.informativeText = "Bạn muốn thực hiện thao tác nào?"
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
        let iconSize = NSSize(width: 64, height: 64)
        let iconOrigin = NSPoint(x: (bounds.width - iconSize.width) / 2, y: bounds.height / 2 - 10)
        icon.draw(in: NSRect(origin: iconOrigin, size: iconSize))
        
        let title = "Kéo thả file nén vào đây"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let titleSize = title.size(withAttributes: attrs)
        let titleOrigin = NSPoint(x: (bounds.width - titleSize.width) / 2, y: bounds.height / 2 - 45)
        title.draw(at: titleOrigin, withAttributes: attrs)
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
