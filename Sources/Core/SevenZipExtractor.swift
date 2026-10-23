import Foundation

/// Specialized backend wrapping the standalone `7zz` binary.
/// Used for complex solid 7Z, password-encrypted headers, and multipart volumes.
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
        
        // Fallback to /usr/local/bin/7zz or system PATH
        if FileManager.default.fileExists(atPath: "/usr/local/bin/7zz") {
            self.bundledBinaryURL = URL(fileURLWithPath: "/usr/local/bin/7zz")
            return
        }
        
        self.bundledBinaryURL = nil
    }
    
    public var isAvailable: Bool {
        return bundledBinaryURL != nil
    }
    
    public func canHandle(format: ArchiveFormat, archiveURL: URL) -> Bool {
        guard isAvailable else { return false }
        switch format {
        case .sevenZip, .rar, .zip, .tar, .tarGz, .tarBz2, .tarXz:
            return true
        default:
            return false
        }
    }
    
    public func inspect(archiveURL: URL, password: String?) throws -> ArchiveInfo {
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
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        try process.run()
        
        if let pw = password, !pw.isEmpty, let inPipe = inPipe {
            inPipe.fileHandleForWriting.write(Data((pw + "\n").utf8))
            try? inPipe.fileHandleForWriting.close()
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        
        let output = String(data: data, encoding: .utf8) ?? ""
        
        var entries: [ArchiveEntryInfo] = []
        var totalBytes: Int64 = 0
        var isEncrypted = false
        
        let blocks = output.components(separatedBy: "\n\n")
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
                } else if line.hasPrefix("Encrypted = +") {
                    encrypted = true
                    isEncrypted = true
                }
            }
            
            if let p = path, p != archiveURL.path {
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
    
    public func extract(archiveURL: URL,
                        options: ExtractionOptions,
                        progress: @escaping (ExtractionProgress) -> Bool) throws -> ExtractionResult {
        guard let binURL = bundledBinaryURL else {
            throw ExtractionError.generic("Không tìm thấy binary 7zz.")
        }
        
        let startTime = Date()
        let fm = FileManager.default
        
        var destDir = options.destinationDirectory
        if options.createEnclosingFolder {
            let folderName = archiveURL.deletingPathExtension().lastPathComponent
            destDir = destDir.appendingPathComponent(folderName, isDirectory: true)
        }
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true, attributes: nil)
        
        // Use a hidden temporary staging directory in destination to ensure atomic integrity and true interactive conflict resolution (.ask)
        let stagingDir = destDir.appendingPathComponent(".upackx_staging_\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true, attributes: nil)
        
        defer {
            // Always ensure the temporary staging folder is cleaned up
            try? fm.removeItem(at: stagingDir)
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
            if lower.contains("wrong password") || lower.contains("enter password") || lower.contains("encrypted archive") {
                throw ExtractionError.passwordRequired
            }
            if process.terminationStatus == 2 {
                throw ExtractionError.corruptedArchive("7zz báo lỗi file nén (exit code 2)")
            }
            throw ExtractionError.generic("7zz hoàn thành với lỗi (exit code \(process.terminationStatus))")
        }
        
        // Commit extracted files from staging to destDir with full conflict resolution and Zip-Slip defense
        var currentConflictDecision: ConflictDecision? = nil
        var extractedCount = 0
        var skippedCount = 0
        var totalBytesExtracted: Int64 = 0
        
        guard let enumerator = fm.enumerator(at: stagingDir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: []) else {
            throw ExtractionError.generic("Không thể duyệt thư mục tạm của 7zz.")
        }
        
        var dirURLs: [URL] = []
        var fileURLs: [URL] = []
        
        while let itemURL = enumerator.nextObject() as? URL {
            let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                dirURLs.append(itemURL)
            } else {
                fileURLs.append(itemURL)
            }
        }
        
        let stagingCanonical = stagingDir.resolvingSymlinksInPath().path
        
        // Sort directories by path depth (shallow first) to recreate directory tree
        dirURLs.sort { $0.path.count < $1.path.count }
        for dirURL in dirURLs {
            let itemCanonical = dirURL.resolvingSymlinksInPath().path
            guard itemCanonical.hasPrefix(stagingCanonical) else { continue }
            var safeRel = String(itemCanonical.dropFirst(stagingCanonical.count))
            while safeRel.hasPrefix("/") { safeRel.removeFirst() }
            guard !safeRel.isEmpty else { continue }
            let targetURL = try PathSecurity.resolveSafeDestinationURL(for: safeRel, in: destDir)
            try fm.createDirectory(at: targetURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        for fileURL in fileURLs {
            let itemCanonical = fileURL.resolvingSymlinksInPath().path
            guard itemCanonical.hasPrefix(stagingCanonical) else { continue }
            var safeRel = String(itemCanonical.dropFirst(stagingCanonical.count))
            while safeRel.hasPrefix("/") { safeRel.removeFirst() }
            guard !safeRel.isEmpty else { continue }
            let targetURL = try PathSecurity.resolveSafeDestinationURL(for: safeRel, in: destDir)
            
            // Check cancellation during move
            let p = ExtractionProgress(
                archiveName: archiveBasename,
                currentFilePath: safeRel,
                extractedBytes: totalBytesExtracted,
                totalBytes: nil,
                extractedEntriesCount: extractedCount,
                totalEntriesCount: fileURLs.count,
                elapsedTime: Date().timeIntervalSince(startTime)
            )
            if !progress(p) {
                throw ExtractionError.cancelled
            }
            
            var finalDestinationURL = targetURL
            if fm.fileExists(atPath: targetURL.path) {
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
                            // If conflict cannot be prompted interactively, skip the file safely
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
                    try? fm.removeItem(at: targetURL)
                    finalDestinationURL = targetURL
                }
            }
            
            try GoogleDriveHelper.safeCommitFile(from: fileURL, to: finalDestinationURL)
            extractedCount += 1
            if let size = (try? finalDestinationURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                totalBytesExtracted += Int64(size)
            }
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        return ExtractionResult(
            archiveURL: archiveURL,
            destinationURL: destDir,
            extractedCount: extractedCount,
            skippedCount: skippedCount,
            totalBytes: totalBytesExtracted,
            elapsedTime: elapsed
        )
    }
}
