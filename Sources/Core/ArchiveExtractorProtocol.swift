import Foundation

/// Protocol for archive extraction backends
public protocol ArchiveExtractorProtocol {
    /// Identifier name for logging/debugging
    var name: String { get }
    
    /// Determines whether this backend can handle the given archive
    func canHandle(format: ArchiveFormat, archiveURL: URL) -> Bool
    
    /// Inspects the archive to retrieve metadata and entry list
    func inspect(archiveURL: URL, password: String?) throws -> ArchiveInfo
    
    /// Extracts the archive with streaming progress and cancellation support.
    /// Returns `ExtractionResult` upon success.
    /// If `progress` closure returns `false`, extraction halts and throws `ExtractionError.cancelled`.
    func extract(archiveURL: URL,
                 options: ExtractionOptions,
                 progress: @escaping (ExtractionProgress) -> Bool) throws -> ExtractionResult
}
