import Foundation

enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

/// A single turn in the conversation. Value type so it can be snapshotted immutably into
/// view state (the retired Android build mutated a shared list in place — its C2 defect).
struct ChatMessage: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var role: MessageRole
    var content: String
    var createdAt: Date

    /// Present when this assistant turn requested a tool call (for display/audit).
    var toolCallSummary: String?
    /// Present on tool-result turns.
    var toolCallId: String?
    /// Model that produced this turn, if known.
    var modelUsed: String?

    init(id: UUID = UUID(),
         role: MessageRole,
         content: String,
         createdAt: Date = Date(),
         toolCallSummary: String? = nil,
         toolCallId: String? = nil,
         modelUsed: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.toolCallSummary = toolCallSummary
        self.toolCallId = toolCallId
        self.modelUsed = modelUsed
    }
}
