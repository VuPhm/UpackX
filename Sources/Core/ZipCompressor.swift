import Foundation

// MARK: - Fault Injection for Hardened Testing
#if DEBUG || canImport(Foundation)
public struct ZipCompressorFaults {
    public static var failHeaderWrite: Bool = false
    public static var failDataWrite: Bool = false
    public static var failClose: Bool = false
    public static var simulateDiskFull: Bool = false
    public static var simulateCommitFailure: Bool = false
    
    public static func reset() {
        failHeaderWrite = false
        failDataWrite = false
        failClose = false
        simulateDiskFull = false
        simulateCommitFailure = false
    }
}
#endif

public final class ZipCompressor {
    public static let shared = ZipCompressor()
    
    private struct CompressItem {
        let sourceURL: URL
        let archivePath: String
        let isDirectory: Bool
        let isSymlink: Bool
        let symlinkTarget: String?
        let fileSize: Int64
        let modificationDate: Date
        let posixPermissions: UInt16
    }
    
    public init() {}
    
    /// Compresses one or more source files/directories into a ZIP archive
    @discardableResult
    public func compress(
        sources rawSources: [URL],
        options: CompressionOptions,
        progress: ((CompressionProgress) -> Bool)? = nil,
        completion: @escaping (Result<CompressionResult, CompressionError>) -> Void
    ) -> Bool {
        let sources = Self.normalizeAndDeduplicateSources(rawSources)
        guard !sources.isEmpty else {
            completion(.failure(.emptySource))
            return false
        }
        
        let startTime = Date()
        let originalDestinationURL = PathSecurity.normalizeFileURL(options.destinationURL)
        var finalDestinationURL = originalDestinationURL
        let fm = FileManager.default
        
        // 1. Conflict resolution if destination already exists (including symlinks)
        var isExistingDestDir: ObjCBool = false
        var isExistingDestSymlink: Bool = false
        if PathSecurity.itemExistsIncludingSymlink(at: finalDestinationURL, isDirectory: &isExistingDestDir, isSymlink: &isExistingDestSymlink) {
            if isExistingDestDir.boolValue && !isExistingDestSymlink {
                // Destination path is an existing real directory: NEVER overwrite or delete a user directory!
                if options.conflictStrategy == .overwrite {
                    completion(.failure(.cannotCreateArchive("Đường dẫn đích '\(finalDestinationURL.path)' là một thư mục đang tồn tại, không thể ghi đè bằng file nén.")))
                    return false
                } else {
                    finalDestinationURL = PathSecurity.generateNonConflictingURL(for: finalDestinationURL)
                }
            } else {
                var strategy = options.conflictStrategy
                if strategy == .ask {
                    if let resolver = options.conflictResolver {
                        let decision = resolver(finalDestinationURL)
                        switch decision.action {
                        case .overwrite:
                            strategy = .overwrite
                        case .rename:
                            strategy = .rename
                        case .skip:
                            strategy = .skip
                        case .cancel:
                            completion(.failure(.cancelled))
                            return false
                        }
                    } else {
                        strategy = .rename
                    }
                }
                
                switch strategy {
                case .overwrite:
                    break // Will replace atomically on completion
                case .rename:
                    finalDestinationURL = PathSecurity.generateNonConflictingURL(for: finalDestinationURL)
                case .skip:
                    let result = CompressionResult(
                        destinationURL: finalDestinationURL,
                        totalItemsCompressed: 0,
                        totalBytesProcessed: 0,
                        archiveSize: 0,
                        elapsedTime: 0
                    )
                    completion(.success(result))
                    return true
                case .ask:
                    finalDestinationURL = PathSecurity.generateNonConflictingURL(for: finalDestinationURL)
                }
            }
        }
        
        let destDir = finalDestinationURL.deletingLastPathComponent()
        
        // Validate that destDir is not an existing regular file
        var isDestParentDir: ObjCBool = false
        var isDestParentSymlink: Bool = false
        if PathSecurity.itemExistsIncludingSymlink(at: destDir, isDirectory: &isDestParentDir, isSymlink: &isDestParentSymlink) {
            if isDestParentSymlink {
                var resolvedIsDir: ObjCBool = false
                if !fm.fileExists(atPath: destDir.path, isDirectory: &resolvedIsDir) || !resolvedIsDir.boolValue {
                    completion(.failure(.cannotCreateArchive("Thư mục lưu '\(destDir.path)' là một symlink không hợp lệ.")))
                    return false
                }
            } else if !isDestParentDir.boolValue {
                completion(.failure(.cannotCreateArchive("Đường dẫn thư mục lưu '\(destDir.path)' là một tệp tin, không phải thư mục.")))
                return false
            }
        }
        
        let destDirExistedBefore = fm.fileExists(atPath: destDir.path)
        let tempFileName = ".upackx_compress_" + UUID().uuidString + ".tmp"
        let tempURL = destDir.appendingPathComponent(tempFileName)
        
        let canonicalOriginalDest = PathSecurity.canonicalPath(for: originalDestinationURL, followSymlinks: false).precomposedStringWithCanonicalMapping
        let canonicalDest = PathSecurity.canonicalPath(for: finalDestinationURL, followSymlinks: false).precomposedStringWithCanonicalMapping
        let canonicalTemp = PathSecurity.canonicalPath(for: tempURL, followSymlinks: false).precomposedStringWithCanonicalMapping
        let excludedCanonicalPaths: Set<String> = [canonicalOriginalDest, canonicalDest, canonicalTemp]
        
        // 2. Scan and collect items to archive BEFORE creating destDir on disk.
        // This guarantees that if destDir is a new subfolder inside a source directory, it is never self-included,
        // and if source validation fails, no unwanted destination directory is created.
        var itemsToCompress: [CompressItem] = []
        var totalBytesToProcess: Int64 = 0
        var usedRootNames: Set<String> = []
        
        for source in sources {
            var isSourceDir: ObjCBool = false
            var isSourceSymlink: Bool = false
            guard PathSecurity.itemExistsIncludingSymlink(at: source, isDirectory: &isSourceDir, isSymlink: &isSourceSymlink) else {
                completion(.failure(.sourceNotFound(source.path)))
                return false
            }
            
            // If source is a symlink to a directory, check if user selected a directory symlink directly
            var treatAsDirectory = isSourceDir.boolValue
            if isSourceSymlink {
                // For a top-level symlink selected directly as a source:
                // Only treat as directory if it's a real directory, otherwise archive the symlink or check readability
                treatAsDirectory = false
            }
            
            if !isSourceSymlink {
                guard fm.isReadableFile(atPath: source.path) else {
                    completion(.failure(.permissionDenied(source.path)))
                    return false
                }
            }
            
            let baseItemName = Self.uniqueTopLevelArchiveName(for: source.lastPathComponent, usedNames: &usedRootNames)
            
            do {
                if treatAsDirectory {
                    try collectItems(
                        from: source,
                        relativePrefix: baseItemName,
                        excludedCanonicalPaths: excludedCanonicalPaths,
                        into: &itemsToCompress,
                        totalBytes: &totalBytesToProcess
                    )
                } else {
                    if let item = try makeCompressItem(
                        for: source,
                        archivePath: baseItemName,
                        excludedCanonicalPaths: excludedCanonicalPaths
                    ) {
                        itemsToCompress.append(item)
                        totalBytesToProcess += item.fileSize
                    }
                }
            } catch let error as CompressionError {
                completion(.failure(error))
                return false
            } catch {
                completion(.failure(.traversalFailed(path: source.path, reason: error.localizedDescription)))
                return false
            }
        }
        
        guard !itemsToCompress.isEmpty else {
            completion(.failure(.emptySource))
            return false
        }
        
        // 3. Prepare output directory now that sources are validated and collected
        if !fm.fileExists(atPath: destDir.path) {
            do {
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            } catch {
                completion(.failure(.cannotCreateArchive("Không thể tạo thư mục đích: \(error.localizedDescription)")))
                return false
            }
        }
        
        let createdDestDirToClean: URL? = destDirExistedBefore ? nil : destDir
        
        // 4. Initialize libarchive writer
        guard let a = archive_write_new() else {
            cleanup(tempURL: tempURL, createdDestDir: createdDestDirToClean)
            completion(.failure(.cannotCreateArchive("Không thể cấp phát bộ nhớ cho archive writer.")))
            return false
        }
        
        guard archive_write_set_format_zip(a) == ARCHIVE_OK else {
            _ = archive_write_free(a)
            cleanup(tempURL: tempURL, createdDestDir: createdDestDirToClean)
            completion(.failure(.cannotCreateArchive("Không thể thiết lập định dạng ZIP.")))
            return false
        }
        
        let optStr = "zip:compression-level=\(options.compressionLevel.libarchiveLevel)"
        let optRes = archive_write_set_options(a, optStr)
        if optRes < ARCHIVE_WARN {
            let errString = archive_error_string(a).map { String(cString: $0) } ?? "Lỗi thiết lập tùy chọn ZIP"
            _ = archive_write_free(a)
            cleanup(tempURL: tempURL, createdDestDir: createdDestDirToClean)
            completion(.failure(.cannotCreateArchive(errString)))
            return false
        }
        
        guard archive_write_open_filename(a, tempURL.path) == ARCHIVE_OK else {
            let errString = archive_error_string(a).map { String(cString: $0) } ?? "Lỗi mở tệp lưu trữ"
            _ = archive_write_free(a)
            cleanup(tempURL: tempURL, createdDestDir: createdDestDirToClean)
            completion(.failure(.cannotCreateArchive(errString)))
            return false
        }
        
        // 5. Streaming Compression Loop
        var processedBytes: Int64 = 0
        var processedFiles: Int = 0
        let totalFiles = itemsToCompress.count
        var isCancelled = false
        var writeLoopError: CompressionError? = nil
        
        let bufferSize = 65536 // 64 KB streaming buffer
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        
        for item in itemsToCompress {
            if isCancelled { break }
            
            // Check progress & cancellation
            let prog = CompressionProgress(
                currentItemName: item.archivePath,
                processedFiles: processedFiles,
                totalFiles: totalFiles,
                processedBytes: processedBytes,
                totalBytes: totalBytesToProcess
            )
            if let progressCallback = progress, !progressCallback(prog) {
                isCancelled = true
                break
            }
            
            guard let entry = archive_entry_new() else {
                writeLoopError = .cannotCreateArchive("Không thể khởi tạo entry cho: \(item.archivePath)")
                break
            }
            
            archive_entry_set_pathname_utf8(entry, item.archivePath)
            archive_entry_set_mtime(entry, Int(item.modificationDate.timeIntervalSince1970), 0)
            archive_entry_set_perm(entry, item.posixPermissions)
            
            // Fault injection hook
            #if DEBUG || canImport(Foundation)
            if ZipCompressorFaults.failHeaderWrite {
                archive_entry_free(entry)
                writeLoopError = .writeFailed("Fault injection: Header write failed for \(item.archivePath)")
                break
            }
            #endif
            
            if item.isSymlink, let target = item.symlinkTarget {
                archive_entry_set_filetype(entry, AE_IFLNK)
                archive_entry_set_symlink(entry, target)
                let headerRes = archive_write_header(a, entry)
                archive_entry_free(entry)
                guard headerRes == ARCHIVE_OK || headerRes == ARCHIVE_WARN else {
                    let errStr = archive_error_string(a).map { String(cString: $0) } ?? "Lỗi ghi header symlink"
                    writeLoopError = .writeFailed("Ghi header symlink '\(item.archivePath)' thất bại: \(errStr)")
                    break
                }
                processedFiles += 1
                continue
            }
            
            if item.isDirectory {
                archive_entry_set_filetype(entry, AE_IFDIR)
                archive_entry_set_size(entry, 0)
                let headerRes = archive_write_header(a, entry)
                archive_entry_free(entry)
                guard headerRes == ARCHIVE_OK || headerRes == ARCHIVE_WARN else {
                    let errStr = archive_error_string(a).map { String(cString: $0) } ?? "Lỗi ghi header thư mục"
                    writeLoopError = .writeFailed("Ghi header thư mục '\(item.archivePath)' thất bại: \(errStr)")
                    break
                }
                processedFiles += 1
                continue
            }
            
            // Regular file entry
            archive_entry_set_filetype(entry, AE_IFREG)
            archive_entry_set_size(entry, item.fileSize)
            
            let headerRes = archive_write_header(a, entry)
            archive_entry_free(entry)
            
            guard headerRes == ARCHIVE_OK || headerRes == ARCHIVE_WARN else {
                let errStr = archive_error_string(a).map { String(cString: $0) } ?? "Lỗi ghi header tệp"
                writeLoopError = .writeFailed("Ghi header tệp '\(item.archivePath)' thất bại: \(errStr)")
                break
            }
            
            // Stream file data in chunks
            if item.fileSize > 0 {
                let fd = open(item.sourceURL.path, O_RDONLY)
                guard fd >= 0 else {
                    let errStr = String(cString: strerror(errno))
                    writeLoopError = .sourceUnreadable(path: item.sourceURL.path, reason: errStr)
                    break
                }
                
                var bytesWrittenForEntry: Int64 = 0
                var readErrorOccurred = false
                
                while bytesWrittenForEntry < item.fileSize {
                    let toRead = min(Int64(bufferSize), item.fileSize - bytesWrittenForEntry)
                    let bytesRead = read(fd, buffer, Int(toRead))
                    
                    if bytesRead < 0 {
                        if errno == EINTR {
                            continue // Interrupted system call, retry
                        }
                        let errStr = String(cString: strerror(errno))
                        writeLoopError = .sourceUnreadable(path: item.sourceURL.path, reason: errStr)
                        readErrorOccurred = true
                        break
                    }
                    
                    if bytesRead == 0 {
                        // Premature EOF: file was truncated during compression
                        writeLoopError = .entrySizeMismatch(
                            path: item.sourceURL.path,
                            declared: item.fileSize,
                            actual: bytesWrittenForEntry
                        )
                        readErrorOccurred = true
                        break
                    }
                    
                    // Fault injection
                    #if DEBUG || canImport(Foundation)
                    if ZipCompressorFaults.failDataWrite {
                        writeLoopError = .writeFailed("Fault injection: Write data failure simulated.")
                        readErrorOccurred = true
                        break
                    }
                    if ZipCompressorFaults.simulateDiskFull {
                        writeLoopError = .diskFull("Fault injection: No space left on device.")
                        readErrorOccurred = true
                        break
                    }
                    #endif
                    
                    // Write buffer to archive handling partial writes
                    var writtenTotal = 0
                    var writeErrorOccurred = false
                    while writtenTotal < bytesRead {
                        let writeChunk = buffer.advanced(by: writtenTotal)
                        let writeLength = bytesRead - writtenTotal
                        let nWritten = archive_write_data(a, writeChunk, writeLength)
                        
                        if nWritten <= 0 {
                            let errStr = archive_error_string(a).map { String(cString: $0) } ?? "Lỗi ghi dữ liệu libarchive"
                            writeLoopError = .writeFailed("Ghi tệp '\(item.archivePath)' thất bại: \(errStr)")
                            writeErrorOccurred = true
                            break
                        }
                        writtenTotal += nWritten
                    }
                    
                    if writeErrorOccurred {
                        readErrorOccurred = true
                        break
                    }
                    
                    bytesWrittenForEntry += Int64(bytesRead)
                    processedBytes += Int64(bytesRead)
                    
                    let chunkProg = CompressionProgress(
                        currentItemName: item.archivePath,
                        processedFiles: processedFiles,
                        totalFiles: totalFiles,
                        processedBytes: processedBytes,
                        totalBytes: totalBytesToProcess
                    )
                    if let progressCallback = progress, !progressCallback(chunkProg) {
                        isCancelled = true
                        break
                    }
                }
                
                // Probe if file grew beyond declared size
                if !readErrorOccurred && !isCancelled {
                    let probeBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
                    let probeRead = read(fd, probeBuffer, 1)
                    probeBuffer.deallocate()
                    if probeRead > 0 {
                        writeLoopError = .entrySizeMismatch(
                            path: item.sourceURL.path,
                            declared: item.fileSize,
                            actual: bytesWrittenForEntry + Int64(probeRead)
                        )
                        readErrorOccurred = true
                    }
                }
                
                close(fd)
                
                if readErrorOccurred || isCancelled {
                    break
                }
            }
            
            processedFiles += 1
        }
        
        // 6. Close and finalize archive
        let closeRes = archive_write_close(a)
        _ = archive_write_free(a)
        
        if isCancelled {
            cleanup(tempURL: tempURL, createdDestDir: createdDestDirToClean)
            completion(.failure(.cancelled))
            return false
        }
        
        if let err = writeLoopError {
            cleanup(tempURL: tempURL, createdDestDir: createdDestDirToClean)
            completion(.failure(err))
            return false
        }
        
        #if DEBUG || canImport(Foundation)
        if ZipCompressorFaults.failClose {
            cleanup(tempURL: tempURL, createdDestDir: createdDestDirToClean)
            completion(.failure(.archiveCloseFailed("Fault injection: Archive close failure simulated.")))
            return false
        }
        #endif
        
        guard closeRes == ARCHIVE_OK || closeRes == ARCHIVE_WARN else {
            cleanup(tempURL: tempURL, createdDestDir: createdDestDirToClean)
            completion(.failure(.archiveCloseFailed("Lỗi ghi cấu trúc cuối của file ZIP (closeRes=\(closeRes)).")))
            return false
        }
        
        // Ensure all planned files were compressed
        guard processedFiles == totalFiles else {
            cleanup(tempURL: tempURL, createdDestDir: createdDestDirToClean)
            completion(.failure(.writeFailed("Số lượng tệp được nén (\(processedFiles)) không khớp với kế hoạch (\(totalFiles)).")))
            return false
        }
        
        // 7. Atomic Commit & Data Safety with Rollback Strategy
        guard fm.fileExists(atPath: tempURL.path) else {
            cleanup(tempURL: tempURL, createdDestDir: createdDestDirToClean)
            completion(.failure(.writeFailed("Tệp nén tạm thời không tồn tại sau khi nén.")))
            return false
        }
        
        let tempSize = (try? fm.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0
        guard tempSize > 0 else {
            cleanup(tempURL: tempURL, createdDestDir: createdDestDirToClean)
            completion(.failure(.writeFailed("Tệp nén tạo ra rỗng (0 bytes).")))
            return false
        }
        
        #if DEBUG || canImport(Foundation)
        if ZipCompressorFaults.simulateCommitFailure {
            cleanup(tempURL: tempURL, createdDestDir: createdDestDirToClean)
            completion(.failure(.commitFailed("Fault injection: Simulated atomic commit failure.")))
            return false
        }
        #endif
        
        do {
            try commitArchive(from: tempURL, to: finalDestinationURL, fileManager: fm)
        } catch {
            cleanup(tempURL: tempURL, createdDestDir: createdDestDirToClean)
            completion(.failure(.commitFailed(error.localizedDescription)))
            return false
        }
        
        let archiveSize = (try? fm.attributesOfItem(atPath: finalDestinationURL.path)[.size] as? Int64) ?? tempSize
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        let result = CompressionResult(
            destinationURL: finalDestinationURL,
            totalItemsCompressed: processedFiles,
            totalBytesProcessed: processedBytes,
            archiveSize: archiveSize,
            elapsedTime: elapsedTime
        )
        
        completion(.success(result))
        return true
    }
    
    // MARK: - Source Deduplication & Top-Level Naming
    
    private static func normalizeAndDeduplicateSources(_ rawSources: [URL]) -> [URL] {
        var uniqueSources: [URL] = []
        var seenCanonical: Set<String> = []
        
        for raw in rawSources {
            let normalized = PathSecurity.normalizeFileURL(raw)
            let canonical = PathSecurity.canonicalPath(for: normalized, followSymlinks: false).precomposedStringWithCanonicalMapping
            if !seenCanonical.contains(canonical) {
                seenCanonical.insert(canonical)
                uniqueSources.append(normalized)
            }
        }
        
        // Filter out any source that is strictly inside another directory in uniqueSources
        var dirCanonicals: [String] = []
        for src in uniqueSources {
            var isDir: ObjCBool = false
            var isLink: Bool = false
            if PathSecurity.itemExistsIncludingSymlink(at: src, isDirectory: &isDir, isSymlink: &isLink),
               isDir.boolValue && !isLink {
                dirCanonicals.append(PathSecurity.canonicalPath(for: src, followSymlinks: true).precomposedStringWithCanonicalMapping)
            }
        }
        
        return uniqueSources.filter { src in
            let itemCanonical = PathSecurity.canonicalPath(for: src, followSymlinks: false).precomposedStringWithCanonicalMapping
            for dirCan in dirCanonicals {
                if itemCanonical != dirCan && PathSecurity.isCanonicallyContained(path: itemCanonical, within: dirCan) {
                    return false
                }
            }
            return true
        }
    }
    
    private static func uniqueTopLevelArchiveName(for rawName: String, usedNames: inout Set<String>) -> String {
        let baseName = rawName.isEmpty ? "Item" : rawName
        var candidate = baseName
        var counter = 1
        while usedNames.contains(candidate.precomposedStringWithCanonicalMapping.lowercased()) {
            let ext = (baseName as NSString).pathExtension
            let stem = (baseName as NSString).deletingPathExtension
            if ext.isEmpty || stem.isEmpty {
                candidate = "\(baseName) (\(counter))"
            } else {
                candidate = "\(stem) (\(counter)).\(ext)"
            }
            counter += 1
        }
        usedNames.insert(candidate.precomposedStringWithCanonicalMapping.lowercased())
        return candidate
    }
    
    // MARK: - Atomic Commit & Rollback
    
    private func commitArchive(from tempURL: URL, to destURL: URL, fileManager fm: FileManager) throws {
        var isExistingDir: ObjCBool = false
        var isExistingSymlink: Bool = false
        let exists = PathSecurity.itemExistsIncludingSymlink(at: destURL, isDirectory: &isExistingDir, isSymlink: &isExistingSymlink)
        
        if exists && isExistingDir.boolValue && !isExistingSymlink {
            throw CompressionError.commitFailed("Đường dẫn đích '\(destURL.path)' là một thư mục đang tồn tại.")
        }
        
        if !exists {
            // Destination does not exist: direct atomic move
            try fm.moveItem(at: tempURL, to: destURL)
            return
        }
        
        // Destination ALREADY exists: Safe atomic replace with backup and rollback
        // Attempt 1: Native filesystem atomic replacement (only when not a symlink)
        if !isExistingSymlink {
            do {
                var resultingURL: NSURL? = nil
                try fm.replaceItem(
                    at: destURL,
                    withItemAt: tempURL,
                    backupItemName: nil,
                    options: [.withoutDeletingBackupItem],
                    resultingItemURL: &resultingURL
                )
                return
            } catch {
                // replaceItem failed (e.g. Google Drive File Provider, network drive, FAT32/exFAT).
                // Fallback to Attempt 2: Staged Backup & Rollback
            }
        }
        
        let destDir = destURL.deletingLastPathComponent()
        let backupFileName = ".upackx_backup_" + UUID().uuidString + ".tmp"
        let backupURL = destDir.appendingPathComponent(backupFileName)
        
        // Step 1: Move existing destination to backup
        try fm.moveItem(at: destURL, to: backupURL)
        
        // Step 2: Move new temp file to destination
        do {
            try fm.moveItem(at: tempURL, to: destURL)
            // Step 3: Success! Safely remove the backup
            try? fm.removeItem(at: backupURL)
        } catch {
            // CRITICAL ROLLBACK: Restore original file from backup!
            try? fm.moveItem(at: backupURL, to: destURL)
            throw error
        }
    }
    
    // MARK: - Directory Scanning & Traversal
    
    private func collectItems(
        from directoryURL: URL,
        relativePrefix: String,
        excludedCanonicalPaths: Set<String>,
        into items: inout [CompressItem],
        totalBytes: inout Int64
    ) throws {
        let fm = FileManager.default
        let canonicalDirPath = PathSecurity.canonicalPath(for: directoryURL, followSymlinks: true)
        
        guard fm.isReadableFile(atPath: directoryURL.path) else {
            throw CompressionError.permissionDenied(directoryURL.path)
        }
        
        // 1. Add directory entry itself
        let dirAttributes = (try? fm.attributesOfItem(atPath: canonicalDirPath)) ?? [:]
        let dirPerm = (dirAttributes[.posixPermissions] as? UInt16) ?? 0o755
        let dirMtime = (dirAttributes[.modificationDate] as? Date) ?? Date()
        
        let cleanPrefix = relativePrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalizedDirPrefix = cleanPrefix + "/"
        items.append(CompressItem(
            sourceURL: directoryURL,
            archivePath: normalizedDirPrefix,
            isDirectory: true,
            isSymlink: false,
            symlinkTarget: nil,
            fileSize: 0,
            modificationDate: dirMtime,
            posixPermissions: dirPerm
        ))
        
        // 2. Enumerate directory contents with strict error propagation
        var traversalError: Error? = nil
        
        guard let enumerator = fm.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey],
            options: [],
            errorHandler: { url, error in
                traversalError = error
                return false // Stop traversal immediately on any error!
            }
        ) else {
            throw CompressionError.traversalFailed(path: directoryURL.path, reason: "Không thể mở bộ duyệt thư mục.")
        }
        
        for case let fileURL as URL in enumerator {
            if let err = traversalError {
                throw CompressionError.traversalFailed(path: fileURL.path, reason: err.localizedDescription)
            }
            
            let itemName = fileURL.lastPathComponent
            if PathSecurity.isInternalStagingArtifact(name: itemName) {
                continue
            }
            
            var st = stat()
            let hasStat = (lstat(fileURL.path, &st) == 0)
            let isLink = hasStat ? ((st.st_mode & S_IFMT) == S_IFLNK) : ((try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false)
            
            if !isLink {
                // Check readability of regular file or directory
                guard fm.isReadableFile(atPath: fileURL.path) else {
                    throw CompressionError.permissionDenied(fileURL.path)
                }
            }
            
            let canonicalItem = PathSecurity.canonicalPath(for: fileURL, followSymlinks: false).precomposedStringWithCanonicalMapping
            // Self-inclusion check: do not include destination archive or temp file
            if excludedCanonicalPaths.contains(canonicalItem) {
                continue
            }
            
            guard let relativePathFromDir = PathSecurity.relativePath(of: fileURL, from: directoryURL),
                  !relativePathFromDir.isEmpty else {
                continue
            }
            
            let archiveEntryPath = normalizedDirPrefix + relativePathFromDir
            
            // Validate POSIX file types: reject sockets, FIFOs, character/block devices
            if hasStat {
                let fileType = st.st_mode & S_IFMT
                if fileType == S_IFSOCK || fileType == S_IFIFO || fileType == S_IFCHR || fileType == S_IFBLK {
                    throw CompressionError.unsupportedFileType(path: fileURL.path, type: fileTypeDescription(mode: st.st_mode))
                }
            }
            
            let isDir = hasStat ? ((st.st_mode & S_IFMT) == S_IFDIR) : ((try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false)
            
            if isLink {
                let target = try? fm.destinationOfSymbolicLink(atPath: fileURL.path)
                let attrs = (try? fm.attributesOfItem(atPath: fileURL.path)) ?? [:]
                let mtime = (attrs[.modificationDate] as? Date) ?? Date()
                items.append(CompressItem(
                    sourceURL: fileURL,
                    archivePath: archiveEntryPath,
                    isDirectory: false,
                    isSymlink: true,
                    symlinkTarget: target,
                    fileSize: 0,
                    modificationDate: mtime,
                    posixPermissions: 0o777
                ))
            } else if isDir {
                let attrs = (try? fm.attributesOfItem(atPath: fileURL.path)) ?? [:]
                let perm = (attrs[.posixPermissions] as? UInt16) ?? 0o755
                let mtime = (attrs[.modificationDate] as? Date) ?? Date()
                items.append(CompressItem(
                    sourceURL: fileURL,
                    archivePath: archiveEntryPath.hasSuffix("/") ? archiveEntryPath : (archiveEntryPath + "/"),
                    isDirectory: true,
                    isSymlink: false,
                    symlinkTarget: nil,
                    fileSize: 0,
                    modificationDate: mtime,
                    posixPermissions: perm
                ))
            } else {
                let attrs = (try? fm.attributesOfItem(atPath: fileURL.path)) ?? [:]
                let size = (attrs[.size] as? Int64) ?? 0
                let perm = (attrs[.posixPermissions] as? UInt16) ?? 0o644
                let mtime = (attrs[.modificationDate] as? Date) ?? Date()
                items.append(CompressItem(
                    sourceURL: fileURL,
                    archivePath: archiveEntryPath,
                    isDirectory: false,
                    isSymlink: false,
                    symlinkTarget: nil,
                    fileSize: size,
                    modificationDate: mtime,
                    posixPermissions: perm
                ))
                totalBytes += size
            }
        }
        
        if let err = traversalError {
            throw CompressionError.traversalFailed(path: directoryURL.path, reason: err.localizedDescription)
        }
    }
    
    private func makeCompressItem(
        for fileURL: URL,
        archivePath: String,
        excludedCanonicalPaths: Set<String>
    ) throws -> CompressItem? {
        if PathSecurity.isInternalStagingArtifact(name: fileURL.lastPathComponent) {
            return nil
        }
        
        let canonicalItem = PathSecurity.canonicalPath(for: fileURL, followSymlinks: false).precomposedStringWithCanonicalMapping
        if excludedCanonicalPaths.contains(canonicalItem) {
            return nil
        }
        
        let fm = FileManager.default
        var st = stat()
        let hasStat = (lstat(fileURL.path, &st) == 0)
        let isLink = hasStat ? ((st.st_mode & S_IFMT) == S_IFLNK) : ((try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false)
        
        if !isLink {
            guard fm.isReadableFile(atPath: fileURL.path) else {
                throw CompressionError.permissionDenied(fileURL.path)
            }
        }
        
        // Validate POSIX file types: reject sockets, FIFOs, character/block devices
        if hasStat {
            let fileType = st.st_mode & S_IFMT
            if fileType == S_IFSOCK || fileType == S_IFIFO || fileType == S_IFCHR || fileType == S_IFBLK {
                throw CompressionError.unsupportedFileType(path: fileURL.path, type: fileTypeDescription(mode: st.st_mode))
            }
        }
        
        let attrs = (try? fm.attributesOfItem(atPath: fileURL.path)) ?? [:]
        let mtime = (attrs[.modificationDate] as? Date) ?? Date()
        
        if isLink {
            let target = try? fm.destinationOfSymbolicLink(atPath: fileURL.path)
            return CompressItem(
                sourceURL: fileURL,
                archivePath: archivePath,
                isDirectory: false,
                isSymlink: true,
                symlinkTarget: target,
                fileSize: 0,
                modificationDate: mtime,
                posixPermissions: 0o777
            )
        }
        
        let size = (attrs[.size] as? Int64) ?? 0
        let perm = (attrs[.posixPermissions] as? UInt16) ?? 0o644
        return CompressItem(
            sourceURL: fileURL,
            archivePath: archivePath,
            isDirectory: false,
            isSymlink: false,
            symlinkTarget: nil,
            fileSize: size,
            modificationDate: mtime,
            posixPermissions: perm
        )
    }
    
    private func fileTypeDescription(mode: mode_t) -> String {
        let fileType = mode & S_IFMT
        switch fileType {
        case S_IFSOCK: return "Unix Socket"
        case S_IFIFO: return "Named Pipe (FIFO)"
        case S_IFCHR: return "Character Device"
        case S_IFBLK: return "Block Device"
        default: return "Special POSIX file"
        }
    }
    
    private func cleanup(tempURL: URL, createdDestDir: URL? = nil) {
        let fm = FileManager.default
        try? fm.removeItem(at: tempURL)
        if let createdDir = createdDestDir {
            if let contents = try? fm.contentsOfDirectory(atPath: createdDir.path), contents.isEmpty {
                try? fm.removeItem(at: createdDir)
            }
        }
    }
}
