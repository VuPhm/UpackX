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
        sources: [URL],
        options: CompressionOptions,
        progress: ((CompressionProgress) -> Bool)? = nil,
        completion: @escaping (Result<CompressionResult, CompressionError>) -> Void
    ) -> Bool {
        guard !sources.isEmpty else {
            completion(.failure(.emptySource))
            return false
        }
        
        let startTime = Date()
        var finalDestinationURL = options.destinationURL
        let fm = FileManager.default
        
        // 1. Conflict resolution if destination already exists
        if fm.fileExists(atPath: finalDestinationURL.path) {
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
        
        // 2. Prepare staging output directory & temporary file
        let destDir = finalDestinationURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: destDir.path) {
            do {
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            } catch {
                completion(.failure(.cannotCreateArchive("Không thể tạo thư mục đích: \(error.localizedDescription)")))
                return false
            }
        }
        
        let tempFileName = ".upackx_compress_" + UUID().uuidString + ".tmp"
        let tempURL = destDir.appendingPathComponent(tempFileName)
        
        let canonicalDest = PathSecurity.canonicalPath(for: finalDestinationURL)
        let canonicalTemp = PathSecurity.canonicalPath(for: tempURL)
        
        // 3. Scan and collect items to archive with strict error reporting
        var itemsToCompress: [CompressItem] = []
        var totalBytesToProcess: Int64 = 0
        
        let isSingleDirectory = (sources.count == 1 && (try? sources[0].resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true)
        
        for source in sources {
            guard fm.fileExists(atPath: source.path) else {
                cleanup(tempURL: tempURL)
                completion(.failure(.sourceNotFound(source.path)))
                return false
            }
            
            // Check read permission on source
            guard fm.isReadableFile(atPath: source.path) else {
                cleanup(tempURL: tempURL)
                completion(.failure(.permissionDenied(source.path)))
                return false
            }
            
            let isDir = (try? source.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            
            do {
                if isSingleDirectory {
                    let rootDirName = source.lastPathComponent
                    try collectItems(
                        from: source,
                        relativePrefix: rootDirName,
                        canonicalDest: canonicalDest,
                        canonicalTemp: canonicalTemp,
                        into: &itemsToCompress,
                        totalBytes: &totalBytesToProcess
                    )
                } else if isDir {
                    let dirName = source.lastPathComponent
                    try collectItems(
                        from: source,
                        relativePrefix: dirName,
                        canonicalDest: canonicalDest,
                        canonicalTemp: canonicalTemp,
                        into: &itemsToCompress,
                        totalBytes: &totalBytesToProcess
                    )
                } else {
                    // Single file or symlink
                    let fileName = source.lastPathComponent
                    if let item = try makeCompressItem(for: source, archivePath: fileName, canonicalDest: canonicalDest, canonicalTemp: canonicalTemp) {
                        itemsToCompress.append(item)
                        totalBytesToProcess += item.fileSize
                    }
                }
            } catch let error as CompressionError {
                cleanup(tempURL: tempURL)
                completion(.failure(error))
                return false
            } catch {
                cleanup(tempURL: tempURL)
                completion(.failure(.traversalFailed(path: source.path, reason: error.localizedDescription)))
                return false
            }
        }
        
        guard !itemsToCompress.isEmpty else {
            cleanup(tempURL: tempURL)
            completion(.failure(.emptySource))
            return false
        }
        
        // 4. Initialize libarchive writer
        guard let a = archive_write_new() else {
            cleanup(tempURL: tempURL)
            completion(.failure(.cannotCreateArchive("Không thể cấp phát bộ nhớ cho archive writer.")))
            return false
        }
        
        guard archive_write_set_format_zip(a) == ARCHIVE_OK else {
            _ = archive_write_free(a)
            cleanup(tempURL: tempURL)
            completion(.failure(.cannotCreateArchive("Không thể thiết lập định dạng ZIP.")))
            return false
        }
        
        let optStr = "zip:compression-level=\(options.compressionLevel.libarchiveLevel)"
        let optRes = archive_write_set_options(a, optStr)
        if optRes < ARCHIVE_WARN {
            let errString = archive_error_string(a).map { String(cString: $0) } ?? "Lỗi thiết lập tùy chọn ZIP"
            _ = archive_write_free(a)
            cleanup(tempURL: tempURL)
            completion(.failure(.cannotCreateArchive(errString)))
            return false
        }
        
        guard archive_write_open_filename(a, tempURL.path) == ARCHIVE_OK else {
            let errString = archive_error_string(a).map { String(cString: $0) } ?? "Lỗi mở tệp lưu trữ"
            _ = archive_write_free(a)
            cleanup(tempURL: tempURL)
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
            cleanup(tempURL: tempURL)
            completion(.failure(.cancelled))
            return false
        }
        
        if let err = writeLoopError {
            cleanup(tempURL: tempURL)
            completion(.failure(err))
            return false
        }
        
        #if DEBUG || canImport(Foundation)
        if ZipCompressorFaults.failClose {
            cleanup(tempURL: tempURL)
            completion(.failure(.archiveCloseFailed("Fault injection: Archive close failure simulated.")))
            return false
        }
        #endif
        
        guard closeRes == ARCHIVE_OK || closeRes == ARCHIVE_WARN else {
            cleanup(tempURL: tempURL)
            completion(.failure(.archiveCloseFailed("Lỗi ghi cấu trúc cuối của file ZIP (closeRes=\(closeRes)).")))
            return false
        }
        
        // Ensure all planned files were compressed
        guard processedFiles == totalFiles else {
            cleanup(tempURL: tempURL)
            completion(.failure(.writeFailed("Số lượng tệp được nén (\(processedFiles)) không khớp với kế hoạch (\(totalFiles)).")))
            return false
        }
        
        // 7. Atomic Commit & Data Safety with Rollback Strategy
        guard fm.fileExists(atPath: tempURL.path) else {
            completion(.failure(.writeFailed("Tệp nén tạm thời không tồn tại sau khi nén.")))
            return false
        }
        
        let tempSize = (try? fm.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0
        guard tempSize > 0 else {
            cleanup(tempURL: tempURL)
            completion(.failure(.writeFailed("Tệp nén tạo ra rỗng (0 bytes).")))
            return false
        }
        
        #if DEBUG || canImport(Foundation)
        if ZipCompressorFaults.simulateCommitFailure {
            cleanup(tempURL: tempURL)
            completion(.failure(.commitFailed("Fault injection: Simulated atomic commit failure.")))
            return false
        }
        #endif
        
        do {
            try commitArchive(from: tempURL, to: finalDestinationURL, fileManager: fm)
        } catch {
            cleanup(tempURL: tempURL)
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
    
    // MARK: - Atomic Commit & Rollback
    
    private func commitArchive(from tempURL: URL, to destURL: URL, fileManager fm: FileManager) throws {
        if !fm.fileExists(atPath: destURL.path) {
            // Destination does not exist: direct atomic move
            try fm.moveItem(at: tempURL, to: destURL)
            return
        }
        
        // Destination ALREADY exists: Safe atomic replace with backup and rollback
        // Attempt 1: Native filesystem atomic replacement
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
        canonicalDest: String,
        canonicalTemp: String,
        into items: inout [CompressItem],
        totalBytes: inout Int64
    ) throws {
        let fm = FileManager.default
        let canonicalDirPath = PathSecurity.canonicalPath(for: directoryURL)
        
        guard fm.isReadableFile(atPath: directoryURL.path) else {
            throw CompressionError.permissionDenied(directoryURL.path)
        }
        
        // 1. Add directory entry itself
        let dirAttributes = (try? fm.attributesOfItem(atPath: canonicalDirPath)) ?? [:]
        let dirPerm = (dirAttributes[.posixPermissions] as? UInt16) ?? 0o755
        let dirMtime = (dirAttributes[.modificationDate] as? Date) ?? Date()
        
        let normalizedDirPrefix = relativePrefix.hasSuffix("/") ? relativePrefix : (relativePrefix + "/")
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
            
            let isLink = (try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
            if !isLink {
                // Check readability of regular file or directory
                guard fm.isReadableFile(atPath: fileURL.path) else {
                    throw CompressionError.permissionDenied(fileURL.path)
                }
            }
            
            let canonicalItem = PathSecurity.canonicalPath(for: fileURL, followSymlinks: false)
            // Self-inclusion check: do not include destination archive or temp file
            if canonicalItem == canonicalDest || canonicalItem == canonicalTemp || canonicalItem.hasPrefix(canonicalTemp + "/") {
                continue
            }
            
            guard canonicalItem.hasPrefix(canonicalDirPath) else { continue }
            let relativePathFromDir = canonicalItem.dropFirst(canonicalDirPath.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let archiveEntryPath = normalizedDirPrefix + relativePathFromDir
            
            // Validate POSIX file types: reject sockets, FIFOs, character/block devices
            var st = stat()
            if lstat(fileURL.path, &st) == 0 {
                let fileType = st.st_mode & S_IFMT
                if fileType == S_IFSOCK || fileType == S_IFIFO || fileType == S_IFCHR || fileType == S_IFBLK {
                    throw CompressionError.unsupportedFileType(path: fileURL.path, type: fileTypeDescription(mode: st.st_mode))
                }
            }
            
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            
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
        canonicalDest: String,
        canonicalTemp: String
    ) throws -> CompressItem? {
        let canonicalItem = PathSecurity.canonicalPath(for: fileURL, followSymlinks: false)
        if canonicalItem == canonicalDest || canonicalItem == canonicalTemp {
            return nil
        }
        
        let fm = FileManager.default
        let isLink = (try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
        if !isLink {
            guard fm.isReadableFile(atPath: fileURL.path) else {
                throw CompressionError.permissionDenied(fileURL.path)
            }
        }
        
        // Validate POSIX file types: reject sockets, FIFOs, character/block devices
        var st = stat()
        if lstat(fileURL.path, &st) == 0 {
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
    
    private func cleanup(tempURL: URL) {
        try? FileManager.default.removeItem(at: tempURL)
    }
}
