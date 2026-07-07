import Foundation

enum AuditActionType: String, Codable, Sendable {
    case aiRequest = "ai_request"
    case aiResponse = "ai_response"
    case commandReceived = "command_received"
    case commandExecuted = "command_executed"
    case commandBlocked = "command_blocked"
    case commandFailed = "command_failed"
    case approvalRequested = "approval_requested"
    case approvalGranted = "approval_granted"
    case approvalRejected = "approval_rejected"
    case connection = "connection"
    case error = "error"
}

/// An append-only record of something the agent or user did. Everything is auditable.
struct AuditEntry: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let timestamp: Date
    let actionType: AuditActionType
    let sessionId: String
    var summary: String
    var riskLevel: RiskLevel?
    var success: Bool?
    var metadata: [String: String]

    init(id: UUID = UUID(),
         timestamp: Date = Date(),
         actionType: AuditActionType,
         sessionId: String,
         summary: String = "",
         riskLevel: RiskLevel? = nil,
         success: Bool? = nil,
         metadata: [String: String] = [:]) {
        self.id = id
        self.timestamp = timestamp
        self.actionType = actionType
        self.sessionId = sessionId
        self.summary = summary
        self.riskLevel = riskLevel
        self.success = success
        self.metadata = metadata
    }
}
