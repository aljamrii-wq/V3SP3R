import Foundation
import SwiftData

/// SwiftData record for an audit entry.
@Model
final class AuditRecord {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var actionTypeRaw: String
    var sessionId: String
    var summary: String
    var riskRaw: String?
    var success: Bool?
    var metadataJSON: String

    init(id: UUID, timestamp: Date, actionTypeRaw: String, sessionId: String,
         summary: String, riskRaw: String?, success: Bool?, metadataJSON: String) {
        self.id = id
        self.timestamp = timestamp
        self.actionTypeRaw = actionTypeRaw
        self.sessionId = sessionId
        self.summary = summary
        self.riskRaw = riskRaw
        self.success = success
        self.metadataJSON = metadataJSON
    }
}

/// SwiftData record for a chat message.
@Model
final class ChatMessageRecord {
    @Attribute(.unique) var id: UUID
    var roleRaw: String
    var content: String
    var createdAt: Date
    var sessionId: String

    init(id: UUID, roleRaw: String, content: String, createdAt: Date, sessionId: String) {
        self.id = id
        self.roleRaw = roleRaw
        self.content = content
        self.createdAt = createdAt
        self.sessionId = sessionId
    }
}

/// Owns the SwiftData container and provides typed persistence. Real (versioned) migrations are a
/// roadmap item; the schema is intentionally simple and additive to keep future migration cheap.
@MainActor
final class PersistenceController {

    let container: ModelContainer

    init(inMemory: Bool = false) {
        do {
            if inMemory {
                container = try ModelContainer(
                    for: AuditRecord.self, ChatMessageRecord.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            } else {
                container = try ModelContainer(for: AuditRecord.self, ChatMessageRecord.self)
            }
        } catch {
            // Fall back to in-memory so the app still runs if the on-disk store can't be opened.
            container = try! ModelContainer(
                for: AuditRecord.self, ChatMessageRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
    }

    private var context: ModelContext { container.mainContext }

    // MARK: - Audit

    func persist(_ entry: AuditEntry) {
        let metadataJSON = (try? JSONEncoder().encode(entry.metadata))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        context.insert(AuditRecord(id: entry.id,
                                   timestamp: entry.timestamp,
                                   actionTypeRaw: entry.actionType.rawValue,
                                   sessionId: entry.sessionId,
                                   summary: entry.summary,
                                   riskRaw: entry.riskLevel?.rawValue,
                                   success: entry.success,
                                   metadataJSON: metadataJSON))
        try? context.save()
    }

    // MARK: - Chat

    func saveMessage(_ message: ChatMessage, sessionId: String) {
        context.insert(ChatMessageRecord(id: message.id,
                                         roleRaw: message.role.rawValue,
                                         content: message.content,
                                         createdAt: message.createdAt,
                                         sessionId: sessionId))
        try? context.save()
    }

    /// Most recent audit entries, newest first — used to hydrate the Audit tab on launch.
    func loadRecentAudit(limit: Int = 200) -> [AuditEntry] {
        var descriptor = FetchDescriptor<AuditRecord>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = limit
        let records = (try? context.fetch(descriptor)) ?? []
        return records.map { record in
            let metadata = record.metadataJSON.data(using: .utf8)
                .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
            return AuditEntry(id: record.id,
                              timestamp: record.timestamp,
                              actionType: AuditActionType(rawValue: record.actionTypeRaw) ?? .error,
                              sessionId: record.sessionId,
                              summary: record.summary,
                              riskLevel: record.riskRaw.flatMap { RiskLevel(rawValue: $0) },
                              success: record.success,
                              metadata: metadata)
        }
    }

    /// The session id of the most recently stored chat message (for restoring the last conversation).
    func latestSessionId() -> String? {
        var descriptor = FetchDescriptor<ChatMessageRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.sessionId
    }

    func loadMessages(sessionId: String) -> [ChatMessage] {
        let descriptor = FetchDescriptor<ChatMessageRecord>(
            predicate: #Predicate<ChatMessageRecord> { $0.sessionId == sessionId },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let records = (try? context.fetch(descriptor)) ?? []
        return records.map {
            ChatMessage(id: $0.id,
                        role: MessageRole(rawValue: $0.roleRaw) ?? .assistant,
                        content: $0.content,
                        createdAt: $0.createdAt)
        }
    }
}
