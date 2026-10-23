import Foundation

/// Provides robust path validation to prevent Zip-Slip and path traversal vulnerabilities.
public enum PathSecurity {
    
    public enum PathError: LocalizedError {
        case illegalCharacters(String)
        case pathTraversalDetected(String)
        case emptyPath
        
        public var errorDescription: String? {
            switch self {
            case .illegalCharacters(let p):
                return "Đường dẫn chứa ký tự không hợp lệ: \(p)"
            case .pathTraversalDetected(let p):
                return "Cảnh báo bảo mật: Phát hiện đường dẫn cố tình thoát khỏi thư mục giải nén (Zip-Slip): \(p)"
            case .emptyPath:
                return "Đường dẫn file bên trong archive rỗng."
            }
        }
    }
    
    /// Sanitizes and validates an archive entry path against a base destination directory.
    /// - Parameters:
    ///   - entryPath: The raw entry path from archive (e.g., "folder/sub/file.txt" or "foo/../../evil.txt").
    ///   - destinationDirectory: The base directory where files should be extracted.
    /// - Returns: A safe, validated absolute destination URL.
    /// - Throws: `PathError.pathTraversalDetected` if the entry attempts to escape `destinationDirectory`.
    public static func resolveSafeDestinationURL(for entryPath: String, in destinationDirectory: URL) throws -> URL {
        // Strip null bytes and control chars
        if entryPath.contains("\0") {
            throw PathError.illegalCharacters(entryPath)
        }
        
        let cleaned = entryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            throw PathError.emptyPath
        }
        
        // Remove leading slashes and drive letters
        var relativePath = cleaned
        while relativePath.hasPrefix("/") || relativePath.hasPrefix("\\") {
            relativePath.removeFirst()
        }
        
        // Split components and verify there's no escape
        let components = relativePath.split(separator: "/").map(String.init)
        var depth = 0
        for comp in components {
            if comp == "." || comp.isEmpty {
                continue
            } else if comp == ".." {
                depth -= 1
                if depth < 0 {
                    throw PathError.pathTraversalDetected(entryPath)
                }
            } else {
                depth += 1
            }
        }
        
        // Standardize base destination
        let baseStandardized = destinationDirectory.standardizedFileURL
        
        // Construct target URL
        var targetURL = baseStandardized
        for comp in components {
            if comp == "." || comp.isEmpty { continue }
            targetURL = targetURL.appendingPathComponent(comp)
        }
        targetURL = targetURL.standardizedFileURL
        
        // Verify canonical prefix
        let basePath = baseStandardized.path
        let targetPath = targetURL.path
        
        let isWithinBase = targetPath == basePath || targetPath.hasPrefix(basePath.hasSuffix("/") ? basePath : basePath + "/")
        if !isWithinBase {
            throw PathError.pathTraversalDetected(entryPath)
        }
        
        return targetURL
    }
    
    /// Generates a non-conflicting file URL by appending an incremental counter (e.g., "file (1).txt")
    public static func generateNonConflictingURL(for fileURL: URL) -> URL {
        let parent = fileURL.deletingLastPathComponent()
        let ext = fileURL.pathExtension
        let base = fileURL.deletingPathExtension().lastPathComponent
        
        var counter = 1
        var candidate: URL
        repeat {
            let newName = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            candidate = parent.appendingPathComponent(newName)
            counter += 1
        } while FileManager.default.fileExists(atPath: candidate.path)
        
        return candidate
    }
}
