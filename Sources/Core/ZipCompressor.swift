import Foundation

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
        
        // 1. Conflict resolution if destination already exists
        let fm = FileManager.default
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
        
        // 2. Prepare staging output path
        let destDir = finalDestinationURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: destDir.path) {
            try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        }
        
        let tempFileName = ".upackx_compress_" + UUID().uuidString + ".tmp"
        let tempURL = destDir.appendingPathComponent(tempFileName)
        
        let canonicalDest = PathSecurity.canonicalPath(for: finalDestinationURL)
        let canonicalTemp = PathSecurity.canonicalPath(for: tempURL)
        
        // 3. Scan and discover items to archive
        var itemsToCompress: [CompressItem] = []
        var totalBytesToProcess: Int64 = 0
        
        let isSingleDirectory = (sources.count == 1 && (try? sources[0].resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true)
        
        for source in sources {
            guard fm.fileExists(atPath: source.path) else {
                cleanup(tempURL: tempURL)
                completion(.failure(.sourceNotFound(source.path)))
                return false
            }
            
            let isDir = (try? source.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            
            if isSingleDirectory {
                // When single directory e.g. "Photos", archive must preserve root "Photos/"
                let rootDirName = source.lastPathComponent
                collectItems(
                    from: source,
                    relativePrefix: rootDirName,
                    canonicalDest: canonicalDest,
                    canonicalTemp: canonicalTemp,
                    into: &itemsToCompress,
                    totalBytes: &totalBytesToProcess
                )
            } else if isDir {
                let dirName = source.lastPathComponent
                collectItems(
                    from: source,
                    relativePrefix: dirName,
                    canonicalDest: canonicalDest,
                    canonicalTemp: canonicalTemp,
                    into: &itemsToCompress,
                    totalBytes: &totalBytesToProcess
                )
            } else {
                // Single file
                let fileName = source.lastPathComponent
                if let item = makeCompressItem(for: source, archivePath: fileName, canonicalDest: canonicalDest, canonicalTemp: canonicalTemp) {
                    itemsToCompress.append(item)
                    totalBytesToProcess += item.fileSize
                }
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
        _ = archive_write_set_options(a, optStr)
        
        guard archive_write_open_filename(a, tempURL.path) == ARCHIVE_OK else {
            let errString = archive_error_string(a).map { String(cString: $0) } ?? "Lỗi không xác định"
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
        
        let bufferSize = 65536 // 64 KB streaming buffer (<30MB RAM footprint)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        
        for item in itemsToCompress {
            if isCancelled { break }
            
            // Check progress & cancellation before writing entry
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
            
            guard let entry = archive_entry_new() else { continue }
            archive_entry_set_pathname_utf8(entry, item.archivePath)
            archive_entry_set_mtime(entry, Int(item.modificationDate.timeIntervalSince1970), 0)
            archive_entry_set_perm(entry, item.posixPermissions)
            
            if item.isSymlink, let target = item.symlinkTarget {
                archive_entry_set_filetype(entry, AE_IFLNK)
                archive_entry_set_symlink(entry, target)
                _ = archive_write_header(a, entry)
                archive_entry_free(entry)
                processedFiles += 1
                continue
            }
            
            if item.isDirectory {
                archive_entry_set_filetype(entry, AE_IFDIR)
                archive_entry_set_size(entry, 0)
                _ = archive_write_header(a, entry)
                archive_entry_free(entry)
                processedFiles += 1
                continue
            }
            
            // Regular file
            archive_entry_set_filetype(entry, AE_IFREG)
            archive_entry_set_size(entry, item.fileSize)
            
            let headerRes = archive_write_header(a, entry)
            archive_entry_free(entry)
            
            if headerRes != ARCHIVE_OK {
                continue
            }
            
            // Stream file data in chunks
            if item.fileSize > 0 {
                let fd = open(item.sourceURL.path, O_RDONLY)
                if fd >= 0 {
                    while true {
                        let bytesRead = read(fd, buffer, bufferSize)
                        if bytesRead <= 0 { break }
                        
                        let bytesWritten = archive_write_data(a, buffer, bytesRead)
                        if bytesWritten < 0 {
                            break
                        }
                        
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
                    close(fd)
                }
            }
            
            processedFiles += 1
        }
        
        _ = archive_write_close(a)
        _ = archive_write_free(a)
        
        if isCancelled {
            cleanup(tempURL: tempURL)
            completion(.failure(.cancelled))
            return false
        }
        
        // 6. Finalize output archive
        do {
            if fm.fileExists(atPath: finalDestinationURL.path) {
                try fm.removeItem(at: finalDestinationURL)
            }
            try fm.moveItem(at: tempURL, to: finalDestinationURL)
        } catch {
            cleanup(tempURL: tempURL)
            completion(.failure(.writeFailed("Không thể hoàn tất file nén đích: \(error.localizedDescription)")))
            return false
        }
        
        let archiveSize = (try? fm.attributesOfItem(atPath: finalDestinationURL.path)[.size] as? Int64) ?? 0
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
    
    // MARK: - Directory Scanning & Traversal
    
    private func collectItems(
        from directoryURL: URL,
        relativePrefix: String,
        canonicalDest: String,
        canonicalTemp: String,
        into items: inout [CompressItem],
        totalBytes: inout Int64
    ) {
        let fm = FileManager.default
        let canonicalDirPath = PathSecurity.canonicalPath(for: directoryURL)
        
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
        
        // 2. Enumerate directory contents recursively
        guard let enumerator = fm.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return }
        
        for case let fileURL as URL in enumerator {
            let canonicalItem = PathSecurity.canonicalPath(for: fileURL)
            // Self-inclusion check: do not include destination archive or temp file
            if canonicalItem == canonicalDest || canonicalItem == canonicalTemp || canonicalItem.hasPrefix(canonicalTemp + "/") {
                continue
            }
            
            guard canonicalItem.hasPrefix(canonicalDirPath) else { continue }
            let relativePathFromDir = canonicalItem.dropFirst(canonicalDirPath.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let archiveEntryPath = normalizedDirPrefix + relativePathFromDir
            
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let isLink = (try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
            
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
    }
    
    private func makeCompressItem(
        for fileURL: URL,
        archivePath: String,
        canonicalDest: String,
        canonicalTemp: String
    ) -> CompressItem? {
        let canonicalItem = PathSecurity.canonicalPath(for: fileURL)
        if canonicalItem == canonicalDest || canonicalItem == canonicalTemp {
            return nil
        }
        
        let fm = FileManager.default
        let isLink = (try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
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
    
    private func cleanup(tempURL: URL) {
        try? FileManager.default.removeItem(at: tempURL)
    }
}
