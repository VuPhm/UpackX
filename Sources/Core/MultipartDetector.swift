import Foundation

/// Defines a recognized multi-part volume format
public enum MultipartType: Equatable {
    case rarPartN(baseName: String, partNumber: Int, padding: Int)     // e.g., archive.part1.rar, archive.part01.rar
    case rarLegacy(baseName: String, partNumber: Int)                  // e.g., archive.rar (part 1), archive.r00 (part 2)
    case sevenZip00N(baseName: String, partNumber: Int)                // e.g., archive.7z.001, archive.001
    case zipZ0N(baseName: String, partNumber: Int)                     // e.g., archive.z01, archive.z02, archive.zip
    case none
}

/// Represents a grouped multi-volume archive set with validation state
public struct MultipartGroup {
    public let baseName: String
    public let multipartType: MultipartType
    public let primaryVolumeURL: URL
    public let allVolumeURLs: [URL]
    public let isComplete: Bool
    public let missingPartNumbers: [Int]
    public let missingPartNames: [String]
    
    public init(baseName: String,
                multipartType: MultipartType,
                primaryVolumeURL: URL,
                allVolumeURLs: [URL],
                isComplete: Bool,
                missingPartNumbers: [Int] = [],
                missingPartNames: [String] = []) {
        self.baseName = baseName
        self.multipartType = multipartType
        self.primaryVolumeURL = primaryVolumeURL
        self.allVolumeURLs = allVolumeURLs
        self.isComplete = isComplete
        self.missingPartNumbers = missingPartNumbers
        self.missingPartNames = missingPartNames
    }
}

/// Task item in the extraction queue
public struct ExtractionTaskItem {
    public let archiveURL: URL
    public let isMultipart: Bool
    public let multipartGroup: MultipartGroup?
    
    public init(archiveURL: URL, isMultipart: Bool = false, multipartGroup: MultipartGroup? = nil) {
        self.archiveURL = archiveURL
        self.isMultipart = isMultipart
        self.multipartGroup = multipartGroup
    }
}

public final class MultipartDetector {
    
    /// Analyzes an archive filename to determine if it belongs to a multi-part volume set
    public static func detectMultipartType(from url: URL) -> MultipartType {
        let filename = url.lastPathComponent
        
        // 1. Check for .part(\d+).rar (case-insensitive)
        let partRarRegex = try? NSRegularExpression(pattern: #"^(.*?)\.part(\d+)\.rar$"#, options: .caseInsensitive)
        if let match = partRarRegex?.firstMatch(in: filename, options: [], range: NSRange(location: 0, length: filename.utf16.count)) {
            if let baseRange = Range(match.range(at: 1), in: filename),
               let numRange = Range(match.range(at: 2), in: filename) {
                let numStr = String(filename[numRange])
                if let num = Int(numStr) {
                    return .rarPartN(baseName: String(filename[baseRange]), partNumber: num, padding: numStr.count)
                }
            }
        }
        
        // 2. Check for .7z.(\d{3,}) or .(\d{3,})
        let sevenZipNumRegex = try? NSRegularExpression(pattern: #"^(.*?)(?:\.7z)?\.(\d{3,})$"#, options: .caseInsensitive)
        if let match = sevenZipNumRegex?.firstMatch(in: filename, options: [], range: NSRange(location: 0, length: filename.utf16.count)) {
            if let baseRange = Range(match.range(at: 1), in: filename),
               let numRange = Range(match.range(at: 2), in: filename),
               let num = Int(filename[numRange]) {
                return .sevenZip00N(baseName: String(filename[baseRange]), partNumber: num)
            }
        }
        
        // 3. Check for .z(\d{2,}) or .zip with matching .z01 peer
        let zNumRegex = try? NSRegularExpression(pattern: #"^(.*?)\.z(\d{2,})$"#, options: .caseInsensitive)
        if let match = zNumRegex?.firstMatch(in: filename, options: [], range: NSRange(location: 0, length: filename.utf16.count)) {
            if let baseRange = Range(match.range(at: 1), in: filename),
               let numRange = Range(match.range(at: 2), in: filename),
               let num = Int(filename[numRange]) {
                return .zipZ0N(baseName: String(filename[baseRange]), partNumber: num)
            }
        }
        
        // Check if file.zip has a companion file.z01 in the same directory
        if url.pathExtension.lowercased() == "zip" {
            let base = url.deletingPathExtension().lastPathComponent
            let parent = url.deletingLastPathComponent()
            let z01 = parent.appendingPathComponent("\(base).z01")
            if FileManager.default.fileExists(atPath: z01.path) {
                return .zipZ0N(baseName: base, partNumber: 0) // .zip is the header/final volume in split zip
            }
        }
        
        // 4. Check for legacy RAR format: archive.rar + archive.r00, archive.r01...
        let rNumRegex = try? NSRegularExpression(pattern: #"^(.*?)\.r(\d{2})$"#, options: .caseInsensitive)
        if let match = rNumRegex?.firstMatch(in: filename, options: [], range: NSRange(location: 0, length: filename.utf16.count)) {
            if let baseRange = Range(match.range(at: 1), in: filename),
               let numRange = Range(match.range(at: 2), in: filename),
               let num = Int(filename[numRange]) {
                return .rarLegacy(baseName: String(filename[baseRange]), partNumber: num + 2) // r00 is part 2
            }
        }
        if url.pathExtension.lowercased() == "rar" {
            let base = url.deletingPathExtension().lastPathComponent
            let parent = url.deletingLastPathComponent()
            let r00 = parent.appendingPathComponent("\(base).r00")
            if FileManager.default.fileExists(atPath: r00.path) {
                return .rarLegacy(baseName: base, partNumber: 1) // .rar is part 1
            }
        }
        
        return .none
    }
    
    /// Scans the directory containing `url` to discover all sibling volumes of the same multipart archive.
    /// Validates completeness and detects missing parts.
    public static func inspectMultipartSet(for url: URL) -> MultipartGroup? {
        let type = detectMultipartType(from: url)
        if case .none = type { return nil }
        
        let parentDir = url.deletingLastPathComponent()
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: parentDir.path) else { return nil }
        
        var siblingURLs: [URL] = []
        var partNumbersFound: Set<Int> = []
        
        switch type {
        case .rarPartN(let baseName, _, _):
            for file in files {
                let fileURL = parentDir.appendingPathComponent(file)
                if case .rarPartN(let b, let num, _) = detectMultipartType(from: fileURL), b.lowercased() == baseName.lowercased() {
                    siblingURLs.append(fileURL)
                    partNumbersFound.insert(num)
                }
            }
            siblingURLs.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            
            // Check continuity
            let maxPart = partNumbersFound.max() ?? 1
            var missingParts: [Int] = []
            var missingNames: [String] = []
            for i in 1...maxPart {
                if !partNumbersFound.contains(i) {
                    missingParts.append(i)
                    missingNames.append("\(baseName).part\(i).rar")
                }
            }
            
            guard let primary = siblingURLs.first else { return nil }
            return MultipartGroup(
                baseName: baseName,
                multipartType: type,
                primaryVolumeURL: primary,
                allVolumeURLs: siblingURLs,
                isComplete: missingParts.isEmpty && partNumbersFound.contains(1),
                missingPartNumbers: missingParts,
                missingPartNames: missingNames
            )
            
        case .sevenZip00N(let baseName, _):
            for file in files {
                let fileURL = parentDir.appendingPathComponent(file)
                if case .sevenZip00N(let b, let num) = detectMultipartType(from: fileURL), b.lowercased() == baseName.lowercased() {
                    siblingURLs.append(fileURL)
                    partNumbersFound.insert(num)
                }
            }
            siblingURLs.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            
            let maxPart = partNumbersFound.max() ?? 1
            var missingParts: [Int] = []
            var missingNames: [String] = []
            for i in 1...maxPart {
                if !partNumbersFound.contains(i) {
                    missingParts.append(i)
                    let formattedNum = String(format: "%03d", i)
                    missingNames.append("\(baseName).7z.\(formattedNum)")
                }
            }
            
            guard let primary = siblingURLs.first else { return nil }
            return MultipartGroup(
                baseName: baseName,
                multipartType: type,
                primaryVolumeURL: primary,
                allVolumeURLs: siblingURLs,
                isComplete: missingParts.isEmpty && partNumbersFound.contains(1),
                missingPartNumbers: missingParts,
                missingPartNames: missingNames
            )
            
        case .zipZ0N(let baseName, _):
            var zipURL: URL? = nil
            for file in files {
                let fileURL = parentDir.appendingPathComponent(file)
                let fType = detectMultipartType(from: fileURL)
                if case .zipZ0N(let b, let num) = fType, b.lowercased() == baseName.lowercased() {
                    siblingURLs.append(fileURL)
                    if num == 0 {
                        zipURL = fileURL
                    } else {
                        partNumbersFound.insert(num)
                    }
                }
            }
            siblingURLs.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            
            let maxPart = partNumbersFound.max() ?? 0
            var missingParts: [Int] = []
            var missingNames: [String] = []
            for i in 1...maxPart {
                if !partNumbersFound.contains(i) {
                    missingParts.append(i)
                    let formattedNum = String(format: "%02d", i)
                    missingNames.append("\(baseName).z\(formattedNum)")
                }
            }
            if zipURL == nil {
                missingNames.append("\(baseName).zip")
            }
            
            let primary = zipURL ?? siblingURLs.first!
            return MultipartGroup(
                baseName: baseName,
                multipartType: type,
                primaryVolumeURL: primary,
                allVolumeURLs: siblingURLs,
                isComplete: missingParts.isEmpty && zipURL != nil,
                missingPartNumbers: missingParts,
                missingPartNames: missingNames
            )
            
        case .rarLegacy(let baseName, _):
            for file in files {
                let fileURL = parentDir.appendingPathComponent(file)
                if case .rarLegacy(let b, let num) = detectMultipartType(from: fileURL), b.lowercased() == baseName.lowercased() {
                    siblingURLs.append(fileURL)
                    partNumbersFound.insert(num)
                }
            }
            siblingURLs.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            
            let maxPart = partNumbersFound.max() ?? 1
            var missingParts: [Int] = []
            var missingNames: [String] = []
            for i in 1...maxPart {
                if !partNumbersFound.contains(i) {
                    missingParts.append(i)
                    if i == 1 {
                        missingNames.append("\(baseName).rar")
                    } else {
                        let formattedNum = String(format: "%02d", i - 2)
                        missingNames.append("\(baseName).r\(formattedNum)")
                    }
                }
            }
            
            guard let primary = siblingURLs.first else { return nil }
            return MultipartGroup(
                baseName: baseName,
                multipartType: type,
                primaryVolumeURL: primary,
                allVolumeURLs: siblingURLs,
                isComplete: missingParts.isEmpty && partNumbersFound.contains(1),
                missingPartNumbers: missingParts,
                missingPartNames: missingNames
            )
            
        case .none:
            return nil
        }
    }
    
    /// Groups a selection of input URLs into discrete tasks, deduplicating multiple selected parts of the same volume set.
    public static func groupArchives(_ urls: [URL]) -> [ExtractionTaskItem] {
        var processedBases: Set<String> = []
        var tasks: [ExtractionTaskItem] = []
        
        for url in urls {
            if let group = inspectMultipartSet(for: url) {
                let key = group.baseName.lowercased()
                if !processedBases.contains(key) {
                    processedBases.insert(key)
                    tasks.append(ExtractionTaskItem(
                        archiveURL: group.primaryVolumeURL,
                        isMultipart: true,
                        multipartGroup: group
                    ))
                }
            } else {
                tasks.append(ExtractionTaskItem(archiveURL: url, isMultipart: false, multipartGroup: nil))
            }
        }
        
        return tasks
    }
}
