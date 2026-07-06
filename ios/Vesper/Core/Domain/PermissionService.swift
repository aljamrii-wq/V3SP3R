import Foundation
import Observation

/// Manages time-limited unlocks for protected paths.
@MainActor
@Observable
final class PermissionService {

    private(set) var unlocks: [ProtectedUnlock] = []

    @discardableResult
    func unlock(prefix: String, duration: TimeInterval = 3600) -> ProtectedUnlock {
        let normalized = PathUtils.normalize(prefix)
        let unlock = ProtectedUnlock(pathPrefix: normalized, expiresAt: Date().addingTimeInterval(duration))
        unlocks.removeAll { $0.pathPrefix == normalized }
        unlocks.append(unlock)
        return unlock
    }

    func lock(_ id: UUID) {
        unlocks.removeAll { $0.id == id }
    }

    func lockAll() {
        unlocks.removeAll()
    }

    /// Currently-active unlocks (prunes expired ones as a side effect).
    func activeUnlocks() -> [ProtectedUnlock] {
        unlocks.removeAll { !$0.isActive }
        return unlocks
    }
}
