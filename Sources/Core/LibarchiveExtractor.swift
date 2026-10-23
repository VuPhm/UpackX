import Foundation

/// Primary native extraction engine using macOS system libarchive.
/// Highly optimized for streaming, minimal RAM usage (< 15MB), and resilient error handling.
public final class LibarchiveExtractor: ArchiveExtractorProtocol {
    public let name = "Libarchive (Native System)"
    
    public init() {}
    
    public func canHandle(format: ArchiveFormat, archiveURL: URL) -> Bool {
        switch format {
        case .zip, .tar, .tarGz, .tarBz2, .tarXz, .gzip, .bzip2, .xz, .iso, .cab, .sevenZip, .rar:
            return true
        case .unknown:
            return false
        }
    }
    
    public func inspect(archiveURL: URL, password: String?) throws -> ArchiveInfo {
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw ExtractionError.fileNotFound(archiveURL)
        }
        
        guard let a = archive_read_new() else {
            throw ExtractionError.generic("Không thể khởi tạo bộ đọc archive.")
        }
        defer { _ = archive_read_free(a) }
        
        _ = archive_read_support_filter_all(a)
        _ = archive_read_support_format_all(a)
        
        if let pw = password, !pw.isEmpty {
            _ = archive_read_add_passphrase(a, pw)
        }
        
        let openRes = archive_read_open_filename(a, archiveURL.path, 16384)
        guard openRes == ARCHIVE_OK else {
            let msg = archive_error_string(a).flatMap { String(cString: $0) } ?? "Mã lỗi \(openRes)"
            throw ExtractionError.corruptedArchive("Không thể mở file nén: \(msg)")
        }
        
        var entries: [ArchiveEntryInfo] = []
        var totalBytes: Int64 = 0
        var isEncrypted = false
        var entryPtr: ArchiveEntryPtr? = nil
        
        while true {
            let r = archive_read_next_header(a, &entryPtr)
            if r == ARCHIVE_EOF { break }
            if r != ARCHIVE_OK {
                let msg = archive_error_string(a).flatMap { String(cString: $0) } ?? ""
                if r == ARCHIVE_WARN {
                    // Non-fatal warning, can continue
                } else {
                    if msg.lowercased().contains("passphrase") || msg.lowercased().contains("password") || msg.lowercased().contains("encrypt") {
                        isEncrypted = true
                        break
                    }
                    throw ExtractionError.corruptedArchive("Lỗi khi đọc header file nén: \(msg)")
                }
            }
            
            guard let entry = entryPtr else { continue }
            
            let pathStr: String
            if let pUtf8 = archive_entry_pathname_utf8(entry) {
                pathStr = String(cString: pUtf8)
            } else if let p = archive_entry_pathname(entry) {
                pathStr = String(cString: p)
            } else {
                pathStr = "unknown_entry_\(entries.count)"
            }
            
            let size = archive_entry_size(entry)
            let fileType = archive_entry_filetype(entry)
            let isDir = (fileType & AE_IFDIR) == AE_IFDIR || pathStr.hasSuffix("/")
            let encrypted = archive_entry_is_encrypted(entry) != 0
            if encrypted { isEncrypted = true }
            let mode = archive_entry_mode(entry)
            let mtimeVal = archive_entry_mtime(entry)
            let date = mtimeVal > 0 ? Date(timeIntervalSince1970: TimeInterval(mtimeVal)) : nil
            
            let symlink: String? = {
                if let s = archive_entry_symlink(entry) {
                    return String(cString: s)
                }
                return nil
            }()
            
            entries.append(ArchiveEntryInfo(
                path: pathStr,
                uncompressedSize: max(0, size),
                compressedSize: nil,
                isDirectory: isDir,
                isEncrypted: encrypted,
                permissions: mode,
                modificationDate: date,
                symlinkTarget: symlink
            ))
            
            if !isDir && size > 0 {
                totalBytes += size
            }
        }
        
        let format = ArchiveFormat.detect(from: archiveURL)
        return ArchiveInfo(
            fileURL: archiveURL,
            format: format,
            totalEntries: entries.count,
            totalUncompressedSize: totalBytes,
            isEncrypted: isEncrypted,
            entries: entries
        )
    }
    
    public func extract(archiveURL: URL,
                        options: ExtractionOptions,
                        progress: @escaping (ExtractionProgress) -> Bool) throws -> ExtractionResult {
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw ExtractionError.fileNotFound(archiveURL)
        }
        
        let startTime = Date()
        let fm = FileManager.default
        
        // 1. Determine destination root
        var destDir = options.destinationDirectory
        if options.createEnclosingFolder {
            let folderName = archiveURL.deletingPathExtension().lastPathComponent
            destDir = destDir.appendingPathComponent(folderName, isDirectory: true)
        }
        
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true, attributes: nil)
        
        // 2. Pre-inspect for total byte count if possible
        var totalBytesExpected: Int64? = nil
        var totalEntriesExpected: Int? = nil
        if let info = try? inspect(archiveURL: archiveURL, password: options.password) {
            totalBytesExpected = info.totalUncompressedSize > 0 ? info.totalUncompressedSize : nil
            totalEntriesExpected = info.totalEntries > 0 ? info.totalEntries : nil
        }
        
        // 3. Initialize libarchive reader
        guard let a = archive_read_new() else {
            throw ExtractionError.generic("Không thể khởi tạo bộ đọc archive.")
        }
        defer { _ = archive_read_free(a) }
        
        _ = archive_read_support_filter_all(a)
        _ = archive_read_support_format_all(a)
        
        if let pw = options.password, !pw.isEmpty {
            _ = archive_read_add_passphrase(a, pw)
        }
        
        let openRes = archive_read_open_filename(a, archiveURL.path, 32768)
        guard openRes == ARCHIVE_OK else {
            let msg = archive_error_string(a).flatMap { String(cString: $0) } ?? "Lỗi \(openRes)"
            throw ExtractionError.corruptedArchive("Không thể mở file nén: \(msg)")
        }
        
        var currentConflictDecision: ConflictDecision? = nil
        var extractedFilesCount = 0
        var skippedFilesCount = 0
        var totalBytesExtracted: Int64 = 0
        var currentPartialURL: URL? = nil
        
        defer {
            // Clean up any remaining temporary partial file
            if let partial = currentPartialURL {
                try? fm.removeItem(at: partial)
            }
        }
        
        var entryPtr: ArchiveEntryPtr? = nil
        let archiveBasename = archiveURL.lastPathComponent
        
        while true {
            let r = archive_read_next_header(a, &entryPtr)
            if r == ARCHIVE_EOF {
                break
            }
            if r != ARCHIVE_OK {
                let msg = archive_error_string(a).flatMap { String(cString: $0) } ?? "Lỗi đọc header"
                if r == ARCHIVE_WARN {
                    // Warning only, continue
                } else {
                    let lower = msg.lowercased()
                    if lower.contains("passphrase") || lower.contains("password") || lower.contains("encrypt") {
                        throw ExtractionError.passwordRequired
                    }
                    throw ExtractionError.corruptedArchive(msg)
                }
            }
            
            guard let entry = entryPtr else { continue }
            
            let rawPath: String
            if let pUtf8 = archive_entry_pathname_utf8(entry) {
                rawPath = String(cString: pUtf8)
            } else if let p = archive_entry_pathname(entry) {
                rawPath = String(cString: p)
            } else {
                continue
            }
            
            // Validate against Zip-Slip
            let targetURL: URL
            do {
                targetURL = try PathSecurity.resolveSafeDestinationURL(for: rawPath, in: destDir)
            } catch {
                throw ExtractionError.pathSecurityViolation("Phát hiện đường dẫn không an toàn: \(rawPath)")
            }
            
            let fileType = archive_entry_filetype(entry)
            let isDir = (fileType & AE_IFDIR) == AE_IFDIR || rawPath.hasSuffix("/")
            
            // Check cancellation before processing entry
            let currentProgress = ExtractionProgress(
                archiveName: archiveBasename,
                currentFilePath: rawPath,
                extractedBytes: totalBytesExtracted,
                totalBytes: totalBytesExpected,
                extractedEntriesCount: extractedFilesCount,
                totalEntriesCount: totalEntriesExpected,
                elapsedTime: Date().timeIntervalSince(startTime)
            )
            
            if !progress(currentProgress) {
                throw ExtractionError.cancelled
            }
            
            if isDir {
                var isExistingDir: ObjCBool = false
                if fm.fileExists(atPath: targetURL.path, isDirectory: &isExistingDir) {
                    if !isExistingDir.boolValue {
                        try? fm.removeItem(at: targetURL)
                        try fm.createDirectory(at: targetURL, withIntermediateDirectories: true, attributes: nil)
                    }
                    // If directory already exists, preserve it and merge contents safely
                } else {
                    try fm.createDirectory(at: targetURL, withIntermediateDirectories: true, attributes: nil)
                }
                continue
            }
            
            // Symlink handling
            if (fileType & AE_IFLNK) == AE_IFLNK {
                if let symlinkTargetC = archive_entry_symlink(entry) {
                    let symlinkTarget = String(cString: symlinkTargetC)
                    // Check if parent directory exists
                    let parentDir = targetURL.deletingLastPathComponent()
                    try fm.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
                    
                    if fm.fileExists(atPath: targetURL.path) {
                        try? fm.removeItem(at: targetURL)
                    }
                    try? fm.createSymbolicLink(atPath: targetURL.path, withDestinationPath: symlinkTarget)
                }
                continue
            }
            
            // Ensure parent directory exists
            let parentDir = targetURL.deletingLastPathComponent()
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
            
            // Conflict handling
            var finalDestinationURL = targetURL
            var isTargetDirectory: ObjCBool = false
            if fm.fileExists(atPath: targetURL.path, isDirectory: &isTargetDirectory) {
                if isTargetDirectory.boolValue {
                    // Path is an existing directory: merge/preserve by auto-renaming the conflicting file
                    finalDestinationURL = generateNonConflictingURL(for: targetURL)
                } else {
                    let action: ConflictAction
                    if let activeDecision = currentConflictDecision, activeDecision.applyToAll {
                        action = activeDecision.action
                    } else {
                    switch options.conflictStrategy {
                    case .overwrite:
                        action = .overwrite
                    case .skip:
                        action = .skip
                    case .rename:
                        action = .rename
                    case .ask:
                        if let resolver = options.conflictResolver {
                            let decision = resolver(targetURL)
                            if decision.applyToAll {
                                currentConflictDecision = decision
                            }
                            action = decision.action
                        } else {
                            // If conflict cannot be prompted interactively, skip the file safely (Requirement 0.3)
                            action = .skip
                        }
                    }
                }
                
                switch action {
                case .cancel:
                    throw ExtractionError.cancelled
                case .skip:
                    skippedFilesCount += 1
                    continue
                case .rename:
                    finalDestinationURL = generateNonConflictingURL(for: targetURL)
                case .overwrite:
                    finalDestinationURL = targetURL
                }
                }
            }
            
            // Write to a temporary hidden partial file first
            let tempPartName = ".\(finalDestinationURL.lastPathComponent).\(UUID().uuidString.prefix(6)).upackx_part"
            let tempPartURL = parentDir.appendingPathComponent(tempPartName)
            currentPartialURL = tempPartURL
            
            // Open file descriptor for writing
            let fd = open(tempPartURL.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
            if fd < 0 {
                let errDesc = String(cString: strerror(errno))
                throw ExtractionError.writeFailed("Không thể tạo file tạm: \(tempPartURL.path) (\(errDesc))")
            }
            
            var writeSucceeded = false
            var entryBytesExtracted: Int64 = 0
            
            do {
                var buffPtr: UnsafeRawPointer? = nil
                var buffSize: Int = 0
                var fileOffset: Int64 = 0
                
                while true {
                    let dataRes = archive_read_data_block(a, &buffPtr, &buffSize, &fileOffset)
                    if dataRes == ARCHIVE_EOF {
                        break
                    }
                    if dataRes != ARCHIVE_OK {
                        let msg = archive_error_string(a).flatMap { String(cString: $0) } ?? "Lỗi đọc dữ liệu"
                        close(fd)
                        throw ExtractionError.corruptedArchive(msg)
                    }
                    
                    if buffSize > 0, let buf = buffPtr {
                        let written = write(fd, buf, buffSize)
                        if written != buffSize {
                            let errDesc = String(cString: strerror(errno))
                            close(fd)
                            throw ExtractionError.writeFailed("Ghi file thất bại: \(errDesc)")
                        }
                        
                        entryBytesExtracted += Int64(buffSize)
                        totalBytesExtracted += Int64(buffSize)
                    }
                    
                    // Periodically notify progress during large files
                    let inProgress = ExtractionProgress(
                        archiveName: archiveBasename,
                        currentFilePath: rawPath,
                        extractedBytes: totalBytesExtracted,
                        totalBytes: totalBytesExpected,
                        extractedEntriesCount: extractedFilesCount,
                        totalEntriesCount: totalEntriesExpected,
                        elapsedTime: Date().timeIntervalSince(startTime)
                    )
                    
                    if !progress(inProgress) {
                        close(fd)
                        throw ExtractionError.cancelled
                    }
                }
                
                close(fd)
                writeSucceeded = true
            } catch {
                close(fd)
                try? fm.removeItem(at: tempPartURL)
                currentPartialURL = nil
                throw error
            }
            
            if writeSucceeded {
                // Safely commit file with cloud/virtual mount fallback
                try GoogleDriveHelper.safeCommitFile(from: tempPartURL, to: finalDestinationURL)
                currentPartialURL = nil
                
                // Restore permissions if valid
                let mode = archive_entry_mode(entry)
                if mode != 0 {
                    chmod(finalDestinationURL.path, mode_t(mode & 0o777))
                }
                
                // Restore modification date if valid
                let mtimeVal = archive_entry_mtime(entry)
                if mtimeVal > 0 {
                    let mdate = Date(timeIntervalSince1970: TimeInterval(mtimeVal))
                    try? fm.setAttributes([.modificationDate: mdate], ofItemAtPath: finalDestinationURL.path)
                }
                
                extractedFilesCount += 1
            }
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        return ExtractionResult(
            archiveURL: archiveURL,
            destinationURL: destDir,
            extractedCount: extractedFilesCount,
            skippedCount: skippedFilesCount,
            totalBytes: totalBytesExtracted,
            elapsedTime: elapsed
        )
    }
    
    private func generateNonConflictingURL(for fileURL: URL) -> URL {
        let parent = fileURL.deletingLastPathComponent()
        let ext = fileURL.pathExtension
        let base = fileURL.deletingPathExtension().lastPathComponent
        
        var counter = 1
        var candidate: URL
        repeat {
            let newName = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            candidate = parent.appendingPathComponent(newName)
            counter += 1
        } while FileManager.default.fileExists(atPath: candidate.path)
        
        return candidate
    }
}
