import AppKit
import UniformTypeIdentifiers

public final class ProgressWindowController: NSWindowController {
    public var onCancel: (() -> Void)?
    public private(set) var isCancelled: Bool = false
    
    private let titleLabel = NSTextField(labelWithString: "Đang giải nén...")
    private let fileLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "Chuẩn bị giải nén...")
    private let progressIndicator = NSProgressIndicator()
    private let cancelButton = NSButton(title: "Hủy", target: nil, action: nil)
    
    public init(archiveName: String, isCompressing: Bool = false) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 145),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = isCompressing ? "UpackX — Nén ZIP" : "UpackX — Giải nén"
        panel.level = .floating
        panel.center()
        panel.isReleasedWhenClosed = false
        
        super.init(window: panel)
        setupUI(archiveName: archiveName, isCompressing: isCompressing)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI(archiveName: String, isCompressing: Bool) {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        
        let iconView = NSImageView(frame: NSRect(x: 20, y: 80, width: 48, height: 48))
        iconView.image = isCompressing ? NSWorkspace.shared.icon(for: .folder) : NSWorkspace.shared.icon(for: .archive)
        contentView.addSubview(iconView)
        
        titleLabel.frame = NSRect(x: 80, y: 104, width: 270, height: 20)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        titleLabel.stringValue = archiveName
        titleLabel.lineBreakMode = .byTruncatingMiddle
        contentView.addSubview(titleLabel)
        
        fileLabel.frame = NSRect(x: 80, y: 82, width: 270, height: 18)
        fileLabel.font = NSFont.systemFont(ofSize: 11)
        fileLabel.textColor = .secondaryLabelColor
        fileLabel.lineBreakMode = .byTruncatingMiddle
        contentView.addSubview(fileLabel)
        
        progressIndicator.frame = NSRect(x: 80, y: 56, width: 340, height: 14)
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0.0
        progressIndicator.maxValue = 1.0
        progressIndicator.doubleValue = 0.0
        contentView.addSubview(progressIndicator)
        
        detailLabel.frame = NSRect(x: 80, y: 22, width: 250, height: 18)
        detailLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.stringValue = isCompressing ? "Chuẩn bị nén..." : "Chuẩn bị giải nén..."
        contentView.addSubview(detailLabel)
        
        cancelButton.frame = NSRect(x: 340, y: 16, width: 80, height: 28)
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        contentView.addSubview(cancelButton)
    }
    
    @objc private func cancelClicked() {
        isCancelled = true
        cancelButton.isEnabled = false
        detailLabel.stringValue = "Đang hủy tác vụ..."
        onCancel?()
    }
    
    public func update(progress: ExtractionProgress) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isCancelled else { return }
            
            self.fileLabel.stringValue = progress.currentFilePath
            
            if let fraction = progress.fractionCompleted {
                self.progressIndicator.isIndeterminate = false
                self.progressIndicator.doubleValue = fraction
                
                let percentInt = Int(fraction * 100)
                let extractedMB = Double(progress.extractedBytes) / 1_048_576.0
                if let total = progress.totalBytes, total > 0 {
                    let totalMB = Double(total) / 1_048_576.0
                    let speedMB = progress.bytesPerSecond / 1_048_576.0
                    self.detailLabel.stringValue = String(format: "%.1f / %.1f MB (%d%%) • %.1f MB/s", extractedMB, totalMB, percentInt, speedMB)
                } else {
                    self.detailLabel.stringValue = String(format: "%.1f MB • %d files", extractedMB, progress.extractedEntriesCount)
                }
            } else {
                self.progressIndicator.isIndeterminate = true
                self.progressIndicator.startAnimation(nil)
                let extractedMB = Double(progress.extractedBytes) / 1_048_576.0
                self.detailLabel.stringValue = String(format: "Đã giải nén %.1f MB • %d files", extractedMB, progress.extractedEntriesCount)
            }
        }
    }
    
    public func update(compressionProgress: CompressionProgress) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isCancelled else { return }
            
            self.fileLabel.stringValue = compressionProgress.currentItemName
            self.progressIndicator.isIndeterminate = false
            self.progressIndicator.doubleValue = compressionProgress.fractionCompleted
            
            let percentInt = Int(compressionProgress.fractionCompleted * 100)
            let processedMB = Double(compressionProgress.processedBytes) / 1_048_576.0
            if compressionProgress.totalBytes > 0 {
                let totalMB = Double(compressionProgress.totalBytes) / 1_048_576.0
                self.detailLabel.stringValue = String(format: "%.1f / %.1f MB (%d%%) • %d/%d tệp", processedMB, totalMB, percentInt, compressionProgress.processedFiles, compressionProgress.totalFiles)
            } else {
                self.detailLabel.stringValue = String(format: "%d/%d mục (%d%%)", compressionProgress.processedFiles, compressionProgress.totalFiles, percentInt)
            }
        }
    }

}
