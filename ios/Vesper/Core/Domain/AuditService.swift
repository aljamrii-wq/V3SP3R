import Foundation
import Observation

/// Append-only action log. Keeps a bounded in-memory window for the UI and forwards every
/// entry to an optional persistence sink.
@MainActor
@Observable
final class AuditService {

    private(set) var recentEntries: [AuditEntry] = []
    private let maxInMemory = 200

    /// Persistence hook (set by the app container to a SwiftData-backed writer).
    @ObservationIgnored var sink: (@MainActor (AuditEntry) -> Void)?

    /// Replace the in-memory window with persisted entries (newest first) on launch.
    func hydrate(_ entries: [AuditEntry]) {
        recentEntries = Array(entries.prefix(maxInMemory))
    }

    func log(_ entry: AuditEntry) {
        recentEntries.insert(entry, at: 0)
        if recentEntries.count > maxInMemory {
            recentEntries.removeLast(recentEntries.count - maxInMemory)
        }
        sink?(entry)
    }

    func log(_ type: AuditActionType,
             session: String,
             summary: String = "",
             risk: RiskLevel? = nil,
             success: Bool? = nil,
             metadata: [String: String] = [:]) {
        log(AuditEntry(actionType: type,
                       sessionId: session,
                       summary: summary,
                       riskLevel: risk,
                       success: success,
                       metadata: metadata))
    }

    // MARK: - Export (roadmap-friendly; JSON is available now)

    func exportJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(recentEntries),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }
}
