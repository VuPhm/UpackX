import Foundation

/// Architectural component for identifying and grouping multi-part volume sets (Stage 2 foundation).
public enum MultipartType {
    case rarPartN(baseName: String, partNumber: Int)        // e.g., file.part1.rar, file.part01.rar
    case sevenZip00N(baseName: String, partNumber: Int)     // e.g., file.7z.001, file.001
    case zipZ0N(baseName: String, partNumber: Int)          // e.g., file.z01, file.zip
    case none
}

public struct MultipartGroup {
    public let baseName: String
    public let primaryVolumeURL: URL
    public let allVolumeURLs: [URL]
    public let isComplete: Bool
}

public final class MultipartDetector {
    
    /// Analyzes an archive URL to determine if it is part of a multi-volume set
    public static func detectMultipartType(from url: URL) -> MultipartType {
        let filename = url.lastPathComponent
        
        // 1. Check for .part(\d+).rar (case-insensitive)
        let partRarRegex = try? NSRegularExpression(pattern: #"^(.*?)\.part(\d+)\.rar$"#, options: .caseInsensitive)
        if let match = partRarRegex?.firstMatch(in: filename, options: [], range: NSRange(location: 0, length: filename.utf16.count)) {
            if let baseRange = Range(match.range(at: 1), in: filename),
               let numRange = Range(match.range(at: 2), in: filename),
               let num = Int(filename[numRange]) {
                return .rarPartN(baseName: String(filename[baseRange]), partNumber: num)
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
        
        return .none
    }
    
    /// Groups a list of selected archive URLs, distinguishing multi-volume archives from independent archives.
    /// Ensures that only the primary (first) volume of a multi-part archive is queued for extraction.
    public static func groupArchives(_ urls: [URL]) -> (primaryArchives: [URL], volumeSets: [MultipartGroup]) {
        var independent: [URL] = []
        var detectedGroups: [String: [URL]] = [:]
        
        for url in urls {
            let type = detectMultipartType(from: url)
            switch type {
            case .none:
                independent.append(url)
            case .rarPartN(let base, _):
                detectedGroups[base + ".rar", default: []].append(url)
            case .sevenZip00N(let base, _):
                detectedGroups[base + ".7z", default: []].append(url)
            case .zipZ0N(let base, _):
                detectedGroups[base + ".zip", default: []].append(url)
            }
        }
        
        var volumeSets: [MultipartGroup] = []
        
        for (groupKey, vols) in detectedGroups {
            // Sort volumes to identify volume 1
            let sortedVols = vols.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            if let firstVol = sortedVols.first {
                independent.append(firstVol)
                volumeSets.append(MultipartGroup(
                    baseName: groupKey,
                    primaryVolumeURL: firstVol,
                    allVolumeURLs: sortedVols,
                    isComplete: true
                ))
            }
        }
        
        return (independent, volumeSets)
    }
}
