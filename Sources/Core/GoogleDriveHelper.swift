import Foundation

public enum CloudFileStatus {
    case localAvailable
    case downloadingPlaceholder
    case regularLocalFile
}

/// Helper for Google Drive for Desktop (CloudStorage / FileProvider) integration and file safety
public final class GoogleDriveHelper {
    
    /// Detects whether a URL resides inside Google Drive or an Apple CloudStorage provider mount
    public static func isGoogleDriveOrCloudStorage(url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if path.contains("/Library/CloudStorage/GoogleDrive-") || path.hasPrefix("/Volumes/GoogleDrive") {
            return true
        }
        if path.contains("/Library/CloudStorage/") {
            return true
        }
        return false
    }
    
    /// Verifies if a file is locally cached or a dataless cloud placeholder
    public static func checkFileAvailability(at url: URL) -> CloudFileStatus {
        guard isGoogleDriveOrCloudStorage(url: url) else {
            return .regularLocalFile
        }
        
        var statBuf = stat()
        if stat(url.path, &statBuf) == 0 {
            // SF_DATALESS flag is 0x40000000 on macOS APFS / FileProvider
            let SF_DATALESS: UInt32 = 0x40000000
            if (statBuf.st_flags & SF_DATALESS) != 0 {
                return .downloadingPlaceholder
            }
        }
        return .localAvailable
    }
    
    /// Commits a temporary partial file to its final destination safely, handling FileProvider / FUSE non-atomic renames
    public static func safeCommitFile(from tempURL: URL, to finalDestinationURL: URL) throws {
        let fm = FileManager.default
        
        // Remove existing destination file if overwriting
        if fm.fileExists(atPath: finalDestinationURL.path) {
            try? fm.removeItem(at: finalDestinationURL)
        }
        
        do {
            // Primary attempt: atomic rename / move
            try fm.moveItem(at: tempURL, to: finalDestinationURL)
        } catch {
            // Fallback for cloud storage cross-device or virtual mount rename restrictions
            do {
                try fm.copyItem(at: tempURL, to: finalDestinationURL)
                try? fm.removeItem(at: tempURL)
            } catch let fallbackError {
                throw ExtractionError.writeFailed("Không thể hoàn tất file trên Google Drive (\(fallbackError.localizedDescription))")
            }
        }
    }
    
    /// Generates appropriate completion notification text distinguishing local extraction from cloud sync
    public static func completionMessage(for archiveName: String, destinationURL: URL, fileCount: Int, elapsedTime: TimeInterval) -> (title: String, body: String) {
        let timeStr = String(format: "%.1fs", elapsedTime)
        let isDrive = isGoogleDriveOrCloudStorage(url: destinationURL)
        
        let title = "Giải nén hoàn tất"
        let body: String
        if isDrive {
            body = "Đã giải nén \(fileCount) file từ \(archiveName) vào thư mục Google Drive (Cục bộ) (\(timeStr)). Google Drive sẽ tự động đồng bộ lên đám mây."
        } else {
            body = "Đã giải nén \(fileCount) file từ \(archiveName) vào \(destinationURL.lastPathComponent) (\(timeStr))."
        }
        return (title, body)
    }
}
