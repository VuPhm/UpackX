import Foundation

/// Central orchestrator coordinating backends, routing, options, and progress
public final class ExtractionManager {
    public static let shared = ExtractionManager()
    
    public let nativeExtractor = LibarchiveExtractor()
    public let sevenZipExtractor = SevenZipExtractor()
    
    private init() {}
    
    /// Finds the best extractor backend for a given archive URL
    public func selectExtractor(for archiveURL: URL) -> ArchiveExtractorProtocol {
        let format = ArchiveFormat.detect(from: archiveURL)
        
        // Prefer native libarchive for zero-dependency streaming and low memory footprint
        if nativeExtractor.canHandle(format: format, archiveURL: archiveURL) {
            return nativeExtractor
        }
        
        // Fallback to 7zz if available
        if sevenZipExtractor.isAvailable && sevenZipExtractor.canHandle(format: format, archiveURL: archiveURL) {
            return sevenZipExtractor
        }
        
        // Default to native extractor which will attempt to open or return standard error
        return nativeExtractor
    }
    
    /// Inspects an archive to return entry count, uncompressed size, etc.
    public func inspect(archiveURL: URL, password: String? = nil) throws -> ArchiveInfo {
        let extractor = selectExtractor(for: archiveURL)
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
            createEnclosingFolder: false, // Requirement 2.2.A: No enclosing folder
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
            let extractor = self.selectExtractor(for: archiveURL)
            do {
                let result = try extractor.extract(archiveURL: archiveURL, options: options, progress: progress)
                DispatchQueue.main.async {
                    completion(.success(result))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
