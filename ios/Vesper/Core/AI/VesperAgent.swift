import Foundation
import Observation

/// Orchestrates the conversation and the agentic tool loop.
///
/// UI state is exposed as value-type snapshots (`messages` is reassigned, never mutated in place)
/// — the structural fix for the retired Android build's C2 defect. A single `isLoading` guard
/// prevents overlapping turns (its H6 defect).
@MainActor
@Observable
final class VesperAgent {

    private(set) var messages: [ChatMessage] = []
    private(set) var isLoading = false
    private(set) var pendingApproval: PendingApproval?
    private(set) var progress: String?
    private(set) var error: String?
    private(set) var sessionId: String

    @ObservationIgnored private let client: OpenRouterClient
    @ObservationIgnored private let executor: CommandExecutor
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let audit: AuditService
    @ObservationIgnored private let persistence: PersistenceController?

    @ObservationIgnored private var apiMessages: [APIMessage] = []
    @ObservationIgnored private var approvalContinuation: CheckedContinuation<Bool, Never>?

    init(client: OpenRouterClient,
         executor: CommandExecutor,
         settings: SettingsStore,
         audit: AuditService,
         persistence: PersistenceController? = nil,
         sessionId: String = UUID().uuidString) {
        self.client = client
        self.executor = executor
        self.settings = settings
        self.audit = audit
        self.persistence = persistence
        self.sessionId = sessionId
        self.apiMessages = [.system(VesperPrompts.system)]
        self.executor.approvalHandler = { [weak self] pending in
            await self?.requestApproval(pending) ?? false
        }
    }

    // MARK: - Public API

    func sendMessage(_ text: String) async {
        guard !isLoading else { return } // in-flight guard
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard settings.hasApiKey else {
            error = "Add an OpenRouter API key in Settings to start."
            return
        }

        error = nil
        append(ChatMessage(role: .user, content: trimmed))
        apiMessages.append(.user(trimmed))

        isLoading = true
        defer { isLoading = false; progress = nil }
        await runLoop()
    }

    func startNewSession() {
        guard !isLoading else { return }
        sessionId = UUID().uuidString
        messages = []
        apiMessages = [.system(VesperPrompts.system)]
        error = nil
    }

    /// Restore the most recent conversation on launch. Tool turns are shown but not replayed into
    /// the model context (persisted messages don't carry tool-call structure), so the model
    /// continues from the user/assistant text turns.
    func restoreLastSession() {
        guard let persistence, let last = persistence.latestSessionId() else { return }
        let restored = persistence.loadMessages(sessionId: last)
        guard !restored.isEmpty else { return }
        sessionId = last
        messages = restored // assigned directly (not via append) so it isn't re-persisted
        apiMessages = [.system(VesperPrompts.system)]
        for message in restored {
            switch message.role {
            case .user: apiMessages.append(.user(message.content))
            case .assistant: apiMessages.append(.assistant(message.content))
            case .tool, .system: break
            }
        }
    }

    func approvePending() {
        approvalContinuation?.resume(returning: true)
        approvalContinuation = nil
    }

    func rejectPending() {
        approvalContinuation?.resume(returning: false)
        approvalContinuation = nil
    }

    // MARK: - Agent loop

    private func runLoop() async {
        let maxIterations = max(1, settings.aiMaxIterations)
        var iterations = 0

        while iterations < maxIterations {
            iterations += 1
            progress = "Thinking (\(iterations)/\(maxIterations))…"
            audit.log(.aiRequest, session: sessionId, metadata: ["messages": "\(apiMessages.count)"])

            let result = await client.chat(messages: apiMessages,
                                            apiKey: settings.apiKey ?? "",
                                            model: settings.selectedModel)

            switch result {
            case .failure(let message):
                error = message
                append(ChatMessage(role: .assistant, content: "⚠️ \(message)"))
                audit.log(.error, session: sessionId, summary: message, success: false)
                return

            case .success(let content, let toolCalls, let model):
                audit.log(.aiResponse, session: sessionId,
                          metadata: ["model": model, "tool_calls": "\(toolCalls.count)"])

                if toolCalls.isEmpty {
                    append(ChatMessage(role: .assistant, content: content, modelUsed: model))
                    apiMessages.append(.assistant(content))
                    return
                }

                let apiToolCalls = toolCalls.map {
                    APIToolCall(id: $0.id, type: "function",
                                function: APIFunctionCall(name: "execute_command", arguments: $0.rawArguments))
                }
                apiMessages.append(.assistant(content.isEmpty ? nil : content, toolCalls: apiToolCalls))
                if !content.isEmpty {
                    append(ChatMessage(role: .assistant, content: content, modelUsed: model))
                }

                for call in toolCalls {
                    let resultText = await handleToolCall(call)
                    apiMessages.append(.toolResult(resultText, callId: call.id))
                }
            }
        }

        append(ChatMessage(role: .assistant,
                           content: "Reached the maximum of \(maxIterations) steps. Ask me to continue if needed."))
    }

    private func handleToolCall(_ call: ParsedToolCall) async -> String {
        guard let command = call.command else {
            let message = call.parseError ?? "Invalid tool call."
            append(ChatMessage(role: .tool, content: "⚠️ \(message)"))
            return message
        }

        progress = "Executing \(command.action.displayName)…"
        append(ChatMessage(role: .tool,
                           content: "▶ \(command.action.displayName)",
                           toolCallSummary: describe(command)))

        let result = await executor.execute(command, sessionId: sessionId)
        let text = result.success ? result.output : "Error: \(result.output)"
        append(ChatMessage(role: .tool, content: text, toolCallId: call.id))
        return text
    }

    private func requestApproval(_ pending: PendingApproval) async -> Bool {
        pendingApproval = pending
        let approved = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            approvalContinuation = continuation
        }
        pendingApproval = nil
        return approved
    }

    // MARK: - Helpers

    private func append(_ message: ChatMessage) {
        messages = messages + [message] // value-type snapshot; never mutate the published array in place
        persistence?.saveMessage(message, sessionId: sessionId)
    }

    private func describe(_ command: ExecuteCommand) -> String {
        var parts = [command.action.rawValue]
        if let path = command.args.path { parts.append(path) }
        if let cmd = command.args.command { parts.append(cmd) }
        if !command.justification.isEmpty { parts.append("— \(command.justification)") }
        return parts.joined(separator: " ")
    }
}
