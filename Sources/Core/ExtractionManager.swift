import Foundation

/// Central orchestrator coordinating backends, routing, options, and progress
public final class ExtractionManager {
    public static let shared = ExtractionManager()
    
    public let nativeExtractor = LibarchiveExtractor()
    public let sevenZipExtractor = SevenZipExtractor()
    
    private init() {}
    
    /// Finds the best extractor backend for a given archive URL and format
    public func selectExtractor(for archiveURL: URL, isMultipart: Bool = false) -> ArchiveExtractorProtocol {
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
    public func inspect(archiveURL: URL, password: String? = nil) throws -> ArchiveInfo {
        let isMulti = MultipartDetector.detectMultipartType(from: archiveURL) != .none
        let extractor = selectExtractor(for: archiveURL, isMultipart: isMulti)
        return try extractor.inspect(archiveURL: archiveURL, password: password)
    }
    
    /// Executes Quick Extract directly in the archive's parent folder without enclosing folder
    public func quickExtract(archiveURL: URL,
                             conflictResolver: ConflictResolver? = nil,
                             progress: @escaping (ExtractionProgress) -> Bool,
                             completion: @escaping (Result<ExtractionResult, Error>) -> Void) {
        let parentDir = archiveURL.deletingLastPathComponent()
        let options = ExtractionOptions(
            destinationDirectory: parentDir,
            createEnclosingFolder: false, // Requirement 2.2.A & 0.3: No enclosing folder
            conflictStrategy: .ask,        // Requirement 2.2.A: Safe conflict handling, never silent overwrite
            conflictResolver: conflictResolver
        )
        
        execute(archiveURL: archiveURL, options: options, progress: progress, completion: completion)
    }
    
    /// Executes Extract To... with custom options
    public func extractTo(archiveURL: URL,
                          options: ExtractionOptions,
                          progress: @escaping (ExtractionProgress) -> Bool,
                          completion: @escaping (Result<ExtractionResult, Error>) -> Void) {
        execute(archiveURL: archiveURL, options: options, progress: progress, completion: completion)
    }
    
    /// Executes extraction in a background thread to prevent UI freezing
    public func execute(archiveURL: URL,
                        options: ExtractionOptions,
                        progress: @escaping (ExtractionProgress) -> Bool,
                        completion: @escaping (Result<ExtractionResult, Error>) -> Void) {
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
                actualArchiveURL = group.primaryVolumeURL
            }
            
            let extractor = self.selectExtractor(for: actualArchiveURL, isMultipart: isMulti)
            do {
                let result = try extractor.extract(archiveURL: actualArchiveURL, options: options, progress: progress)
                DispatchQueue.main.async {
                    completion(.success(result))
                }
            } catch ExtractionError.passwordRequired {
                if let provider = options.passwordProvider, let pw = provider(), !pw.isEmpty {
                    var retryOptions = options
                    retryOptions.password = pw
                    do {
                        let retryResult = try extractor.extract(archiveURL: actualArchiveURL, options: retryOptions, progress: progress)
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
