import Foundation

enum FlipperFileSystemError: LocalizedError, Equatable {
    case invalidPath(String)
    case controlCharacters
    case notConnected

    var errorDescription: String? {
        switch self {
        case .invalidPath(let p): return "Path must be under /ext or /int: \(p)"
        case .controlCharacters: return "Path or argument contains illegal control characters."
        case .notConnected: return "Flipper is not connected."
        }
    }
}

/// High-level, path-validated file operations over the Flipper CLI.
///
/// Path validation rejects anything outside `/ext`/`/int` and any control character (newline,
/// carriage return, NUL) — since the CLI is line-oriented, that rejection is what makes command
/// construction injection-safe (the retired Android build interpolated unvalidated strings, its
/// H1 defect).
struct FlipperFileSystem {

    let proto: FlipperProtocol

    // MARK: - Validation

    static func validate(path: String) throws {
        try rejectControlCharacters(path)
        // Reject explicit traversal segments outright (defense in depth on top of normalization).
        let segments = path.split(separator: "/", omittingEmptySubsequences: true)
        if segments.contains("..") { throw FlipperFileSystemError.invalidPath(path) }
        let normalized = PathUtils.normalize(path)
        guard normalized == "/ext" || normalized.hasPrefix("/ext/")
                || normalized == "/int" || normalized.hasPrefix("/int/") else {
            throw FlipperFileSystemError.invalidPath(path)
        }
    }

    static func rejectControlCharacters(_ value: String) throws {
        for scalar in value.unicodeScalars where scalar.value < 0x20 {
            throw FlipperFileSystemError.controlCharacters
        }
    }

    // MARK: - Operations

    func listDirectory(_ path: String) async throws -> [FlipperFileEntry] {
        try Self.validate(path: path)
        let out = try await proto.sendCommand("storage list \(path)")
        return Self.parseList(out, base: path)
    }

    func readFile(_ path: String, maxBytes: Int = 64 * 1024) async throws -> String {
        try Self.validate(path: path)
        let out = try await proto.sendCommand("storage read \(path)")
        let body = Self.stripReadHeader(out)
        if body.utf8.count > maxBytes {
            return String(body.prefix(maxBytes)) + "\n… [truncated]"
        }
        return body
    }

    @discardableResult
    func writeFile(_ path: String, content: String) async throws -> String {
        try Self.validate(path: path)
        return try await proto.sendCommandWithInput("storage write \(path)", input: Data(content.utf8))
    }

    @discardableResult
    func makeDirectory(_ path: String) async throws -> String {
        try Self.validate(path: path)
        return try await proto.sendCommand("storage mkdir \(path)")
    }

    @discardableResult
    func remove(_ path: String, recursive: Bool) async throws -> String {
        try Self.validate(path: path)
        let verb = recursive ? "remove_recursive" : "remove"
        return try await proto.sendCommand("storage \(verb) \(path)")
    }

    @discardableResult
    func copy(_ source: String, to destination: String) async throws -> String {
        try Self.validate(path: source)
        try Self.validate(path: destination)
        return try await proto.sendCommand("storage copy \(source) \(destination)")
    }

    @discardableResult
    func rename(_ source: String, to destination: String) async throws -> String {
        try Self.validate(path: source)
        try Self.validate(path: destination)
        return try await proto.sendCommand("storage rename \(source) \(destination)")
    }

    func stat(_ path: String) async throws -> String {
        try Self.validate(path: path)
        return try await proto.sendCommand("storage stat \(path)")
    }

    /// Raw CLI passthrough. Rejects embedded control characters so a single call can carry only
    /// one command line (no newline-smuggled second command past risk classification).
    func executeCli(_ command: String) async throws -> String {
        try Self.rejectControlCharacters(command)
        return try await proto.sendCommand(command)
    }

    func deviceInfo() async throws -> FlipperDeviceInfo {
        let devOut = (try? await proto.sendCommand("device_info")) ?? ""
        let powerOut = (try? await proto.sendCommand("power_info")) ?? ""
        let storageOut = (try? await proto.sendCommand("storage info /ext")) ?? ""

        var kv = Self.parseKeyValues(devOut)
        for (k, v) in Self.parseKeyValues(powerOut) where kv[k] == nil { kv[k] = v }

        let name = kv["hardware_name"] ?? kv["hardware_model"] ?? "Flipper"
        let firmware = kv["firmware_version"] ?? kv["firmware_commit"] ?? "unknown"
        let model = kv["hardware_model"] ?? kv["hardware_ver"] ?? "unknown"
        let battery = Int(kv["charge_level"] ?? "")
        let (used, total) = Self.parseStorageInfo(storageOut)

        return FlipperDeviceInfo(name: name,
                                 firmwareVersion: firmware,
                                 hardwareModel: model,
                                 batteryPercent: battery,
                                 storageUsedBytes: used,
                                 storageTotalBytes: total,
                                 raw: kv)
    }

    // MARK: - Parsing

    static func parseList(_ output: String, base: String) -> [FlipperFileEntry] {
        var entries: [FlipperFileEntry] = []
        let prefix = base.hasSuffix("/") ? base : base + "/"
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[D]") {
                let name = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                entries.append(FlipperFileEntry(name: name, path: prefix + name,
                                                isDirectory: true, sizeBytes: nil))
            } else if line.hasPrefix("[F]") {
                let rest = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                let (name, size) = splitNameAndSize(String(rest))
                guard !name.isEmpty else { continue }
                entries.append(FlipperFileEntry(name: name, path: prefix + name,
                                                isDirectory: false, sizeBytes: size))
            }
        }
        return entries
    }

    private static func splitNameAndSize(_ rest: String) -> (String, Int64?) {
        let tokens = rest.split(separator: " ")
        if let last = tokens.last, let size = Int64(last), tokens.count > 1 {
            let name = tokens.dropLast().joined(separator: " ")
            return (name, size)
        }
        return (rest, nil)
    }

    static func stripReadHeader(_ output: String) -> String {
        // `storage read` prints a "Size: N" header line before the content.
        var lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let first = lines.first, first.lowercased().hasPrefix("size:") {
            lines.removeFirst()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parseKeyValues(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in output.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { result[key] = value }
        }
        return result
    }

    /// Best-effort parse of `storage info /ext` (formats vary by firmware).
    static func parseStorageInfo(_ output: String) -> (used: Int64?, total: Int64?) {
        var total: Int64?
        var free: Int64?
        for line in output.split(separator: "\n") {
            let lower = line.lowercased()
            if lower.contains("total"), let bytes = firstByteQuantity(String(line)) { total = bytes }
            if lower.contains("free"), let bytes = firstByteQuantity(String(line)) { free = bytes }
        }
        if let total, let free { return (max(0, total - free), total) }
        return (nil, total)
    }

    private static func firstByteQuantity(_ line: String) -> Int64? {
        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        for (i, token) in tokens.enumerated() {
            if let value = Double(token) {
                let unit = i + 1 < tokens.count ? tokens[i + 1].lowercased() : ""
                let multiplier: Double
                if unit.hasPrefix("kb") || unit.hasPrefix("kib") { multiplier = 1024 }
                else if unit.hasPrefix("mb") || unit.hasPrefix("mib") { multiplier = 1024 * 1024 }
                else if unit.hasPrefix("gb") || unit.hasPrefix("gib") { multiplier = 1024 * 1024 * 1024 }
                else { multiplier = 1 }
                return Int64(value * multiplier)
            }
        }
        return nil
    }
}
