import AppKit

public final class PasswordDialog {
    
    public static func prompt(for archiveURL: URL) -> String? {
        if Thread.isMainThread {
            return showModal(for: archiveURL)
        } else {
            var pass: String? = nil
            DispatchQueue.main.sync {
                pass = showModal(for: archiveURL)
            }
            return pass
        }
    }
    
    private static func showModal(for archiveURL: URL) -> String? {
        let alert = NSAlert()
        alert.messageText = "File nén có mật khẩu"
        alert.informativeText = "File \"\(archiveURL.lastPathComponent)\" đã được mã hóa.\nVui lòng nhập mật khẩu để giải nén:"
        alert.alertStyle = .informational
        
        let inputField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        inputField.placeholderString = "Mật khẩu"
        alert.accessoryView = inputField
        
        alert.addButton(withTitle: "Xác nhận")
        alert.addButton(withTitle: "Hủy")
        
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            return inputField.stringValue
        }
        return nil
    }
}
