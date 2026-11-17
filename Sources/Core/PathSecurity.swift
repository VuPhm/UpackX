import Foundation

/// Unified path resolution, normalization, validation, and Zip-Slip / symlink security engine.
/// Shared across UI (Extract To, Compress To, Drag & Drop), Finder Services, CLI, and extraction/compression backends.
public enum PathSecurity {
    
    // MARK: - Archive Entry Security Errors
    
    public enum PathError: LocalizedError, Equatable {
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
    
    // MARK: - User Input Path & Filename Validation Errors
    
    public enum UserPathError: LocalizedError, Equatable {
        case emptyPath
        case relativePathNotAllowed(String)
        case invalidCharacters(String)
        case invalidHomeDirectory(String)
        case pointsToExistingFile(URL)
        case pointsToBrokenSymlink(URL)
        case invalidArchiveName(String)
        case destinationIsDirectory(URL)
        
        public var errorDescription: String? {
            switch self {
            case .emptyPath:
                return "Vui lòng nhập đường dẫn thư mục."
            case .relativePathNotAllowed(let raw):
                return "Đường dẫn \"\(raw)\" không phải là đường dẫn tuyệt đối. Vui lòng nhập đường dẫn đầy đủ bắt đầu bằng '/' hoặc '~'."
            case .invalidCharacters(let raw):
                return "Đường dẫn chứa ký tự điều khiển không hợp lệ: \(raw)"
            case .invalidHomeDirectory(let raw):
                return "Không tìm thấy thư mục người dùng cho đường dẫn: \(raw)"
            case .pointsToExistingFile(let url):
                return "Đường dẫn \"\(url.lastPathComponent)\" đã tồn tại nhưng là một tệp tin, không phải thư mục.\nVui lòng chỉ định một thư mục khác."
            case .pointsToBrokenSymlink(let url):
                return "Đường dẫn \"\(url.lastPathComponent)\" là một liên kết tượng trưng (symlink) bị hỏng hoặc không hợp lệ."
            case .invalidArchiveName(let reason):
                return reason
            case .destinationIsDirectory(let url):
                return "Đường dẫn file nén đích \"\(url.lastPathComponent)\" trùng tên với một thư mục đang tồn tại."
            }
        }
    }
    
    // MARK: - Fundamental URL Normalization
    
    /// Converts any file URL (including Finder file reference URLs `file:///.file/id=...`) into a standardized file path URL
    /// without resolving symlinks on the final path (preserving user-selected symlink/CloudStorage paths).
    public static func normalizeFileURL(_ url: URL) -> URL {
        let resolvedRef = (url as NSURL).filePathURL ?? url
        let standardized = resolvedRef.standardizedFileURL
        return URL(fileURLWithPath: standardized.path)
    }
    
    /// Normalizes a directory URL ensuring `hasDirectoryPath` semantics and clean component boundaries.
    public static func normalizeDirectoryURL(_ url: URL) -> URL {
        let resolvedRef = (url as NSURL).filePathURL ?? url
        let standardized = resolvedRef.standardizedFileURL
        return URL(fileURLWithPath: standardized.path, isDirectory: true)
    }
    
    /// Normalizes and deduplicates an array of file URLs while preserving order (e.g., when NSPasteboard has multiple representations for the same file).
    public static func deduplicateURLs(_ urls: [URL]) -> [URL] {
        var result: [URL] = []
        var seen: Set<String> = []
        for raw in urls {
            let norm = normalizeFileURL(raw)
            let key = norm.path.precomposedStringWithCanonicalMapping
            if !key.isEmpty && !seen.contains(key) {
                seen.insert(key)
                result.append(norm)
            }
        }
        return result
    }
    
    /// Cleans raw user-entered or pasted path strings (from UI text fields, pasteboard, drag-and-drop, or CLI).
    /// - Supports `~`, `file://`, trailing `/`, surrounding quotes (`"`, `'`, `“`, `”`, `‘`, `’`), and shell-escaped spaces `\ `.
    /// - NEVER resolves empty or relative strings against the process's current working directory.
    public static func cleanUserInputPath(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }
        
        // 1. Strip surrounding quotes repeatedly
        s = stripSurroundingQuotes(s)
        guard !s.isEmpty else { return "" }
        
        // 2. Handle file:// URLs (including percent-encoded paths and file://localhost/)
        if s.lowercased().hasPrefix("file://") {
            if let directURL = URL(string: s), directURL.isFileURL {
                let resolved = (directURL as NSURL).filePathURL ?? directURL
                s = resolved.path
            } else if let encoded = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let encodedURL = URL(string: encoded), encodedURL.isFileURL {
                let resolved = (encodedURL as NSURL).filePathURL ?? encodedURL
                s = resolved.path
            } else {
                if s.lowercased().hasPrefix("file://localhost/") {
                    s = String(s.dropFirst("file://localhost".count))
                } else {
                    s = String(s.dropFirst("file://".count))
                }
                s = s.removingPercentEncoding ?? s
            }
            s = stripSurroundingQuotes(s)
            guard !s.isEmpty else { return "" }
        }
        
        // 3. Unescape shell-escaped spaces from Terminal drag/paste
        s = s.replacingOccurrences(of: "\\ ", with: " ")
        
        // 4. Expand tilde (~)
        if s == "~" {
            s = FileManager.default.homeDirectoryForCurrentUser.path
        } else if s.hasPrefix("~/") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            s = home + String(s.dropFirst(1))
        } else if s.hasPrefix("~") {
            let expanded = (s as NSString).expandingTildeInPath
            s = expanded
        }
        
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }
        
        // 5. Only standardize via URL(fileURLWithPath:) if the path is already absolute (starts with "/").
        // Relative paths or unexpanded "~unknownuser" are returned without CWD contamination so callers can validate them.
        if s.hasPrefix("/") {
            return URL(fileURLWithPath: s).standardized.path
        }
        
        return s
    }
    
    private static func stripSurroundingQuotes(_ input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let quotePairs: [(String, String)] = [
            ("\"", "\""),
            ("'", "'"),
            ("“", "”"),
            ("‘", "’")
        ]
        var changed = true
        while changed && s.count >= 2 {
            changed = false
            for (openQ, closeQ) in quotePairs {
                if s.hasPrefix(openQ) && s.hasSuffix(closeQ) {
                    s = String(s.dropFirst(openQ.count).dropLast(closeQ.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    changed = true
                    break
                }
            }
        }
        return s
    }
    
    // MARK: - Destination Directory & Output File URL Resolution
    
    /// Resolves and validates a destination directory path from user input or CLI.
    /// - Parameters:
    ///   - rawInput: Raw path string entered by user or passed via CLI.
    ///   - baseDirectory: Optional explicit base directory for resolving relative paths (e.g., CLI startup working directory).
    ///                    Pass `nil` in UI dialogs so relative paths are rejected rather than resolved against an implicit CWD.
    public static func resolveDestinationDirectoryURL(_ rawInput: String, baseDirectory: URL? = nil) throws -> URL {
        if rawInput.contains("\0") || rawInput.contains("\n") || rawInput.contains("\r") {
            throw UserPathError.invalidCharacters(rawInput)
        }
        
        let cleaned = cleanUserInputPath(rawInput)
        guard !cleaned.isEmpty else {
            throw UserPathError.emptyPath
        }
        
        if cleaned.hasPrefix("~") {
            throw UserPathError.invalidHomeDirectory(cleaned)
        }
        
        if cleaned.hasPrefix("/") {
            return URL(fileURLWithPath: cleaned, isDirectory: true).standardizedFileURL
        }
        
        // Relative path: only allowed when an explicit baseDirectory is provided (CLI)
        guard let base = baseDirectory else {
            throw UserPathError.relativePathNotAllowed(cleaned)
        }
        
        let normalizedBase = normalizeDirectoryURL(base)
        let resolved = URL(fileURLWithPath: cleaned, isDirectory: true, relativeTo: normalizedBase).standardizedFileURL
        return URL(fileURLWithPath: resolved.path, isDirectory: true)
    }
    
    /// Resolves an input file or directory path from CLI arguments using an explicit base working directory.
    public static func resolveInputFileURL(_ rawInput: String, baseDirectory: URL) throws -> URL {
        if rawInput.contains("\0") {
            throw UserPathError.invalidCharacters(rawInput)
        }
        let cleaned = cleanUserInputPath(rawInput)
        guard !cleaned.isEmpty else {
            throw UserPathError.emptyPath
        }
        if cleaned.hasPrefix("~") {
            throw UserPathError.invalidHomeDirectory(cleaned)
        }
        if cleaned.hasPrefix("/") {
            return normalizeFileURL(URL(fileURLWithPath: cleaned))
        }
        let normalizedBase = normalizeDirectoryURL(baseDirectory)
        let resolved = URL(fileURLWithPath: cleaned, relativeTo: normalizedBase).standardizedFileURL
        return normalizeFileURL(resolved)
    }
    
    /// Validates and normalizes an archive file name entered in the "Compress To" dialog.
    /// - Forbids hierarchical path separators (`/`, `\`, `:`) and control characters.
    /// - Ensures a single `.zip` extension (never `.zip.zip`).
    /// - Preserves dots, spaces, and Unicode characters in the base name.
    public static func validateAndNormalizeArchiveFileName(_ rawName: String) throws -> String {
        var name = stripSurroundingQuotes(rawName.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !name.isEmpty else {
            throw UserPathError.invalidArchiveName("Vui lòng nhập tên file nén (.zip).")
        }
        
        if name.contains("\0") || name.contains("\n") || name.contains("\r") {
            throw UserPathError.invalidArchiveName("Tên file nén chứa ký tự điều khiển không hợp lệ.")
        }
        
        if name.contains("/") || name.contains("\\") || name.contains(":") {
            throw UserPathError.invalidArchiveName("Tên file nén không được chứa đường dẫn phân cấp ('/', '\\' hoặc ':'). Vui lòng chỉ nhập tên file.")
        }
        
        // Collapse duplicate .zip extensions (e.g., "Archive.zip.zip" -> "Archive.zip")
        while name.lowercased().hasSuffix(".zip.zip") && name.count > 8 {
            name = String(name.dropLast(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Strip ".zip" temporarily to validate base name
        let baseName: String
        if name.lowercased().hasSuffix(".zip") {
            baseName = String(name.dropLast(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            baseName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        if baseName.isEmpty || baseName == "." || baseName == ".." {
            throw UserPathError.invalidArchiveName("Tên file nén \"\(rawName)\" không hợp lệ. Vui lòng nhập tên hợp lệ trước phần mở rộng .zip.")
        }
        
        return "\(baseName).zip"
    }
    
    // MARK: - Default Paths & Archive Naming Semantics
    
    /// Default directory for Quick Extract and initial Extract To dialog: always the archive's containing folder.
    public static func defaultExtractionDirectory(for archiveURL: URL) -> URL {
        return normalizeFileURL(archiveURL).deletingLastPathComponent()
    }
    
    /// Default directory for Quick Compress and initial Compress To dialog: containing folder of the first source item.
    public static func defaultCompressionDirectory(for rawSources: [URL]) -> URL {
        let sources = deduplicateURLs(rawSources)
        guard let first = sources.first else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return normalizeFileURL(first).deletingLastPathComponent()
    }
    
    /// Computes the default `.zip` filename for compressing one or more source items.
    /// - Single directory `Folder.v1.4.1` -> `Folder.v1.4.1.zip` (preserves dots in directory names!).
    /// - Single file `report.pdf` -> `report.zip`.
    /// - Multiple items -> `Archive.zip`.
    public static func defaultArchiveFileName(for rawSources: [URL]) -> String {
        let sources = deduplicateURLs(rawSources)
        guard sources.count == 1, let rawFirst = sources.first else {
            return "Archive.zip"
        }
        
        let first = normalizeFileURL(rawFirst)
        let filename = first.lastPathComponent
        guard !filename.isEmpty && filename != "/" else {
            return "Archive.zip"
        }
        
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir)
        let treatAsDirectory = (exists && isDir.boolValue) || rawFirst.hasDirectoryPath
        
        let base: String
        if treatAsDirectory {
            // Directory: keep the entire directory name intact (including dots, Unicode, spaces)
            base = filename
        } else {
            // Regular file: remove only the last file extension (unless it's a dotfile like ".env")
            let stripped = (filename as NSString).deletingPathExtension
            if stripped.isEmpty || (filename.hasPrefix(".") && !String(filename.dropFirst()).contains(".")) {
                base = filename
            } else {
                base = stripped
            }
        }
        
        let cleanBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanBase.isEmpty || cleanBase == "." || cleanBase == ".." {
            return "Archive.zip"
        }
        if cleanBase.lowercased().hasSuffix(".zip") {
            return cleanBase
        }
        return "\(cleanBase).zip"
    }
    
    /// Computes the clean base name of an archive for enclosing folder creation.
    /// Properly strips multipart suffixes (`.part1.rar`, `.7z.001`, `.z01`, `.r00`) and compound extensions (`.tar.gz`, `.tar.bz2`, `.tar.xz`, `.tgz`, etc.).
    public static func archiveBaseName(for archiveURL: URL) -> String {
        let filename = normalizeFileURL(archiveURL).lastPathComponent
        guard !filename.isEmpty && filename != "/" else { return "Archive" }
        
        // 1. Multipart patterns
        let multipartPatterns = [
            #"^(.*?)\.part\d+\.rar$"#,
            #"^(.*?)\.tar\.(?:gz|bz2|xz)\.\d{3,}$"#,
            #"^(.*?)\.(?:7z|zip|rar|tar)\.\d{3,}$"#,
            #"^(.*?)\.z\d{2,}$"#,
            #"^(.*?)\.r\d{2,}$"#,
            #"^(.*?)\.\d{3,}$"#
        ]
        for pattern in multipartPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: filename, options: [], range: NSRange(location: 0, length: filename.utf16.count)),
               let range = Range(match.range(at: 1), in: filename) {
                let candidate = String(filename[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty && candidate != "." && candidate != ".." {
                    return candidate
                }
            }
        }
        
        // 2. Compound extensions
        let lower = filename.lowercased()
        let compoundSuffixes = [".tar.gz", ".tar.bz2", ".tar.xz", ".tar.zst", ".tar.lzma", ".tgz", ".tbz2", ".tbz", ".txz"]
        for suffix in compoundSuffixes {
            if lower.hasSuffix(suffix) && filename.count > suffix.count {
                let candidate = String(filename.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty && candidate != "." && candidate != ".." {
                    return candidate
                }
            }
        }
        
        // 3. Standard single extension
        let stripped = (filename as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stripped.isEmpty && stripped != "." && stripped != ".." {
            return stripped
        }
        return "Archive"
    }
    
    // MARK: - Enclosing Folder & Duplicate Wrapper Prevention
    
    /// Compares two folder/file names using Unicode NFC canonical equivalence (case-insensitive).
    public static func normalizedFolderNameEqual(_ a: String, _ b: String) -> Bool {
        let normA = a.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping.lowercased()
        let normB = b.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping.lowercased()
        return !normA.isEmpty && normA == normB
    }
    
    /// Splits an archive entry path into clean relative components (normalizing `\` to `/`, resolving `..`, and ignoring `.` and empty segments).
    public static func splitArchiveEntryComponents(_ rawPath: String) -> [String] {
        let normalized = rawPath.replacingOccurrences(of: "\\", with: "/")
        let rawParts = normalized.split(separator: "/").map(String.init)
        var resolved: [String] = []
        for comp in rawParts {
            if comp.isEmpty || comp == "." {
                continue
            } else if comp == ".." {
                if resolved.isEmpty {
                    return []
                }
                resolved.removeLast()
            } else {
                resolved.append(comp)
            }
        }
        return resolved
    }
    
    /// Determines whether all meaningful entries in an archive already reside inside a single root directory matching `enclosingName`.
    /// Prevents creating duplicate `Video/Video/` structures when `createEnclosingFolder` is enabled.
    public static func archiveAlreadyHasSingleRootDirectory(entries: [ArchiveEntryInfo], matching enclosingName: String) -> Bool {
        let meaningfulEntries = entries.filter { entry in
            let comps = splitArchiveEntryComponents(entry.path)
            guard let first = comps.first else { return false }
            if first == "__MACOSX" || first == ".DS_Store" {
                return false
            }
            return true
        }
        
        guard !meaningfulEntries.isEmpty else { return false }
        
        for entry in meaningfulEntries {
            let comps = splitArchiveEntryComponents(entry.path)
            guard let first = comps.first else { continue }
            
            // If there is a single-component entry that is NOT a directory, it's a loose root file
            if comps.count == 1 && !entry.isDirectory {
                return false
            }
            
            if !normalizedFolderNameEqual(first, enclosingName) {
                return false
            }
        }
        
        return true
    }
    
    /// Determines whether an extracted staging directory already has a single top-level directory matching `enclosingName`.
    public static func stagingDirectoryHasSingleRootDirectory(at stagingDir: URL, matching enclosingName: String) -> Bool {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: stagingDir.path) else { return false }
        let meaningful = items.filter { $0 != "__MACOSX" && $0 != ".DS_Store" }
        guard meaningful.count == 1, let singleName = meaningful.first else { return false }
        guard normalizedFolderNameEqual(singleName, enclosingName) else { return false }
        
        let singleURL = stagingDir.appendingPathComponent(singleName)
        var st = stat()
        guard lstat(singleURL.path, &st) == 0 else { return false }
        return (st.st_mode & S_IFMT) == S_IFDIR
    }
    
    /// Resolves the effective extraction root directory and reported destination URL for an archive.
    /// - When `options.createEnclosingFolder == false`: extracts directly into `options.destinationDirectory` (never adds a wrapper).
    /// - When `options.createEnclosingFolder == true`: adds `<archiveBaseName>` wrapper ONLY if the archive does not already have
    ///   an equivalent root folder AND the destination directory does not already end with `<archiveBaseName>`.
    public static func resolveEffectiveExtractionDirectory(
        archiveURL: URL,
        options: ExtractionOptions,
        entries: [ArchiveEntryInfo]
    ) -> (extractionRoot: URL, reportedDestination: URL, createdWrapperDirectory: URL?) {
        let baseDir = normalizeDirectoryURL(options.destinationDirectory)
        
        guard options.createEnclosingFolder else {
            return (extractionRoot: baseDir, reportedDestination: baseDir, createdWrapperDirectory: nil)
        }
        
        let enclosingName = archiveBaseName(for: archiveURL)
        
        // 1. If the archive already contains a single root folder matching enclosingName, do not wrap again (avoid Video/Video/)
        if archiveAlreadyHasSingleRootDirectory(entries: entries, matching: enclosingName) {
            let existingRootURL = baseDir.appendingPathComponent(enclosingName, isDirectory: true)
            return (extractionRoot: baseDir, reportedDestination: existingRootURL, createdWrapperDirectory: nil)
        }
        
        // 2. If the user's selected destination directory itself is already named enclosingName, do not wrap again
        if normalizedFolderNameEqual(baseDir.lastPathComponent, enclosingName) {
            return (extractionRoot: baseDir, reportedDestination: baseDir, createdWrapperDirectory: nil)
        }
        
        // 3. Create single enclosing wrapper directory
        let wrapperURL = baseDir.appendingPathComponent(enclosingName, isDirectory: true)
        return (extractionRoot: wrapperURL, reportedDestination: wrapperURL, createdWrapperDirectory: wrapperURL)
    }
    
    // MARK: - Zip-Slip, Path Traversal & Symlink Containment
    
    /// Sanitizes and validates an archive entry path against a base destination directory.
    /// Enforces both lexical component traversal checks and canonical on-disk symlink containment checks.
    public static func resolveSafeDestinationURL(for entryPath: String, in destinationDirectory: URL) throws -> URL {
        // 1. Reject null bytes and control characters
        if entryPath.contains("\0") {
            throw PathError.illegalCharacters(entryPath)
        }
        
        let cleaned = entryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            throw PathError.emptyPath
        }
        
        // Normalize Windows backslashes to POSIX slashes
        var relativePath = cleaned.replacingOccurrences(of: "\\", with: "/")
        
        // Reject Windows drive-letter prefix (e.g., "C:/..." or "D:...")
        if relativePath.count >= 2 {
            let firstChar = relativePath[relativePath.startIndex]
            let secondChar = relativePath[relativePath.index(after: relativePath.startIndex)]
            if secondChar == ":" && firstChar.isLetter {
                throw PathError.pathTraversalDetected(entryPath)
            }
        }
        
        // Strip leading slashes
        while relativePath.hasPrefix("/") {
            relativePath.removeFirst()
        }
        
        // Split components and verify no traversal above root (depth < 0)
        let rawComponents = relativePath.split(separator: "/").map(String.init)
        var resolvedComponents: [String] = []
        for comp in rawComponents {
            if comp == "." || comp.isEmpty {
                continue
            } else if comp == ".." {
                if resolvedComponents.isEmpty {
                    throw PathError.pathTraversalDetected(entryPath)
                }
                resolvedComponents.removeLast()
            } else {
                resolvedComponents.append(comp)
            }
        }
        
        let baseStandardized = normalizeDirectoryURL(destinationDirectory)
        let canonicalBase = canonicalPath(for: baseStandardized, followSymlinks: true)
        
        // If entry is just "." or "./", return baseStandardized directly
        if resolvedComponents.isEmpty {
            return baseStandardized
        }
        
        // Walk down components and verify no intermediate directory on disk is a symlink pointing outside canonicalBase
        var currentURL = baseStandardized
        for (index, comp) in resolvedComponents.enumerated() {
            currentURL = currentURL.appendingPathComponent(comp)
            let isIntermediate = index < (resolvedComponents.count - 1)
            
            var st = stat()
            if lstat(currentURL.path, &st) == 0 {
                let mode = st.st_mode & S_IFMT
                if isIntermediate {
                    if mode == S_IFLNK {
                        // Intermediate component is a symlink: check where it resolves!
                        let resolvedTarget = canonicalPath(for: currentURL, followSymlinks: true)
                        if !isCanonicallyContained(path: resolvedTarget, within: canonicalBase) {
                            throw PathError.pathTraversalDetected(entryPath)
                        }
                    }
                }
            }
        }
        
        let targetURL = currentURL.standardizedFileURL
        
        // Verify lexical containment within baseStandardized
        if !isCanonicallyContained(path: targetURL.path, within: baseStandardized.path) {
            throw PathError.pathTraversalDetected(entryPath)
        }
        
        // Verify canonical containment of parent directory within canonicalBase
        let canonicalTargetParent = canonicalPath(for: targetURL.deletingLastPathComponent(), followSymlinks: true)
        if !isCanonicallyContained(path: canonicalTargetParent, within: canonicalBase) {
            throw PathError.pathTraversalDetected(entryPath)
        }
        
        return targetURL
    }
    
    /// Checks whether `path` is equal to `base` or strictly a descendant inside `base` on a path-component boundary (`/`).
    /// Uses Unicode NFC normalization so APFS NFD and Swift NFC strings match accurately.
    public static func isCanonicallyContained(path: String, within base: String) -> Bool {
        let normPath = path.precomposedStringWithCanonicalMapping
        var normBase = base.precomposedStringWithCanonicalMapping
        while normBase.count > 1 && normBase.hasSuffix("/") {
            normBase.removeLast()
        }
        
        if normPath == normBase {
            return true
        }
        let prefix = normBase == "/" ? "/" : (normBase + "/")
        return normPath.hasPrefix(prefix)
    }
    
    /// Computes the relative path of `itemURL` inside `baseDirectoryURL` with strict path-component boundary checking.
    public static func relativePath(of itemURL: URL, from baseDirectoryURL: URL) -> String? {
        let canonicalBase = canonicalPath(for: baseDirectoryURL, followSymlinks: true).precomposedStringWithCanonicalMapping
        let canonicalItem = canonicalPath(for: itemURL, followSymlinks: false).precomposedStringWithCanonicalMapping
        
        var cleanBase = canonicalBase
        while cleanBase.count > 1 && cleanBase.hasSuffix("/") {
            cleanBase.removeLast()
        }
        
        let prefix = cleanBase == "/" ? "/" : (cleanBase + "/")
        guard canonicalItem.hasPrefix(prefix) else {
            return nil
        }
        let rel = String(canonicalItem.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return rel.isEmpty ? nil : rel
    }
    
    /// Checks if any filesystem entry (including a broken/dangling symlink) exists at `url` using `lstat`.
    public static func itemExistsIncludingSymlink(at url: URL, isDirectory: UnsafeMutablePointer<ObjCBool>? = nil, isSymlink: UnsafeMutablePointer<Bool>? = nil) -> Bool {
        var st = stat()
        let path = url.path
        guard lstat(path, &st) == 0 else {
            isDirectory?.pointee = false
            isSymlink?.pointee = false
            return false
        }
        let fileType = st.st_mode & S_IFMT
        let link = (fileType == S_IFLNK)
        isSymlink?.pointee = link
        
        if link {
            // For a symlink, only treat as directory if callers explicitly inspect target, but for conflict safety
            // a symlink itself is a link entry, not a real directory tree.
            isDirectory?.pointee = false
        } else {
            isDirectory?.pointee = ObjCBool(fileType == S_IFDIR)
        }
        return true
    }
    
    /// Generates a non-conflicting file URL by appending an incremental counter (e.g., "file (1).txt").
    /// Uses `itemExistsIncludingSymlink` so broken symlinks are also not collided with.
    public static func generateNonConflictingURL(for fileURL: URL) -> URL {
        let normalized = normalizeFileURL(fileURL)
        let parent = normalized.deletingLastPathComponent()
        let filename = normalized.lastPathComponent
        
        // Handle compound extensions cleanly when renaming (e.g. .tar.gz)
        let lower = filename.lowercased()
        let compoundSuffixes = [".tar.gz", ".tar.bz2", ".tar.xz", ".tgz", ".tbz2", ".tbz", ".txz"]
        var base = ""
        var extWithDot = ""
        
        var matchedCompound = false
        for suffix in compoundSuffixes {
            if lower.hasSuffix(suffix) && filename.count > suffix.count {
                base = String(filename.dropLast(suffix.count))
                extWithDot = String(filename.suffix(suffix.count))
                matchedCompound = true
                break
            }
        }
        
        if !matchedCompound {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: normalized.path, isDirectory: &isDir)
            if exists && isDir.boolValue {
                base = filename
                extWithDot = ""
            } else {
                let ext = normalized.pathExtension
                let stripped = normalized.deletingPathExtension().lastPathComponent
                if ext.isEmpty || stripped.isEmpty {
                    base = filename
                    extWithDot = ""
                } else {
                    base = stripped
                    extWithDot = ".\(ext)"
                }
            }
        }
        
        var counter = 1
        var candidate: URL
        repeat {
            let newName = "\(base) (\(counter))\(extWithDot)"
            candidate = parent.appendingPathComponent(newName)
            counter += 1
        } while itemExistsIncludingSymlink(at: candidate)
        
        return candidate
    }
    
    /// Resolves canonical POSIX path using `realpath(3)`, resolving symlinks (such as macOS `/tmp` -> `/private/tmp`).
    /// When `followSymlinks` is `false`, or when the target file/directory does not yet exist on disk,
    /// walks up to the nearest existing ancestor directory, resolves it via `realpath(3)`, and appends the remaining components.
    public static func canonicalPath(for url: URL, followSymlinks: Bool = true) -> String {
        let standardized = normalizeFileURL(url)
        let rawPath = standardized.path
        
        var isSymlink = false
        if !followSymlinks {
            var st = stat()
            if lstat(rawPath, &st) == 0 && (st.st_mode & S_IFMT) == S_IFLNK {
                isSymlink = true
            }
        }
        
        var resolved = [CChar](repeating: 0, count: Int(PATH_MAX))
        if !isSymlink, let ptr = realpath(rawPath, &resolved) {
            return String(cString: ptr)
        }
        
        // Walk up ancestors until we find an existing directory that realpath(3) can resolve
        var currentURL = standardized.deletingLastPathComponent()
        var trailingComponents: [String] = [standardized.lastPathComponent]
        
        while !currentURL.path.isEmpty {
            if let ptr = realpath(currentURL.path, &resolved) {
                var result = String(cString: ptr)
                for comp in trailingComponents.reversed() where !comp.isEmpty && comp != "/" {
                    result = (result as NSString).appendingPathComponent(comp)
                }
                return result
            }
            if currentURL.path == "/" { break }
            trailingComponents.append(currentURL.lastPathComponent)
            let parent = currentURL.deletingLastPathComponent()
            if parent.path == currentURL.path { break }
            currentURL = parent
        }
        
        return rawPath
    }
    
    /// Checks whether a filename is an internal UpackX temporary/staging artifact that should never be archived or extracted.
    public static func isInternalStagingArtifact(name: String) -> Bool {
        return name.hasPrefix(".upackx_compress_") ||
               name.hasPrefix(".upackx_backup_") ||
               name.hasPrefix(".upackx_staging_") ||
               name.hasPrefix(".upackx_extract_backup_") ||
               name.hasSuffix(".upackx_part")
    }
}
