import Foundation

/// Information about an individual entry inside an archive
public struct ArchiveEntryInfo: Identifiable {
    public var id: String { path }
    public let path: String
    public let uncompressedSize: Int64
    public let compressedSize: Int64?
    public let isDirectory: Bool
    public let isEncrypted: Bool
    public let permissions: UInt16
    public let modificationDate: Date?
    public let symlinkTarget: String?
    
    public init(path: String,
                uncompressedSize: Int64,
                compressedSize: Int64? = nil,
                isDirectory: Bool,
                isEncrypted: Bool = false,
                permissions: UInt16 = 0o644,
                modificationDate: Date? = nil,
                symlinkTarget: String? = nil) {
        self.path = path
        self.uncompressedSize = uncompressedSize
        self.compressedSize = compressedSize
        self.isDirectory = isDirectory
        self.isEncrypted = isEncrypted
        self.permissions = permissions
        self.modificationDate = modificationDate
        self.symlinkTarget = symlinkTarget
    }
}

/// Summary information for an archive file
public struct ArchiveInfo {
    public let fileURL: URL
    public let format: ArchiveFormat
    public let totalEntries: Int
    public let totalUncompressedSize: Int64
    public let isEncrypted: Bool
    public let entries: [ArchiveEntryInfo]
    
    public init(fileURL: URL,
                format: ArchiveFormat,
                totalEntries: Int,
                totalUncompressedSize: Int64,
                isEncrypted: Bool,
                entries: [ArchiveEntryInfo] = []) {
        self.fileURL = fileURL
        self.format = format
        self.totalEntries = totalEntries
        self.totalUncompressedSize = totalUncompressedSize
        self.isEncrypted = isEncrypted
        self.entries = entries
    }
}
