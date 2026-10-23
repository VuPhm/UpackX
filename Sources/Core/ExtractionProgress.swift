import Foundation

/// Progress state emitted during extraction
public struct ExtractionProgress {
    public let archiveName: String
    public let currentFilePath: String
    public let extractedBytes: Int64
    public let totalBytes: Int64?
    public let extractedEntriesCount: Int
    public let totalEntriesCount: Int?
    public let elapsedTime: TimeInterval
    
    public var fractionCompleted: Double? {
        if let total = totalBytes, total > 0 {
            return min(1.0, max(0.0, Double(extractedBytes) / Double(total)))
        }
        if let totalCount = totalEntriesCount, totalCount > 0 {
            return min(1.0, max(0.0, Double(extractedEntriesCount) / Double(totalCount)))
        }
        return nil
    }
    
    public var bytesPerSecond: Double {
        guard elapsedTime > 0.05 else { return 0 }
        return Double(extractedBytes) / elapsedTime
    }
    
    public init(archiveName: String,
                currentFilePath: String,
                extractedBytes: Int64,
                totalBytes: Int64? = nil,
                extractedEntriesCount: Int,
                totalEntriesCount: Int? = nil,
                elapsedTime: TimeInterval) {
        self.archiveName = archiveName
        self.currentFilePath = currentFilePath
        self.extractedBytes = extractedBytes
        self.totalBytes = totalBytes
        self.extractedEntriesCount = extractedEntriesCount
        self.totalEntriesCount = totalEntriesCount
        self.elapsedTime = elapsedTime
    }
}

/// Final result returned after extraction completes
public struct ExtractionResult {
    public let archiveURL: URL
    public let destinationURL: URL
    public let extractedCount: Int
    public let skippedCount: Int
    public let totalBytes: Int64
    public let elapsedTime: TimeInterval
    
    public init(archiveURL: URL,
                destinationURL: URL,
                extractedCount: Int,
                skippedCount: Int,
                totalBytes: Int64,
                elapsedTime: TimeInterval) {
        self.archiveURL = archiveURL
        self.destinationURL = destinationURL
        self.extractedCount = extractedCount
        self.skippedCount = skippedCount
        self.totalBytes = totalBytes
        self.elapsedTime = elapsedTime
    }
}

public enum ExtractionError: LocalizedError {
    case fileNotFound(URL)
    case unsupportedFormat(String)
    case passwordRequired
    case wrongPassword
    case corruptedArchive(String)
    case cancelled
    case writeFailed(String)
    case pathSecurityViolation(String)
    case generic(String)
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Không tìm thấy file: \(url.path)"
        case .unsupportedFormat(let fmt):
            return "Định dạng file không được hỗ trợ: \(fmt)"
        case .passwordRequired:
            return "File nén có mật khẩu bảo vệ. Vui lòng nhập mật khẩu."
        case .wrongPassword:
            return "Mật khẩu không chính xác."
        case .corruptedArchive(let msg):
            return "File nén bị hỏng hoặc dữ liệu không hoàn chỉnh: \(msg)"
        case .cancelled:
            return "Quá trình giải nén đã bị hủy."
        case .writeFailed(let msg):
            return "Lỗi khi ghi file ra ổ đĩa: \(msg)"
        case .pathSecurityViolation(let msg):
            return "Nguy cơ bảo mật Zip-Slip: \(msg)"
        case .generic(let msg):
            return "Lỗi giải nén: \(msg)"
        }
    }
}
