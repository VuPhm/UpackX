import Foundation

/// Supported archive formats in UpackX
public enum ArchiveFormat: String, CaseIterable {
    case zip = "ZIP"
    case sevenZip = "7Z"
    case rar = "RAR"
    case tar = "TAR"
    case tarGz = "TAR.GZ"
    case tarBz2 = "TAR.BZ2"
    case tarXz = "TAR.XZ"
    case gzip = "GZ"
    case bzip2 = "BZ2"
    case xz = "XZ"
    case iso = "ISO"
    case cab = "CAB"
    case unknown = "Unknown"
    
    /// Detects format based on URL (extension and magic bytes)
    public static func detect(from url: URL) -> ArchiveFormat {
        let name = url.lastPathComponent.lowercased()
        
        // Compound extensions first
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") { return .tarGz }
        if name.hasSuffix(".tar.bz2") || name.hasSuffix(".tbz") || name.hasSuffix(".tbz2") { return .tarBz2 }
        if name.hasSuffix(".tar.xz") || name.hasSuffix(".txz") { return .tarXz }
        
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "zip", "zipx", "jar", "war": return .zip
        case "7z": return .sevenZip
        case "rar": return .rar
        case "tar": return .tar
        case "gz": return .gzip
        case "bz2": return .bzip2
        case "xz": return .xz
        case "iso": return .iso
        case "cab": return .cab
        default: break
        }
        
        // Magic byte fallback
        if let magic = readHeaderBytes(from: url, length: 16) {
            if magic.starts(with: [0x50, 0x4B, 0x03, 0x04]) || magic.starts(with: [0x50, 0x4B, 0x05, 0x06]) {
                return .zip
            }
            if magic.starts(with: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) {
                return .sevenZip
            }
            if magic.starts(with: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07]) {
                return .rar
            }
            if magic.starts(with: [0x1F, 0x8B]) {
                return name.contains(".tar") ? .tarGz : .gzip
            }
            if magic.starts(with: [0x42, 0x5A, 0x68]) {
                return name.contains(".tar") ? .tarBz2 : .bzip2
            }
            if magic.starts(with: [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) {
                return name.contains(".tar") ? .tarXz : .xz
            }
        }
        
        return .unknown
    }
    
    private static func readHeaderBytes(from url: URL, length: Int) -> [UInt8]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: length)
        return [UInt8](data)
    }
}
