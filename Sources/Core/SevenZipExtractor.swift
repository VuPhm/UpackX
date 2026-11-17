import Foundation

/// Specialized backend wrapping the standalone `7zz` binary.
/// Used for complex solid 7Z, RAR5, password-encrypted headers, and multipart volumes.
public final class SevenZipExtractor: ArchiveExtractorProtocol {
    public let name = "7-Zip (7zz CLI Engine)"
    
    private let bundledBinaryURL: URL?
    
    public init() {
        // Check inside app bundle Resources/bin/7zz first
        if let resURL = Bundle.main.resourceURL {
            let bundled = resURL.appendingPathComponent("bin/7zz")
            if FileManager.default.fileExists(atPath: bundled.path) {
                self.bundledBinaryURL = bundled
                return
            }
        }
        
        // Fallback to system locations if not bundled
        for fallbackPath in ["/opt/homebrew/bin/7zz", "/usr/local/bin/7zz"] {
            if FileManager.default.fileExists(atPath: fallbackPath) {
                self.bundledBinaryURL = URL(fileURLWithPath: fallbackPath)
                return
            }
        }
        
        self.bundledBinaryURL = nil
    }
    
    public var isAvailable: Bool {
        return bundledBinaryURL != nil
    }
    
    public func canHandle(format: ArchiveFormat, archiveURL: URL) -> Bool {
        guard isAvailable else { return false }
        switch format {
        case .sevenZip, .rar, .zip, .tar, .iso, .cab:
            return true
        default:
            return false
        }
    }
    
    public func inspect(archiveURL rawArchiveURL: URL, password: String?) throws -> ArchiveInfo {
        let archiveURL = PathSecurity.normalizeFileURL(rawArchiveURL)
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw ExtractionError.fileNotFound(archiveURL)
        }
        guard let binURL = bundledBinaryURL else {
            throw ExtractionError.generic("Không tìm thấy binary 7zz.")
        }
        
        let process = Process()
        process.executableURL = binURL
        
        // Security: Avoid passing password in command line arguments (ps inspection prevention)
        var args = ["l", "-slt"]
        var inPipe: Pipe? = nil
        if let pw = password, !pw.isEmpty {
            inPipe = Pipe()
            process.standardInput = inPipe
        } else {
            args.append("-p-")
        }
        args.append(archiveURL.path)
        process.arguments = args
        
        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe
        
        try process.run()
        
        if let pw = password, !pw.isEmpty, let inPipe = inPipe {
            inPipe.fileHandleForWriting.write(Data((pw + "\n").utf8))
            try? inPipe.fileHandleForWriting.close()
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        
        let output = (String(data: data, encoding: .utf8) ?? "").replacingOccurrences(of: "\r\n", with: "\n")
        let errOutput = String(data: errData, encoding: .utf8) ?? ""
        let combinedLower = (output + "\n" + errOutput).lowercased()
        
        var isEncrypted = false
        if combinedLower.contains("wrong password") || combinedLower.contains("enter password") || combinedLower.contains("encrypted archive") || combinedLower.contains("can not open encrypted archive") {
            isEncrypted = true
        }
        
        var entries: [ArchiveEntryInfo] = []
        var totalBytes: Int64 = 0
        
        // Only parse entry blocks after the "----------" separator line
        let partsAfterSeparator = output.components(separatedBy: "----------\n")
        let entriesSection = partsAfterSeparator.count > 1 ? partsAfterSeparator.dropFirst().joined(separator: "----------\n") : output
        
        let blocks = entriesSection.components(separatedBy: "\n\n")
        for block in blocks {
            var path: String?
            var size: Int64 = 0
            var isDir = false
            var encrypted = false
            
            let lines = block.components(separatedBy: "\n")
            for line in lines {
                if line.hasPrefix("Path = ") {
                    path = String(line.dropFirst("Path = ".count))
                } else if line.hasPrefix("Size = ") {
                    size = Int64(line.dropFirst("Size = ".count)) ?? 0
                } else if line.hasPrefix("Folder = +") {
                    isDir = true
                } else if line.hasPrefix("Attributes = D") || line.contains("Attributes = ") && line.contains("D") {
                    isDir = true
                } else if line.hasPrefix("Encrypted = +") {
                    encrypted = true
                    isEncrypted = true
                }
            }
            
            if let p = path, !p.isEmpty, p != archiveURL.path {
                entries.append(ArchiveEntryInfo(
                    path: p,
                    uncompressedSize: size,
                    isDirectory: isDir,
                    isEncrypted: encrypted
                ))
                if !isDir { totalBytes += size }
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
    
    public func extract(archiveURL rawArchiveURL: URL,
                        options: ExtractionOptions,
                        progress: @escaping (ExtractionProgress) -> Bool) throws -> ExtractionResult {
        let archiveURL = PathSecurity.normalizeFileURL(rawArchiveURL)
        let fm = FileManager.default
        
        var isArchiveDir: ObjCBool = false
        guard fm.fileExists(atPath: archiveURL.path, isDirectory: &isArchiveDir), !isArchiveDir.boolValue else {
            throw ExtractionError.fileNotFound(archiveURL)
        }
        
        guard let binURL = bundledBinaryURL else {
            throw ExtractionError.generic("Không tìm thấy binary 7zz.")
        }
        
        let startTime = Date()
        let baseDest = PathSecurity.normalizeDirectoryURL(options.destinationDirectory)
        
        // Verify baseDest is not an existing regular file
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
        
        let baseDestExistedBefore = fm.fileExists(atPath: baseDest.path)
        try fm.createDirectory(at: baseDest, withIntermediateDirectories: true, attributes: nil)
        
        // Use a hidden temporary staging directory inside baseDest to ensure atomic integrity and conflict resolution
        let stagingDir = baseDest.appendingPathComponent(".upackx_staging_\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true, attributes: nil)
        
        var createdWrapperDir: URL? = nil
        var wrapperExistedBefore = true
        var extractionSucceeded = false
        var extractedCount = 0
        
        defer {
            // Always ensure the temporary staging folder is cleaned up
            try? fm.removeItem(at: stagingDir)
            if !extractionSucceeded && extractedCount == 0 {
                if let wrapper = createdWrapperDir, !wrapperExistedBefore {
                    if let contents = try? fm.contentsOfDirectory(atPath: wrapper.path), contents.isEmpty {
                        try? fm.removeItem(at: wrapper)
                    }
                }
                if !baseDestExistedBefore {
                    if let contents = try? fm.contentsOfDirectory(atPath: baseDest.path), contents.isEmpty {
                        try? fm.removeItem(at: baseDest)
                    }
                }
            }
        }
        
        let process = Process()
        process.executableURL = binURL
        
        // 7zz extracts into clean staging directory with -aoa
        var args = [
            "x",
            "-o\(stagingDir.path)",
            "-aoa",
            "-bsp1",
            "-bso1",
            "-bd"
        ]
        
        var inPipe: Pipe? = nil
        if let pw = options.password, !pw.isEmpty {
            inPipe = Pipe()
            process.standardInput = inPipe
        } else {
            args.append("-p-")
        }
        
        args.append(archiveURL.path)
        process.arguments = args
        
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = outPipe
        
        try process.run()
        
        // Write password via stdin pipe if provided (never exposed in process arguments or logs)
        if let pw = options.password, !pw.isEmpty, let inPipe = inPipe {
            inPipe.fileHandleForWriting.write(Data((pw + "\n").utf8))
            try? inPipe.fileHandleForWriting.close()
        }
        
        let outHandle = outPipe.fileHandleForReading
        let archiveBasename = archiveURL.lastPathComponent
        
        var cancelled = false
        var buffer = Data()
        var allOutput = ""
        
        while process.isRunning {
            let chunk = outHandle.availableData
            if chunk.isEmpty {
                usleep(50_000)
                continue
            }
            buffer.append(chunk)
            if let str = String(data: chunk, encoding: .utf8) {
                allOutput += str
            }
            
            // Parse progress output from 7zz
            while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\r")) ?? buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer.subdata(in: 0..<newlineIndex)
                buffer.removeSubrange(0...newlineIndex)
                
                if let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                    let p = ExtractionProgress(
                        archiveName: archiveBasename,
                        currentFilePath: line,
                        extractedBytes: 0,
                        totalBytes: nil,
                        extractedEntriesCount: 0,
                        totalEntriesCount: nil,
                        elapsedTime: Date().timeIntervalSince(startTime)
                    )
                    
                    if !progress(p) {
                        cancelled = true
                        process.terminate()
                        break
                    }
                }
            }
            
            if cancelled { break }
        }
        
        // Read any remaining data after exit
        let remaining = outHandle.readDataToEndOfFile()
        if let str = String(data: remaining, encoding: .utf8) {
            allOutput += str
        }
        
        process.waitUntilExit()
        
        if cancelled {
            throw ExtractionError.cancelled
        }
        
        if process.terminationStatus != 0 {
            let lower = allOutput.lowercased()
            if lower.contains("wrong password") || lower.contains("enter password") || lower.contains("encrypted archive") || lower.contains("can not open encrypted archive") {
                throw ExtractionError.passwordRequired
            }
            if process.terminationStatus == 2 {
                throw ExtractionError.corruptedArchive("7zz báo lỗi file nén (exit code 2)")
            }
            throw ExtractionError.generic("7zz hoàn thành với lỗi (exit code \(process.terminationStatus))")
        }
        
        // Determine effective destination directory after staging (avoiding duplicate Video/Video/ wrapper)
        let destDir: URL
        let reportedDestination: URL
        if options.createEnclosingFolder {
            let enclosingName = PathSecurity.archiveBaseName(for: archiveURL)
            if PathSecurity.stagingDirectoryHasSingleRootDirectory(at: stagingDir, matching: enclosingName) {
                destDir = baseDest
                reportedDestination = baseDest.appendingPathComponent(enclosingName, isDirectory: true)
            } else if PathSecurity.normalizedFolderNameEqual(baseDest.lastPathComponent, enclosingName) {
                destDir = baseDest
                reportedDestination = baseDest
            } else {
                let wrapper = baseDest.appendingPathComponent(enclosingName, isDirectory: true)
                wrapperExistedBefore = fm.fileExists(atPath: wrapper.path)
                createdWrapperDir = wrapper
                try fm.createDirectory(at: wrapper, withIntermediateDirectories: true, attributes: nil)
                destDir = wrapper
                reportedDestination = wrapper
            }
        } else {
            destDir = baseDest
            reportedDestination = baseDest
        }
        
        // Commit extracted files from staging to destDir with full conflict resolution and Zip-Slip defense
        var currentConflictDecision: ConflictDecision? = nil
        var skippedCount = 0
        var totalBytesExtracted: Int64 = 0
        
        guard let enumerator = fm.enumerator(
            at: stagingDir,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
            options: []
        ) else {
            throw ExtractionError.generic("Không thể duyệt thư mục tạm của 7zz.")
        }
        
        var dirURLs: [URL] = []
        var fileAndSymlinkURLs: [URL] = []
        
        while let itemURL = enumerator.nextObject() as? URL {
            var st = stat()
            if lstat(itemURL.path, &st) == 0 {
                let fileType = st.st_mode & S_IFMT
                if fileType == S_IFDIR {
                    dirURLs.append(itemURL)
                } else {
                    fileAndSymlinkURLs.append(itemURL)
                }
            }
        }
        
        // Sort directories by path depth (shallow first) to recreate directory tree safely
        dirURLs.sort { $0.path.count < $1.path.count }
        for dirURL in dirURLs {
            guard let safeRel = PathSecurity.relativePath(of: dirURL, from: stagingDir), !safeRel.isEmpty else { continue }
            let targetURL = try PathSecurity.resolveSafeDestinationURL(for: safeRel, in: destDir)
            if targetURL.standardizedFileURL.path == destDir.standardizedFileURL.path { continue }
            
            var isExistingDir: ObjCBool = false
            var isExistingSymlink: Bool = false
            if PathSecurity.itemExistsIncludingSymlink(at: targetURL, isDirectory: &isExistingDir, isSymlink: &isExistingSymlink) {
                if isExistingSymlink {
                    let resolvedLink = PathSecurity.canonicalPath(for: targetURL, followSymlinks: true)
                    let canonicalDest = PathSecurity.canonicalPath(for: destDir, followSymlinks: true)
                    if !PathSecurity.isCanonicallyContained(path: resolvedLink, within: canonicalDest) {
                        throw ExtractionError.pathSecurityViolation("Thư mục đích chứa symlink trỏ ra ngoài phạm vi an toàn: \(safeRel)")
                    }
                } else if !isExistingDir.boolValue {
                    throw ExtractionError.writeFailed("Không thể tạo thư mục '\(targetURL.lastPathComponent)' vì đã có một tệp tin trùng tên tại đích.")
                }
            } else {
                try fm.createDirectory(at: targetURL, withIntermediateDirectories: true, attributes: nil)
            }
        }
        
        for itemURL in fileAndSymlinkURLs {
            guard let safeRel = PathSecurity.relativePath(of: itemURL, from: stagingDir), !safeRel.isEmpty else { continue }
            let targetURL = try PathSecurity.resolveSafeDestinationURL(for: safeRel, in: destDir)
            
            // Check cancellation during move
            let p = ExtractionProgress(
                archiveName: archiveBasename,
                currentFilePath: safeRel,
                extractedBytes: totalBytesExtracted,
                totalBytes: nil,
                extractedEntriesCount: extractedCount,
                totalEntriesCount: fileAndSymlinkURLs.count,
                elapsedTime: Date().timeIntervalSince(startTime)
            )
            if !progress(p) {
                throw ExtractionError.cancelled
            }
            
            let parentDir = targetURL.deletingLastPathComponent()
            if !fm.fileExists(atPath: parentDir.path) {
                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
            }
            
            var finalDestinationURL = targetURL
            var isTargetDirectory: ObjCBool = false
            var isTargetSymlink: Bool = false
            if PathSecurity.itemExistsIncludingSymlink(at: targetURL, isDirectory: &isTargetDirectory, isSymlink: &isTargetSymlink) {
                if isTargetDirectory.boolValue && !isTargetSymlink {
                    // Never delete an existing user directory! Auto-rename incoming file
                    finalDestinationURL = PathSecurity.generateNonConflictingURL(for: targetURL)
                } else {
                    let action: ConflictAction
                    if let active = currentConflictDecision, active.applyToAll {
                        action = active.action
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
                                action = .skip
                            }
                        }
                    }
                    
                    switch action {
                    case .cancel:
                        throw ExtractionError.cancelled
                    case .skip:
                        skippedCount += 1
                        continue
                    case .rename:
                        finalDestinationURL = PathSecurity.generateNonConflictingURL(for: targetURL)
                    case .overwrite:
                        finalDestinationURL = targetURL
                    }
                }
            }
            
            var st = stat()
            let isStagedSymlink = (lstat(itemURL.path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFLNK)
            if isStagedSymlink {
                if let linkDest = try? fm.destinationOfSymbolicLink(atPath: itemURL.path) {
                    if PathSecurity.itemExistsIncludingSymlink(at: finalDestinationURL) {
                        try? fm.removeItem(at: finalDestinationURL)
                    }
                    try fm.createSymbolicLink(atPath: finalDestinationURL.path, withDestinationPath: linkDest)
                    extractedCount += 1
                }
            } else {
                let itemSize = (try? fm.attributesOfItem(atPath: itemURL.path)[.size] as? Int64) ?? 0
                try GoogleDriveHelper.safeCommitFile(from: itemURL, to: finalDestinationURL)
                extractedCount += 1
                totalBytesExtracted += itemSize
            }
        }
        
        extractionSucceeded = true
        let elapsed = Date().timeIntervalSince(startTime)
        return ExtractionResult(
            archiveURL: archiveURL,
            destinationURL: reportedDestination,
            extractedCount: extractedCount,
            skippedCount: skippedCount,
            totalBytes: totalBytesExtracted,
            elapsedTime: elapsed
        )
    }
}
