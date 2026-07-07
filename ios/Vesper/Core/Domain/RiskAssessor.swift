import Foundation

struct RiskAssessment: Sendable, Equatable {
    let level: RiskLevel
    let reason: String
    let requiresDiff: Bool
    let requiresHoldToConfirm: Bool

    static func of(_ level: RiskLevel, _ reason: String, diff: Bool = false) -> RiskAssessment {
        RiskAssessment(level: level,
                       reason: reason,
                       requiresDiff: diff,
                       requiresHoldToConfirm: level == .high)
    }
}

/// Classifies commands by risk. "Android decides, not the model." Bakes in the fixes for the
/// retired build's H2 (prefix-only CLI classification), mass-op escalation gap, and H4
/// (operation modes were never enforced).
struct RiskAssessor {

    func assess(_ command: ExecuteCommand,
                mode: OperationMode = .standard,
                unlocks: [ProtectedUnlock] = []) -> RiskAssessment {

        // 1) Operation-mode enforcement (real, not cosmetic).
        if mode.blockedActions.contains(command.action) {
            return .of(.blocked, "\(command.action.displayName) is blocked in \(mode.displayName) mode.")
        }

        // 2) Protected-path gate.
        for path in affectedPaths(command) {
            if ProtectedPaths.isProtected(path) && !unlocks.contains(where: { $0.covers(path) }) {
                return .of(.blocked, "\(path) is protected; unlock it in Settings first.")
            }
        }

        // 3) Per-action classification.
        switch command.action {
        case .executeCli:
            // Classify the FULL command, across chained separators.
            return classifyCli(command.args.command ?? "")

        case .listDirectory, .readFile, .getDeviceInfo, .getStorageInfo,
             .searchFaphub, .browseRepo, .githubSearch, .requestPhoto:
            return .of(.low, "Read-only operation.")

        case .writeFile:
            return .of(.medium, "Writing a file; review the diff.", diff: true)

        case .createDirectory, .copy, .irTransmit, .nfcEmulate, .rfidEmulate,
             .ibuttonEmulate, .launchApp, .forgePayload, .downloadResource,
             .ledControl, .vibroControl:
            return .of(.medium, "Reversible change or reversible signal action.")

        case .delete, .move, .rename:
            return .of(.high, "Destructive file operation.")

        case .subghzTransmit, .badusbExecute, .pushArtifact, .installFaphubApp:
            return .of(.high, "High-impact action (RF transmit / HID / executable install).")
        }
    }

    // MARK: - CLI classification

    private static let blockingTokens = ["format", "factory_reset"]
    private static let destructiveTokens = ["remove_recursive", "remove", "erase", "rm", "delete"]
    private static let readOnlyPrefixes = [
        "storage list", "storage stat", "storage info", "storage read", "storage md5",
        "device_info", "power_info", "info", "help", "ps", "free", "date", "uptime", "loader list"
    ]

    private func classifyCli(_ raw: String) -> RiskAssessment {
        let command = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if command.isEmpty { return .of(.low, "Empty command.") }

        let segments = splitSegments(command)
        var maxLevel: RiskLevel = .low
        var reason = "Read-only CLI command."

        for segment in segments {
            let (level, why) = classifySegment(segment)
            if level > maxLevel { maxLevel = level; reason = why }
        }

        // Chained commands are never auto-run: escalate a plain LOW to MEDIUM if multiple segments.
        if segments.count > 1 && maxLevel == .low {
            return .of(.medium, "Chained CLI command; review before running.")
        }
        return .of(maxLevel, reason)
    }

    private func classifySegment(_ segment: String) -> (RiskLevel, String) {
        let lower = segment.lowercased().trimmingCharacters(in: .whitespaces)
        if RiskAssessor.blockingTokens.contains(where: { containsWord(lower, $0) }) {
            return (.blocked, "Command would format/reset storage.")
        }
        if RiskAssessor.destructiveTokens.contains(where: { containsWord(lower, $0) }) {
            return (.high, "Command deletes data.")
        }
        if RiskAssessor.readOnlyPrefixes.contains(where: { lower.hasPrefix($0) }) {
            return (.low, "Read-only CLI command.")
        }
        return (.medium, "CLI command with side effects.")
    }

    /// Split on shell-style chaining/piping so a safe-looking prefix can't hide a destructive tail.
    private func splitSegments(_ command: String) -> [String] {
        var segments: [String] = []
        var current = ""
        let scalars = Array(command)
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            let next = i + 1 < scalars.count ? scalars[i + 1] : nil
            if c == ";" || c == "|" || c == "&" {
                if (c == "&" && next == "&") || (c == "|" && next == "|") { i += 1 }
                segments.append(current)
                current = ""
            } else {
                current.append(c)
            }
            i += 1
        }
        segments.append(current)
        return segments.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func containsWord(_ haystack: String, _ word: String) -> Bool {
        haystack.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
            .contains { $0 == Substring(word) }
    }

    private func affectedPaths(_ command: ExecuteCommand) -> [String] {
        [command.args.path, command.args.destinationPath, command.args.signalFile]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
    }
}
