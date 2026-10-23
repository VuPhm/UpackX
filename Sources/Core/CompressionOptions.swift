import Foundation

// MARK: - Compression Level

public enum CompressionLevel: String, CaseIterable {
    case fast = "fast"
    case normal = "normal"
    case maximum = "maximum"
    
    public var title: String {
        switch self {
        case .fast:
            return "Nhanh (Fast)"
        case .normal:
            return "Tiêu chuẩn (Normal)"
        case .maximum:
            return "Nén tối đa (Maximum)"
        }
    }
    
    public var libarchiveLevel: Int {
        switch self {
        case .fast: return 1
        case .normal: return 6
        case .maximum: return 9
        }
    }
}

// MARK: - Compression Options

public struct CompressionOptions {
    public var destinationURL: URL
    public var compressionLevel: CompressionLevel
    public var conflictStrategy: ConflictStrategy
    public var conflictResolver: ConflictResolver?
    
    public init(
        destinationURL: URL,
        compressionLevel: CompressionLevel = .normal,
        conflictStrategy: ConflictStrategy = .ask,
        conflictResolver: ConflictResolver? = nil
    ) {
        self.destinationURL = destinationURL
        self.compressionLevel = compressionLevel
        self.conflictStrategy = conflictStrategy
        self.conflictResolver = conflictResolver
    }
}

// MARK: - Compression Progress & Result

public struct CompressionProgress {
    public let currentItemName: String
    public let processedFiles: Int
    public let totalFiles: Int
    public let processedBytes: Int64
    public let totalBytes: Int64
    public let fractionCompleted: Double
    
    public init(
        currentItemName: String,
        processedFiles: Int,
        totalFiles: Int,
        processedBytes: Int64,
        totalBytes: Int64
    ) {
        self.currentItemName = currentItemName
        self.processedFiles = processedFiles
        self.totalFiles = totalFiles
        self.processedBytes = processedBytes
        self.totalBytes = totalBytes
        if totalBytes > 0 {
            self.fractionCompleted = min(1.0, max(0.0, Double(processedBytes) / Double(totalBytes)))
        } else if totalFiles > 0 {
            self.fractionCompleted = min(1.0, max(0.0, Double(processedFiles) / Double(totalFiles)))
        } else {
            self.fractionCompleted = 0.0
        }
    }
}

public struct CompressionResult {
    public let destinationURL: URL
    public let totalItemsCompressed: Int
    public let totalBytesProcessed: Int64
    public let archiveSize: Int64
    public let elapsedTime: TimeInterval
    
    public init(
        destinationURL: URL,
        totalItemsCompressed: Int,
        totalBytesProcessed: Int64,
        archiveSize: Int64,
        elapsedTime: TimeInterval
    ) {
        self.destinationURL = destinationURL
        self.totalItemsCompressed = totalItemsCompressed
        self.totalBytesProcessed = totalBytesProcessed
        self.archiveSize = archiveSize
        self.elapsedTime = elapsedTime
    }
}

// MARK: - Compression Error

public enum CompressionError: LocalizedError {
    case emptySource
    case cannotCreateArchive(String)
    case cancelled
    case writeFailed(String)
    case destinationExists(String)
    case sourceNotFound(String)
    case permissionDenied(String)
    case diskFull(String)
    case sourceUnreadable(path: String, reason: String)
    case entrySizeMismatch(path: String, declared: Int64, actual: Int64)
    case traversalFailed(path: String, reason: String)
    case unsupportedFileType(path: String, type: String)
    case archiveCloseFailed(String)
    case commitFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .emptySource:
            return "Không có file hoặc thư mục nguồn nào để nén."
        case .cannotCreateArchive(let msg):
            return "Không thể khởi tạo file nén: \(msg)"
        case .cancelled:
            return "Tác vụ nén đã bị hủy bởi người dùng."
        case .writeFailed(let msg):
            return "Lỗi ghi dữ liệu nén: \(msg)"
        case .destinationExists(let path):
            return "File đích đã tồn tại: \(path)"
        case .sourceNotFound(let path):
            return "Không tìm thấy nguồn: \(path)"
        case .permissionDenied(let path):
            return "Không có quyền đọc dữ liệu tại: \(path)"
        case .diskFull(let msg):
            return "Dung lượng ổ đĩa không đủ: \(msg)"
        case .sourceUnreadable(let path, let reason):
            return "Không thể đọc tệp nguồn tại '\(path)': \(reason)"
        case .entrySizeMismatch(let path, let declared, let actual):
            return "Kích thước tệp thay đổi trong quá trình nén tại '\(path)' (khai báo: \(declared) bytes, thực tế: \(actual) bytes)."
        case .traversalFailed(let path, let reason):
            return "Lỗi quét thư mục nguồn tại '\(path)': \(reason)"
        case .unsupportedFileType(let path, let type):
            return "Loại tệp không được hỗ trợ để nén tại '\(path)' (\(type))."
        case .archiveCloseFailed(let msg):
            return "Lỗi đóng và hoàn tất file nén: \(msg)"
        case .commitFailed(let msg):
            return "Không thể hoàn tất file nén đích (commit thất bại): \(msg)"
        }
    }
}
