import Foundation

/// Executes commands under risk enforcement. The model proposes; this layer decides.
@MainActor
final class CommandExecutor {

    private let fs: FlipperFileSystem
    private let ble: FlipperBLEManager
    private let risk: RiskAssessor
    private let permissions: PermissionService
    private let audit: AuditService
    private let diffService: DiffService
    private let settings: SettingsStore

    /// Provided by the agent: surfaces a pending approval to the UI and resolves to the decision.
    var approvalHandler: (@MainActor (PendingApproval) async -> Bool)?

    init(fs: FlipperFileSystem,
         ble: FlipperBLEManager,
         risk: RiskAssessor = RiskAssessor(),
         permissions: PermissionService,
         audit: AuditService,
         diffService: DiffService = DiffService(),
         settings: SettingsStore) {
        self.fs = fs
        self.ble = ble
        self.risk = risk
        self.permissions = permissions
        self.audit = audit
        self.diffService = diffService
        self.settings = settings
    }

    func execute(_ command: ExecuteCommand, sessionId: String) async -> CommandResult {
        audit.log(.commandReceived, session: sessionId, summary: describe(command))

        let assessment = risk.assess(command,
                                     mode: settings.operationMode,
                                     unlocks: permissions.activeUnlocks())

        if assessment.level == .blocked {
            audit.log(.commandBlocked, session: sessionId, summary: assessment.reason,
                      risk: .blocked, success: false)
            return .failure("Blocked: \(assessment.reason)", risk: .blocked, blocked: true)
        }

        if requiresApproval(action: command.action, level: assessment.level) {
            let diff = assessment.requiresDiff ? await computeDiff(command) : nil
            let pending = PendingApproval(command: command,
                                          riskLevel: assessment.level,
                                          reason: assessment.reason,
                                          diff: diff,
                                          requiresHoldToConfirm: assessment.requiresHoldToConfirm)
            audit.log(.approvalRequested, session: sessionId, summary: assessment.reason,
                      risk: assessment.level)
            let approved = await (approvalHandler?(pending) ?? false)
            guard approved else {
                audit.log(.approvalRejected, session: sessionId, summary: describe(command),
                          risk: assessment.level, success: false)
                return .failure("User rejected the action.", risk: assessment.level)
            }
            audit.log(.approvalGranted, session: sessionId, summary: describe(command),
                      risk: assessment.level, success: true)
        }

        do {
            let output = try await executeAction(command)
            audit.log(.commandExecuted, session: sessionId, summary: describe(command),
                      risk: assessment.level, success: true)
            return .ok(output, risk: assessment.level)
        } catch {
            audit.log(.commandFailed, session: sessionId, summary: error.localizedDescription,
                      risk: assessment.level, success: false)
            return .failure(error.localizedDescription, risk: assessment.level)
        }
    }

    func requiresApproval(action: CommandAction, level: RiskLevel) -> Bool {
        Self.requiresApproval(action: action,
                              level: level,
                              autoApproveMedium: settings.autoApproveMedium,
                              autoApproveHigh: settings.autoApproveHigh)
    }

    /// Pure approval decision (no side effects, no dependencies) — exercised directly by tests.
    /// Irreversible actions are never auto-approved, even when `autoApproveHigh` is on.
    static func requiresApproval(action: CommandAction,
                                 level: RiskLevel,
                                 autoApproveMedium: Bool,
                                 autoApproveHigh: Bool) -> Bool {
        switch level {
        case .low: return false
        case .medium: return !autoApproveMedium
        case .high:
            if action.isIrreversible { return true }
            return !autoApproveHigh
        case .blocked: return true
        }
    }

    // MARK: - Execution

    private func executeAction(_ command: ExecuteCommand) async throws -> String {
        guard ble.connectionState.isConnected else { throw FlipperFileSystemError.notConnected }
        let args = command.args

        switch command.action {
        case .listDirectory:
            let entries = try await fs.listDirectory(args.path ?? "/ext")
            if entries.isEmpty { return "(empty)" }
            return entries.map { ($0.isDirectory ? "📁 " : "📄 ") + $0.name
                + ($0.sizeBytes.map { " (\($0) B)" } ?? "") }.joined(separator: "\n")

        case .readFile:
            return try await fs.readFile(args.path ?? "")

        case .writeFile:
            return try await fs.writeFile(args.path ?? "", content: args.content ?? "")

        case .createDirectory:
            return try await fs.makeDirectory(args.path ?? "")

        case .delete:
            return try await fs.remove(args.path ?? "", recursive: args.recursive ?? false)

        case .move, .rename:
            let dest = args.destinationPath ?? destinationFromNewName(args)
            return try await fs.rename(args.path ?? "", to: dest)

        case .copy:
            return try await fs.copy(args.path ?? "", to: args.destinationPath ?? "")

        case .getDeviceInfo:
            let info = try await fs.deviceInfo()
            return formatDeviceInfo(info)

        case .getStorageInfo:
            return try await fs.executeCli("storage info /ext")

        case .executeCli:
            return try await fs.executeCli(args.command ?? "")

        case .ledControl:
            return try await runLed(color: args.color, on: args.state ?? true)

        case .vibroControl:
            return try await fs.executeCli("vibro \((args.state ?? true) ? 1 : 0)")

        case .launchApp:
            let name = args.appName ?? ""
            try FlipperFileSystem.rejectControlCharacters(name)
            return try await fs.executeCli("loader open \(name)")

        case .subghzTransmit, .irTransmit, .nfcEmulate, .rfidEmulate, .ibuttonEmulate,
             .badusbExecute, .pushArtifact, .forgePayload, .installFaphubApp,
             .searchFaphub, .browseRepo, .downloadResource, .githubSearch, .requestPhoto:
            return "\(command.action.displayName) is on the iOS roadmap and is not wired to hardware in this build yet."
        }
    }

    private func runLed(color: String?, on: Bool) async throws -> String {
        let channel: String
        switch (color ?? "green").lowercased() {
        case "red": channel = "r"
        case "green": channel = "g"
        case "blue": channel = "b"
        case "backlight", "bl": channel = "bl"
        default: channel = "g"
        }
        return try await fs.executeCli("led \(channel) \(on ? 255 : 0)")
    }

    private func destinationFromNewName(_ args: CommandArgs) -> String {
        guard let path = args.path, let newName = args.newName else { return args.destinationPath ?? "" }
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? newName : parent + "/" + newName
    }

    private func computeDiff(_ command: ExecuteCommand) async -> String? {
        guard command.action == .writeFile, let path = command.args.path else { return nil }
        let newContent = command.args.content ?? ""
        let oldContent = (try? await fs.readFile(path)) ?? ""
        let diff = diffService.unifiedDiff(old: oldContent, new: newContent)
        return diff.isEmpty ? nil : diff
    }

    // MARK: - Formatting

    private func describe(_ command: ExecuteCommand) -> String {
        var parts = [command.action.rawValue]
        if let path = command.args.path { parts.append(path) }
        if let cmd = command.args.command { parts.append(cmd) }
        return parts.joined(separator: " ")
    }

    private func formatDeviceInfo(_ info: FlipperDeviceInfo) -> String {
        var lines = ["Name: \(info.name)",
                     "Firmware: \(info.firmwareVersion)",
                     "Hardware: \(info.hardwareModel)"]
        if let battery = info.batteryPercent { lines.append("Battery: \(battery)%") }
        if let total = info.storageTotalBytes {
            let free = info.storageFreeBytes ?? 0
            lines.append("Storage: \(byteString(total - free)) used / \(byteString(total))")
        }
        return lines.joined(separator: "\n")
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
