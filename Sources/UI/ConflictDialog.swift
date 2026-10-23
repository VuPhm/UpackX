import AppKit

public final class ConflictDialog {
    
    /// Presents a synchronous conflict dialog on the main thread
    public static func prompt(for existingFileURL: URL) -> ConflictDecision {
        if Thread.isMainThread {
            return showModal(for: existingFileURL)
        } else {
            var decision = ConflictDecision(action: .rename, applyToAll: false)
            DispatchQueue.main.sync {
                decision = showModal(for: existingFileURL)
            }
            return decision
        }
    }
    
    private static func showModal(for existingFileURL: URL) -> ConflictDecision {
        let alert = NSAlert()
        alert.messageText = "Xung đột file"
        alert.informativeText = "File \"\(existingFileURL.lastPathComponent)\" đã tồn tại tại thư mục đích.\nBạn muốn xử lý như thế nào?"
        alert.alertStyle = .warning
        
        alert.addButton(withTitle: "Giữ cả hai (Đổi tên)") // Return 1000 (.rename)
        alert.addButton(withTitle: "Ghi đè")               // Return 1001 (.overwrite)
        alert.addButton(withTitle: "Bỏ qua")               // Return 1002 (.skip)
        alert.addButton(withTitle: "Hủy giải nén")         // Return 1003 (.cancel)
        
        let checkbox = NSButton(checkboxWithTitle: "Áp dụng cho tất cả các file trùng còn lại", target: nil, action: nil)
        alert.accessoryView = checkbox
        
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        
        let applyToAll = (checkbox.state == .on)
        let action: ConflictAction
        switch response {
        case .alertFirstButtonReturn:
            action = .rename
        case .alertSecondButtonReturn:
            action = .overwrite
        case .alertThirdButtonReturn:
            action = .skip
        default:
            action = .cancel
        }
        
        return ConflictDecision(action: action, applyToAll: applyToAll)
    }
}
