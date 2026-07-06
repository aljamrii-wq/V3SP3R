import Foundation

/// CLI command/response layer over the BLE serial link.
///
/// The Flipper exposes a text REPL: you write `command\r\n`, it echoes the line, prints output,
/// then re-prints its prompt (`>: `). This actor serializes commands (one in flight at a time),
/// accumulates inbound bytes from the transport's single `AsyncStream`, and returns the text
/// between the echo and the next prompt. Full protobuf RPC is a roadmap item; CLI covers the
/// storage + device-info surface the foundation needs.
actor FlipperProtocol {

    private let transport: FlipperBLEManager
    private var buffer = Data()
    private var consumerTask: Task<Void, Never>?

    // FIFO command lock (actor reentrancy would otherwise interleave awaited commands).
    private var commandInFlight = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private static let prompt = ">: "

    init(transport: FlipperBLEManager) {
        self.transport = transport
    }

    /// Begin consuming inbound bytes. Idempotent.
    func start() {
        guard consumerTask == nil else { return }
        let stream = transport.inboundBytes
        consumerTask = Task { [weak self] in
            for await chunk in stream {
                await self?.ingest(chunk)
            }
        }
    }

    private func ingest(_ chunk: Data) {
        buffer.append(chunk)
        // Cap the buffer so a chatty device can't grow it without bound.
        if buffer.count > 512 * 1024 {
            buffer.removeFirst(buffer.count - 512 * 1024)
        }
    }

    /// Run one CLI command and return its trimmed textual output.
    func sendCommand(_ command: String, timeout: TimeInterval = 8) async throws -> String {
        await acquire()
        defer { release() }

        buffer.removeAll(keepingCapacity: true)
        let line = command + "\r\n"
        try await transport.send(Data(line.utf8))

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        while true {
            if let response = extractResponse(echo: command) {
                return response
            }
            if clock.now >= deadline { throw FlipperError.timeout }
            try await Task.sleep(for: .milliseconds(40))
        }
    }

    /// Run a command that streams input (e.g. `storage write <path>`), terminated by Ctrl-C.
    func sendCommandWithInput(_ command: String, input: Data, timeout: TimeInterval = 15) async throws -> String {
        await acquire()
        defer { release() }

        buffer.removeAll(keepingCapacity: true)
        try await transport.send(Data((command + "\r\n").utf8))
        try await Task.sleep(for: .milliseconds(150)) // let the device enter input mode
        try await transport.send(input)
        try await transport.send(Data([0x03])) // Ctrl-C ends input and saves

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        while true {
            if let response = extractResponse(echo: command) { return response }
            if clock.now >= deadline { throw FlipperError.timeout }
            try await Task.sleep(for: .milliseconds(40))
        }
    }

    // MARK: - Response extraction

    private func extractResponse(echo: String) -> String? {
        guard !buffer.isEmpty else { return nil }
        let decoded = String(decoding: buffer, as: UTF8.self)
        let cleaned = Self.stripAnsi(decoded)
        // Only accept once the trailing prompt is present.
        guard let promptRange = cleaned.range(of: Self.prompt, options: .backwards) else {
            return nil
        }
        var body = String(cleaned[cleaned.startIndex..<promptRange.lowerBound])
        body = Self.removeEchoedCommand(from: body, echo: echo)
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeEchoedCommand(from body: String, echo: String) -> String {
        let trimmedEcho = echo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEcho.isEmpty else { return body }
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        if let first = lines.first,
           first.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedEcho {
            return lines.dropFirst().joined(separator: "\n")
        }
        return body
    }

    /// Strip ANSI/VT100 escape sequences the Flipper CLI may emit, and normalize CRLF to LF.
    static func stripAnsi(_ input: String) -> String {
        let scalars = Array(input.unicodeScalars)
        var result = String.UnicodeScalarView()
        result.reserveCapacity(scalars.count)
        var i = 0
        while i < scalars.count {
            let scalar = scalars[i]
            if scalar == "\u{1B}" { // ESC — skip a CSI sequence up to its letter terminator.
                i += 1
                if i < scalars.count, scalars[i] == "[" { i += 1 }
                while i < scalars.count {
                    let s = scalars[i]
                    i += 1
                    if (s >= "A" && s <= "Z") || (s >= "a" && s <= "z") { break }
                }
                continue
            }
            if scalar == "\r" { i += 1; continue } // normalize CRLF -> LF
            result.append(scalar)
            i += 1
        }
        return String(result)
    }

    // MARK: - Command lock

    private func acquire() async {
        if !commandInFlight {
            commandInFlight = true
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Void>) in
            waiters.append(cont)
        }
    }

    private func release() {
        if waiters.isEmpty {
            commandInFlight = false
        } else {
            let next = waiters.removeFirst()
            next.resume()
        }
    }
}
