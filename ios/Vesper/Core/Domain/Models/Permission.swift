import Foundation

/// Paths that are protected by default and require an explicit, time-boxed unlock.
enum ProtectedPaths {
    /// Prefixes considered protected (internal storage / firmware regions).
    static let prefixes: [String] = ["/int", "/dev", "/sys"]

    static func isProtected(_ path: String) -> Bool {
        let normalized = PathUtils.normalize(path)
        return prefixes.contains { normalized == $0 || normalized.hasPrefix($0 + "/") }
    }
}

/// A time-limited unlock for an otherwise-protected path prefix.
struct ProtectedUnlock: Identifiable, Sendable, Equatable {
    let id: UUID
    let pathPrefix: String
    let expiresAt: Date

    init(id: UUID = UUID(), pathPrefix: String, expiresAt: Date) {
        self.id = id
        self.pathPrefix = pathPrefix
        self.expiresAt = expiresAt
    }

    var isActive: Bool { expiresAt > Date() }

    func covers(_ path: String) -> Bool {
        guard isActive else { return false }
        let normalized = PathUtils.normalize(path)
        return normalized == pathPrefix || normalized.hasPrefix(pathPrefix + "/")
    }
}

/// A pending action awaiting the user's decision.
struct PendingApproval: Identifiable, Sendable, Equatable {
    let id: UUID
    let command: ExecuteCommand
    let riskLevel: RiskLevel
    let reason: String
    /// A unified diff to show for MEDIUM file writes (nil otherwise).
    let diff: String?
    let requiresHoldToConfirm: Bool

    init(id: UUID = UUID(),
         command: ExecuteCommand,
         riskLevel: RiskLevel,
         reason: String,
         diff: String? = nil,
         requiresHoldToConfirm: Bool) {
        self.id = id
        self.command = command
        self.riskLevel = riskLevel
        self.reason = reason
        self.diff = diff
        self.requiresHoldToConfirm = requiresHoldToConfirm
    }
}

/// Small, shared path helpers used by validation + protection + permissions.
enum PathUtils {
    /// Collapse `.`/`..` segments and duplicate slashes without touching the filesystem.
    static func normalize(_ path: String) -> String {
        let isAbsolute = path.hasPrefix("/")
        var stack: [String] = []
        for segment in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch segment {
            case ".": continue
            case "..": if !stack.isEmpty { stack.removeLast() }
            default: stack.append(String(segment))
            }
        }
        let joined = stack.joined(separator: "/")
        return isAbsolute ? "/" + joined : joined
    }
}
