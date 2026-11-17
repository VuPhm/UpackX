import Foundation

/// Central orchestrator coordinating backends, routing, options, and progress
public final class ExtractionManager {
    public static let shared = ExtractionManager()
    
    public let nativeExtractor = LibarchiveExtractor()
    public let sevenZipExtractor = SevenZipExtractor()
    
    private init() {}
    
    /// Finds the best extractor backend for a given archive URL and format
    public func selectExtractor(for rawArchiveURL: URL, isMultipart: Bool = false) -> ArchiveExtractorProtocol {
        let archiveURL = PathSecurity.normalizeFileURL(rawArchiveURL)
        let format = ArchiveFormat.detect(from: archiveURL)
        
        // Multi-part RAR and 7z archives work most reliably via 7zz's multi-volume engine
        if isMultipart && sevenZipExtractor.isAvailable {
            return sevenZipExtractor
        }
        
        // Prefer native libarchive for zero-dependency streaming and low memory footprint
        if nativeExtractor.canHandle(format: format, archiveURL: archiveURL) {
            return nativeExtractor
        }
        
        // Fallback to 7zz if available
        if sevenZipExtractor.isAvailable && sevenZipExtractor.canHandle(format: format, archiveURL: archiveURL) {
            return sevenZipExtractor
        }
        
        return nativeExtractor
    }
    
    /// Inspects an archive to return entry count, uncompressed size, etc.
    public func inspect(archiveURL rawArchiveURL: URL, password: String? = nil) throws -> ArchiveInfo {
        let archiveURL = PathSecurity.normalizeFileURL(rawArchiveURL)
        let isMulti = MultipartDetector.detectMultipartType(from: archiveURL) != .none
        let extractor = selectExtractor(for: archiveURL, isMultipart: isMulti)
        do {
            return try extractor.inspect(archiveURL: archiveURL, password: password)
        } catch {
            let format = ArchiveFormat.detect(from: archiveURL)
            if (format == .sevenZip || format == .rar) && sevenZipExtractor.isAvailable && (extractor as AnyObject) !== sevenZipExtractor {
                return try sevenZipExtractor.inspect(archiveURL: archiveURL, password: password)
            }
            throw error
        }
    }
    
    /// Executes Quick Extract directly in the archive's parent folder without enclosing folder.
    /// Completely independent: never inherits any custom destination from previous operations.
    public func quickExtract(archiveURL rawArchiveURL: URL,
                             conflictResolver: ConflictResolver? = nil,
                             progress: @escaping (ExtractionProgress) -> Bool,
                             completion: @escaping (Result<ExtractionResult, Error>) -> Void) {
        let archiveURL = PathSecurity.normalizeFileURL(rawArchiveURL)
        let parentDir = PathSecurity.defaultExtractionDirectory(for: archiveURL)
        let options = ExtractionOptions(
            destinationDirectory: parentDir,
            createEnclosingFolder: false, // Quick Extract never creates an enclosing wrapper folder
            conflictStrategy: .ask,
            conflictResolver: conflictResolver
        )
        
        execute(archiveURL: archiveURL, options: options, progress: progress, completion: completion)
    }
    
    /// Executes Extract To... with custom options
    public func extractTo(archiveURL rawArchiveURL: URL,
                          options: ExtractionOptions,
                          progress: @escaping (ExtractionProgress) -> Bool,
                          completion: @escaping (Result<ExtractionResult, Error>) -> Void) {
        execute(archiveURL: rawArchiveURL, options: options, progress: progress, completion: completion)
    }
    
    /// Executes extraction in a background thread to prevent UI freezing
    public func execute(archiveURL rawArchiveURL: URL,
                        options rawOptions: ExtractionOptions,
                        progress: @escaping (ExtractionProgress) -> Bool,
                        completion: @escaping (Result<ExtractionResult, Error>) -> Void) {
        let archiveURL = PathSecurity.normalizeFileURL(rawArchiveURL)
        var options = rawOptions
        options.destinationDirectory = PathSecurity.normalizeDirectoryURL(rawOptions.destinationDirectory)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // 1. Google Drive dataless check
            let cloudStatus = GoogleDriveHelper.checkFileAvailability(at: archiveURL)
            if cloudStatus == .downloadingPlaceholder {
                DispatchQueue.main.async {
                    completion(.failure(ExtractionError.generic("File nén đang ở trạng thái trực tuyến trên Google Drive và chưa được tải về máy. Vui lòng mở hoặc tải file về trước khi giải nén.")))
                }
                return
            }
            
            // 2. Multi-part volume integrity validation
            var actualArchiveURL = archiveURL
            var isMulti = false
            
            if let group = MultipartDetector.inspectMultipartSet(for: archiveURL) {
                isMulti = true
                if !group.isComplete {
                    let missingList = group.missingPartNames.joined(separator: ", ")
                    DispatchQueue.main.async {
                        completion(.failure(ExtractionError.corruptedArchive("Bộ nén chia phần '\(group.baseName)' không hoàn chỉnh. Thiếu các file volume: \(missingList)")))
                    }
                    return
                }
                actualArchiveURL = PathSecurity.normalizeFileURL(group.primaryVolumeURL)
            }
            
            let format = ArchiveFormat.detect(from: actualArchiveURL)
            let primaryExtractor = self.selectExtractor(for: actualArchiveURL, isMultipart: isMulti)
            
            let runExtraction = { (ext: ArchiveExtractorProtocol, opts: ExtractionOptions) throws -> ExtractionResult in
                do {
                    return try ext.extract(archiveURL: actualArchiveURL, options: opts, progress: progress)
                } catch ExtractionError.corruptedArchive(let msg) {
                    // Fallback to 7zz for RAR5 / solid 7z formats if native libarchive cannot decode the filter
                    if (format == .sevenZip || format == .rar) && self.sevenZipExtractor.isAvailable && (ext as AnyObject) !== self.sevenZipExtractor {
                        return try self.sevenZipExtractor.extract(archiveURL: actualArchiveURL, options: opts, progress: progress)
                    }
                    throw ExtractionError.corruptedArchive(msg)
                }
            }
            
            do {
                let result = try runExtraction(primaryExtractor, options)
                DispatchQueue.main.async {
                    completion(.success(result))
                }
            } catch ExtractionError.passwordRequired {
                if let provider = options.passwordProvider, let pw = provider(), !pw.isEmpty {
                    var retryOptions = options
                    retryOptions.password = pw
                    do {
                        let retryResult = try runExtraction(primaryExtractor, retryOptions)
                        DispatchQueue.main.async {
                            completion(.success(retryResult))
                        }
                    } catch {
                        DispatchQueue.main.async {
                            completion(.failure(error))
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(ExtractionError.passwordRequired))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
