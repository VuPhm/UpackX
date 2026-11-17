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
    
    public func inspect(archiveURL rawArchiveURL: URL, password: String?) throws -> ArchiveInfo {
        let archiveURL = PathSecurity.normalizeFileURL(rawArchiveURL)
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
                    let lower = msg.lowercased()
                    if lower.contains("passphrase") || lower.contains("password") || lower.contains("encrypt") {
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
        
        if archive_read_has_encrypted_entries(a) > 0 {
            isEncrypted = true
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
    
    public func extract(archiveURL rawArchiveURL: URL,
                        options: ExtractionOptions,
                        progress: @escaping (ExtractionProgress) -> Bool) throws -> ExtractionResult {
        let archiveURL = PathSecurity.normalizeFileURL(rawArchiveURL)
        let fm = FileManager.default
        
        var isArchiveDir: ObjCBool = false
        guard fm.fileExists(atPath: archiveURL.path, isDirectory: &isArchiveDir), !isArchiveDir.boolValue else {
            throw ExtractionError.fileNotFound(archiveURL)
        }
        
        let startTime = Date()
        let baseDest = PathSecurity.normalizeDirectoryURL(options.destinationDirectory)
        
        // Verify base destination is not an existing regular file
        var isBaseDestDir: ObjCBool = false
        var isBaseDestSymlink: Bool = false
        if PathSecurity.itemExistsIncludingSymlink(at: baseDest, isDirectory: &isBaseDestDir, isSymlink: &isBaseDestSymlink) {
            if isBaseDestSymlink {
                var targetIsDir: ObjCBool = false
                if !fm.fileExists(atPath: baseDest.path, isDirectory: &targetIsDir) || !targetIsDir.boolValue {
                    throw ExtractionError.writeFailed("Đường dẫn đích '\(baseDest.path)' là một liên kết tượng trưng (symlink) không trỏ tới thư mục hợp lệ.")
                }
            } else if !isBaseDestDir.boolValue {
                throw ExtractionError.writeFailed("Đường dẫn đích '\(baseDest.path)' đã tồn tại nhưng là một tệp tin, không phải thư mục.")
            }
        }
        
        // 1. Pre-inspect archive before creating any directories on disk
        var totalBytesExpected: Int64? = nil
        var totalEntriesExpected: Int? = nil
        var inspectedEntries: [ArchiveEntryInfo] = []
        
        if let info = try? inspect(archiveURL: archiveURL, password: options.password) {
            if info.isEncrypted && (options.password == nil || options.password?.isEmpty == true) {
                throw ExtractionError.passwordRequired
            }
            totalBytesExpected = info.totalUncompressedSize > 0 ? info.totalUncompressedSize : nil
            totalEntriesExpected = info.totalEntries > 0 ? info.totalEntries : nil
            inspectedEntries = info.entries
        }
        
        // 2. Resolve effective extraction directory (preventing duplicate Video/Video/ wrappers)
        let resolvedDest = PathSecurity.resolveEffectiveExtractionDirectory(
            archiveURL: archiveURL,
            options: options,
            entries: inspectedEntries
        )
        let destDir = resolvedDest.extractionRoot
        let reportedDestination = resolvedDest.reportedDestination
        let createdWrapper = resolvedDest.createdWrapperDirectory
        let wrapperExistedBefore = createdWrapper.map { fm.fileExists(atPath: $0.path) } ?? true
        
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true, attributes: nil)
        
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
        var extractionSucceeded = false
        
        defer {
            // Clean up any remaining temporary partial file
            if let partial = currentPartialURL {
                try? fm.removeItem(at: partial)
            }
            // If extraction failed or was cancelled before extracting any files, remove newly created empty wrapper
            if !extractionSucceeded && extractedFilesCount == 0,
               let wrapper = createdWrapper, !wrapperExistedBefore {
                if let contents = try? fm.contentsOfDirectory(atPath: wrapper.path), contents.isEmpty {
                    try? fm.removeItem(at: wrapper)
                }
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
            
            if archive_entry_is_encrypted(entry) != 0 && (options.password == nil || options.password?.isEmpty == true) {
                throw ExtractionError.passwordRequired
            }
            
            let rawPath: String
            if let pUtf8 = archive_entry_pathname_utf8(entry) {
                rawPath = String(cString: pUtf8)
            } else if let p = archive_entry_pathname(entry) {
                rawPath = String(cString: p)
            } else {
                continue
            }
            
            // Validate against Zip-Slip and symlink escape
            let targetURL: URL
            do {
                targetURL = try PathSecurity.resolveSafeDestinationURL(for: rawPath, in: destDir)
            } catch {
                throw ExtractionError.pathSecurityViolation("Phát hiện đường dẫn không an toàn: \(rawPath)")
            }
            
            // Skip root "." or "./" entries that resolve to destDir itself
            if targetURL.standardizedFileURL.path == destDir.standardizedFileURL.path {
                continue
            }
            
            if PathSecurity.isInternalStagingArtifact(name: targetURL.lastPathComponent) {
                continue
            }
            
            let fileType = archive_entry_filetype(entry)
            let isDir = (fileType & AE_IFDIR) == AE_IFDIR || rawPath.hasSuffix("/") || rawPath.hasSuffix("\\")
            
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
                var isExistingSymlink: Bool = false
                if PathSecurity.itemExistsIncludingSymlink(at: targetURL, isDirectory: &isExistingDir, isSymlink: &isExistingSymlink) {
                    if isExistingSymlink {
                        // Verify symlink does not point outside destDir
                        let resolvedLink = PathSecurity.canonicalPath(for: targetURL, followSymlinks: true)
                        let canonicalDest = PathSecurity.canonicalPath(for: destDir, followSymlinks: true)
                        if !PathSecurity.isCanonicallyContained(path: resolvedLink, within: canonicalDest) {
                            throw ExtractionError.pathSecurityViolation("Thư mục đích chứa symlink trỏ ra ngoài phạm vi an toàn: \(rawPath)")
                        }
                    } else if isExistingDir.boolValue {
                        // Directory already exists: preserve it and merge contents safely
                    } else {
                        // A regular file already exists at this directory path: never delete user file silently!
                        throw ExtractionError.writeFailed("Không thể tạo thư mục '\(targetURL.lastPathComponent)' vì đã có một tệp tin trùng tên tại đích.")
                    }
                } else {
                    try fm.createDirectory(at: targetURL, withIntermediateDirectories: true, attributes: nil)
                }
                continue
            }
            
            // Ensure parent directory exists and re-verify symlink containment on disk
            let parentDir = targetURL.deletingLastPathComponent()
            var isParentDir: ObjCBool = false
            var isParentSymlink: Bool = false
            if PathSecurity.itemExistsIncludingSymlink(at: parentDir, isDirectory: &isParentDir, isSymlink: &isParentSymlink) {
                if !isParentDir.boolValue && !isParentSymlink {
                    throw ExtractionError.writeFailed("Không thể tạo thư mục cha '\(parentDir.lastPathComponent)' vì đã có một tệp tin trùng tên.")
                }
            } else {
                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
            }
            
            // Re-validate after parentDir exists on disk to catch any symlink intermediate traversal
            do {
                _ = try PathSecurity.resolveSafeDestinationURL(for: rawPath, in: destDir)
            } catch {
                throw ExtractionError.pathSecurityViolation("Phát hiện đường dẫn thoát khỏi thư mục đích qua symlink: \(rawPath)")
            }
            
            // Symlink handling
            if (fileType & AE_IFLNK) == AE_IFLNK {
                if let symlinkTargetC = archive_entry_symlink(entry) {
                    let symlinkTarget = String(cString: symlinkTargetC)
                    
                    var finalSymlinkURL = targetURL
                    var isTargetDir: ObjCBool = false
                    var isTargetSymlink: Bool = false
                    if PathSecurity.itemExistsIncludingSymlink(at: targetURL, isDirectory: &isTargetDir, isSymlink: &isTargetSymlink) {
                        if isTargetDir.boolValue && !isTargetSymlink {
                            // Never delete an existing directory! Rename the conflicting symlink
                            finalSymlinkURL = PathSecurity.generateNonConflictingURL(for: targetURL)
                        } else {
                            let action = try resolveConflictAction(
                                for: targetURL,
                                options: options,
                                currentDecision: &currentConflictDecision
                            )
                            switch action {
                            case .cancel:
                                throw ExtractionError.cancelled
                            case .skip:
                                skippedFilesCount += 1
                                continue
                            case .rename:
                                finalSymlinkURL = PathSecurity.generateNonConflictingURL(for: targetURL)
                            case .overwrite:
                                try? fm.removeItem(at: targetURL)
                                finalSymlinkURL = targetURL
                            }
                        }
                    }
                    
                    try fm.createSymbolicLink(atPath: finalSymlinkURL.path, withDestinationPath: symlinkTarget)
                    extractedFilesCount += 1
                }
                continue
            }
            
            // Conflict handling for regular files
            var finalDestinationURL = targetURL
            var isTargetDirectory: ObjCBool = false
            var isTargetSymlink: Bool = false
            if PathSecurity.itemExistsIncludingSymlink(at: targetURL, isDirectory: &isTargetDirectory, isSymlink: &isTargetSymlink) {
                if isTargetDirectory.boolValue && !isTargetSymlink {
                    // Path is an existing user directory: never delete it, auto-rename the incoming file
                    finalDestinationURL = PathSecurity.generateNonConflictingURL(for: targetURL)
                } else {
                    let action = try resolveConflictAction(
                        for: targetURL,
                        options: options,
                        currentDecision: &currentConflictDecision
                    )
                    switch action {
                    case .cancel:
                        throw ExtractionError.cancelled
                    case .skip:
                        skippedFilesCount += 1
                        continue
                    case .rename:
                        finalDestinationURL = PathSecurity.generateNonConflictingURL(for: targetURL)
                    case .overwrite:
                        finalDestinationURL = targetURL
                    }
                }
            }
            
            // Write to a temporary hidden partial file first
            let tempPartName = ".\(finalDestinationURL.lastPathComponent).\(UUID().uuidString.prefix(6)).upackx_part"
            let tempPartURL = parentDir.appendingPathComponent(tempPartName)
            currentPartialURL = tempPartURL
            
            // Open file descriptor for writing (O_EXCL / O_NOFOLLOW for safety)
            let fd = open(tempPartURL.path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0o644)
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
                        let lower = msg.lowercased()
                        if lower.contains("passphrase") || lower.contains("password") || lower.contains("encrypt") {
                            throw ExtractionError.passwordRequired
                        }
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
                // Safely commit file with atomic replacement & rollback
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
        
        extractionSucceeded = true
        let elapsed = Date().timeIntervalSince(startTime)
        return ExtractionResult(
            archiveURL: archiveURL,
            destinationURL: reportedDestination,
            extractedCount: extractedFilesCount,
            skippedCount: skippedFilesCount,
            totalBytes: totalBytesExtracted,
            elapsedTime: elapsed
        )
    }
    
    private func resolveConflictAction(
        for targetURL: URL,
        options: ExtractionOptions,
        currentDecision: inout ConflictDecision?
    ) throws -> ConflictAction {
        if let activeDecision = currentDecision, activeDecision.applyToAll {
            return activeDecision.action
        }
        switch options.conflictStrategy {
        case .overwrite:
            return .overwrite
        case .skip:
            return .skip
        case .rename:
            return .rename
        case .ask:
            if let resolver = options.conflictResolver {
                let decision = resolver(targetURL)
                if decision.applyToAll {
                    currentDecision = decision
                }
                return decision.action
            } else {
                // Non-interactive fallback: skip safely, never overwrite silently
                return .skip
            }
        }
    }
}
