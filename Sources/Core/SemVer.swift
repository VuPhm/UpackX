import Foundation

public struct SemVer: Comparable, Equatable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?
    public let raw: String
    
    public init?(string: String) {
        var clean = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.lowercased().hasPrefix("v") {
            clean = String(clean.dropFirst())
        }
        self.raw = string
        
        let parts = clean.components(separatedBy: "-")
        let versionPart = parts[0]
        self.prerelease = parts.count > 1 ? parts.dropFirst().joined(separator: "-") : nil
        
        let numbers = versionPart.components(separatedBy: ".")
        guard numbers.count >= 2,
              let maj = Int(numbers[0]),
              let min = Int(numbers[1]) else {
            return nil
        }
        self.major = maj
        self.minor = min
        self.patch = numbers.count >= 3 ? (Int(numbers[2]) ?? 0) : 0
    }
    
    public var description: String {
        var s = "\(major).\(minor).\(patch)"
        if let pre = prerelease {
            s += "-\(pre)"
        }
        return s
    }
    
    public static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        
        // A release without pre-release tags has higher precedence than one with tags
        if lhs.prerelease == nil && rhs.prerelease != nil { return false }
        if lhs.prerelease != nil && rhs.prerelease == nil { return true }
        if let lp = lhs.prerelease, let rp = rhs.prerelease {
            return lp < rp
        }
        return false
    }
    
    public static func == (lhs: SemVer, rhs: SemVer) -> Bool {
        return lhs.major == rhs.major &&
               lhs.minor == rhs.minor &&
               lhs.patch == rhs.patch &&
               lhs.prerelease == rhs.prerelease
    }
}

