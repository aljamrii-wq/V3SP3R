import Foundation

// MARK: - Wire types

struct APIToolCall: Codable, Equatable {
    let id: String
    let type: String
    let function: APIFunctionCall
}

struct APIFunctionCall: Codable, Equatable {
    let name: String
    let arguments: String
}

/// A message in OpenRouter chat format.
struct APIMessage: Equatable {
    let role: String
    var content: String?
    var toolCalls: [APIToolCall]?
    var toolCallId: String?
    var name: String?

    static func system(_ text: String) -> APIMessage { APIMessage(role: "system", content: text) }
    static func user(_ text: String) -> APIMessage { APIMessage(role: "user", content: text) }
    static func assistant(_ text: String?, toolCalls: [APIToolCall]? = nil) -> APIMessage {
        APIMessage(role: "assistant", content: text, toolCalls: toolCalls)
    }
    static func toolResult(_ text: String, callId: String) -> APIMessage {
        APIMessage(role: "tool", content: text, toolCallId: callId)
    }

    func jsonObject() -> [String: Any] {
        var object: [String: Any] = ["role": role]
        object["content"] = content ?? NSNull()
        if let toolCalls {
            object["tool_calls"] = toolCalls.map { call -> [String: Any] in
                ["id": call.id,
                 "type": call.type,
                 "function": ["name": call.function.name, "arguments": call.function.arguments] as [String: Any]]
            }
        }
        if let toolCallId { object["tool_call_id"] = toolCallId }
        if let name { object["name"] = name }
        return object
    }
}

struct ParsedToolCall: Equatable {
    let id: String
    let command: ExecuteCommand?
    let rawArguments: String
    let parseError: String?
}

enum ChatResult {
    case success(content: String, toolCalls: [ParsedToolCall], model: String)
    case failure(String)
}

// MARK: - Client

/// Talks to OpenRouter's chat-completions endpoint with tool calling.
final class OpenRouterClient {

    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let session: URLSession
    private let rateLimiter = RateLimiter(maxRequests: 30, windowSeconds: 60)
    private let maxRetries = 3
    private let retryAfterCap: TimeInterval = 30

    init(session: URLSession = .shared) {
        self.session = session
    }

    func chat(messages: [APIMessage], apiKey: String, model: String) async -> ChatResult {
        guard !apiKey.isEmpty else { return .failure("No OpenRouter API key set. Add one in Settings.") }
        await rateLimiter.acquire()

        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { $0.jsonObject() },
            "tools": [Self.toolSchema],
            "tool_choice": "auto"
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return .failure("Failed to encode the request.")
        }

        do {
            let data = try await executeWithRetry(bodyData: bodyData, apiKey: apiKey)
            return Self.parseResponse(data)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - Networking

    private func executeWithRetry(bodyData: Data, apiKey: String) async throws -> Data {
        var lastError: Error = URLError(.unknown)
        for attempt in 0..<maxRetries {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 60
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("https://github.com/elder-plinius/V3SP3R", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("Vesper", forHTTPHeaderField: "X-Title")
            request.httpBody = bodyData

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { return data }
                switch http.statusCode {
                case 200..<300:
                    return data
                case 429, 500..<600:
                    lastError = OpenRouterError.http(http.statusCode, Self.errorMessage(data))
                    let retryAfter = Self.retryAfterSeconds(http) ?? pow(2.0, Double(attempt))
                    try await Task.sleep(for: .seconds(min(retryAfter, retryAfterCap)))
                default:
                    throw OpenRouterError.http(http.statusCode, Self.errorMessage(data))
                }
            } catch let error as OpenRouterError {
                throw error
            } catch {
                lastError = error
                try await Task.sleep(for: .seconds(min(pow(2.0, Double(attempt)), retryAfterCap)))
            }
        }
        throw lastError
    }

    private static func retryAfterSeconds(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(value) else { return nil }
        return max(0, seconds)
    }

    private static func errorMessage(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return "Request failed."
        }
        return message
    }

    // MARK: - Parsing

    static func parseResponse(_ data: Data) -> ChatResult {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure("Could not parse the model response.")
        }
        if let error = root["error"] as? [String: Any], let message = error["message"] as? String {
            return .failure(message)
        }
        let model = root["model"] as? String ?? "unknown"
        guard let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            return .failure("The model returned no choices.")
        }
        let content = message["content"] as? String ?? ""
        let rawToolCalls = message["tool_calls"] as? [[String: Any]] ?? []
        let parsed = rawToolCalls.compactMap { parseToolCall($0) }

        if parsed.isEmpty && content.isEmpty {
            return .failure("The model returned an empty response.")
        }
        return .success(content: content, toolCalls: parsed, model: model)
    }

    static func parseToolCall(_ raw: [String: Any]) -> ParsedToolCall? {
        guard let function = raw["function"] as? [String: Any] else { return nil }
        let id = raw["id"] as? String ?? UUID().uuidString
        let argumentsString = function["arguments"] as? String ?? "{}"
        let (command, error) = parseCommand(arguments: argumentsString)
        return ParsedToolCall(id: id, command: command, rawArguments: argumentsString, parseError: error)
    }

    /// Tolerant decode of the tool arguments into an `ExecuteCommand`.
    static func parseCommand(arguments: String) -> (ExecuteCommand?, String?) {
        let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [trimmed, unwrapJSONString(trimmed)].compactMap { $0 }
        for candidate in candidates {
            if let data = candidate.data(using: .utf8),
               let command = try? JSONDecoder().decode(ExecuteCommand.self, from: data) {
                return (command, nil)
            }
        }
        return (nil, "Could not parse tool arguments.")
    }

    /// If the model double-encoded the args as a JSON string ("\"{...}\""), unwrap one level.
    private static func unwrapJSONString(_ value: String) -> String? {
        guard value.hasPrefix("\""), value.hasSuffix("\""),
              let data = value.data(using: .utf8),
              let unwrapped = try? JSONDecoder().decode(String.self, from: data) else { return nil }
        return unwrapped
    }

    // MARK: - Tool schema (mirrors docs/execute_command_schema.json)

    /// Built from a JSON string to avoid deeply-nested heterogeneous dictionary-literal inference.
    static var toolSchema: [String: Any] {
        let actions = CommandAction.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ",")
        let json = """
        {
          "type": "function",
          "function": {
            "name": "execute_command",
            "description": "Execute a command on the Flipper Zero device. All file operations, device queries, hardware control, and artifact pushes go through this interface.",
            "parameters": {
              "type": "object",
              "properties": {
                "action": { "type": "string", "enum": [\(actions)], "description": "The action to perform on the Flipper Zero" },
                "args": { "type": "object", "description": "Arguments for the action (varies by action type)" },
                "justification": { "type": "string", "description": "Why this action is being taken" },
                "expected_effect": { "type": "string", "description": "What this action should accomplish" }
              },
              "required": ["action", "args", "justification", "expected_effect"]
            }
          }
        }
        """
        return (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]) ?? [:]
    }
}

enum OpenRouterError: LocalizedError {
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let message): return "OpenRouter error \(code): \(message)"
        }
    }
}

/// Simple sliding-window rate limiter.
actor RateLimiter {
    private let maxRequests: Int
    private let windowSeconds: TimeInterval
    private var timestamps: [Date] = []

    init(maxRequests: Int, windowSeconds: TimeInterval) {
        self.maxRequests = maxRequests
        self.windowSeconds = windowSeconds
    }

    func acquire() async {
        while true {
            let now = Date()
            timestamps.removeAll { now.timeIntervalSince($0) > windowSeconds }
            if timestamps.count < maxRequests {
                timestamps.append(now)
                return
            }
            let oldest = timestamps.first ?? now
            let wait = windowSeconds - now.timeIntervalSince(oldest)
            try? await Task.sleep(for: .seconds(max(0.05, wait)))
        }
    }
}
