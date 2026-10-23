import Foundation

/// Strategy for resolving destination file conflicts
public enum ConflictStrategy: String, CaseIterable {
    case ask = "ask"
    case overwrite = "overwrite"
    case skip = "skip"
    case rename = "rename"
    
    public var displayName: String {
        switch self {
        case .ask: return "Hỏi khi trùng tên"
        case .overwrite: return "Ghi đè file cũ"
        case .skip: return "Bỏ qua file trùng"
        case .rename: return "Tự động đổi tên (Giữ cả hai)"
        }
    }
}

/// Decision made when resolving a single file conflict
public enum ConflictAction {
    case overwrite
    case skip
    case rename
    case cancel
}

public struct ConflictDecision {
    public let action: ConflictAction
    public let applyToAll: Bool
    
    public init(action: ConflictAction, applyToAll: Bool = false) {
        self.action = action
        self.applyToAll = applyToAll
    }
}

/// Callback invoked when a destination file conflict is detected
public typealias ConflictResolver = (_ existingFileURL: URL) -> ConflictDecision

/// Callback invoked to request archive password
public typealias PasswordProvider = () -> String?

/// Extraction options passed to the extractor
public struct ExtractionOptions {
    public var destinationDirectory: URL
    public var createEnclosingFolder: Bool
    public var conflictStrategy: ConflictStrategy
    public var password: String?
    public var conflictResolver: ConflictResolver?
    public var passwordProvider: PasswordProvider?
    
    public init(destinationDirectory: URL,
                createEnclosingFolder: Bool = false,
                conflictStrategy: ConflictStrategy = .ask,
                password: String? = nil,
                conflictResolver: ConflictResolver? = nil,
                passwordProvider: PasswordProvider? = nil) {
        self.destinationDirectory = destinationDirectory
        self.createEnclosingFolder = createEnclosingFolder
        self.conflictStrategy = conflictStrategy
        self.password = password
        self.conflictResolver = conflictResolver
        self.passwordProvider = passwordProvider
    }
}
