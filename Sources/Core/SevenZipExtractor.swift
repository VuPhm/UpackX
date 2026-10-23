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
        
        var args = ["l", "-slt", archiveURL.path]
        if let pw = password, !pw.isEmpty {
            args.append("-p\(pw)")
        } else {
            args.append("-p-")
        }
        process.arguments = args
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        try process.run()
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
        
        let process = Process()
        process.executableURL = binURL
        
        // 7zz command: x -o<dest> -bsp1 -bso1 -y
        var args = [
            "x",
            "-o\(destDir.path)",
            "-bsp1",
            "-bso1",
            "-bd"
        ]
        
        switch options.conflictStrategy {
        case .overwrite:
            args.append("-aoa") // Overwrite all
        case .skip:
            args.append("-aos") // Skip existing
        case .rename:
            args.append("-aou") // Auto rename
        case .ask:
            // 7zz doesn't have an interactive GUI prompt, default to rename or skip
            args.append("-aou")
        }
        
        if let pw = options.password, !pw.isEmpty {
            args.append("-p\(pw)")
        } else {
            args.append("-p-")
        }
        
        args.append(archiveURL.path)
        process.arguments = args
        
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = outPipe
        
        try process.run()
        
        let outHandle = outPipe.fileHandleForReading
        let archiveBasename = archiveURL.lastPathComponent
        
        var cancelled = false
        var buffer = Data()
        var allOutput = ""
        let extractedBytes: Int64 = 0
        
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
                        extractedBytes: extractedBytes,
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
        
        let elapsed = Date().timeIntervalSince(startTime)
        return ExtractionResult(
            archiveURL: archiveURL,
            destinationURL: destDir,
            extractedCount: 1,
            skippedCount: 0,
            totalBytes: extractedBytes,
            elapsedTime: elapsed
        )
    }
}
