import Foundation

/// The single tool surface exposed to the model — mirrors docs/execute_command_schema.json.
enum CommandAction: String, Codable, CaseIterable, Sendable {
    case listDirectory = "list_directory"
    case readFile = "read_file"
    case writeFile = "write_file"
    case createDirectory = "create_directory"
    case delete
    case move
    case rename
    case copy
    case getDeviceInfo = "get_device_info"
    case getStorageInfo = "get_storage_info"
    case executeCli = "execute_cli"
    case pushArtifact = "push_artifact"
    case forgePayload = "forge_payload"
    case subghzTransmit = "subghz_transmit"
    case irTransmit = "ir_transmit"
    case nfcEmulate = "nfc_emulate"
    case rfidEmulate = "rfid_emulate"
    case ibuttonEmulate = "ibutton_emulate"
    case badusbExecute = "badusb_execute"
    case launchApp = "launch_app"
    case ledControl = "led_control"
    case vibroControl = "vibro_control"
    case searchFaphub = "search_faphub"
    case installFaphubApp = "install_faphub_app"
    case browseRepo = "browse_repo"
    case downloadResource = "download_resource"
    case githubSearch = "github_search"
    case requestPhoto = "request_photo"

    /// Irreversible / destructive actions. These ALWAYS require explicit confirmation even
    /// when "auto-approve high" is enabled — closing the retired Android build's H3 hole.
    var isIrreversible: Bool {
        switch self {
        case .delete, .badusbExecute, .subghzTransmit, .pushArtifact, .installFaphubApp:
            return true
        default:
            return false
        }
    }

    /// A human-facing verb for audit/UI.
    var displayName: String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

/// Loosely-typed argument bag for a command. Only the fields relevant to the action are set.
struct CommandArgs: Codable, Sendable, Equatable {
    var path: String?
    var destinationPath: String?
    var content: String?
    var newName: String?
    var recursive: Bool?
    var artifactType: String?
    var artifactData: String?
    var command: String?
    var payloadType: String?
    var payloadSpec: String?
    var frequency: Double?
    var protocolName: String?
    var signalFile: String?
    var script: String?
    var appName: String?
    var appArgs: String?
    var color: String?
    var state: Bool?
    var query: String?
    var appId: String?
    var repoUrl: String?
    var resourceUrl: String?

    enum CodingKeys: String, CodingKey {
        case path
        case destinationPath = "destination_path"
        case content
        case newName = "new_name"
        case recursive
        case artifactType = "artifact_type"
        case artifactData = "artifact_data"
        case command
        case payloadType = "payload_type"
        case payloadSpec = "payload_spec"
        case frequency
        case protocolName = "protocol"
        case signalFile = "signal_file"
        case script
        case appName = "app_name"
        case appArgs = "app_args"
        case color
        case state
        case query
        case appId = "app_id"
        case repoUrl = "repo_url"
        case resourceUrl = "resource_url"
    }

    init() {}

    /// Tolerant decoding: some models send `recursive`/`state`/`frequency` as strings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decodeIfPresent(String.self, forKey: .path)
        destinationPath = try c.decodeIfPresent(String.self, forKey: .destinationPath)
        content = try c.decodeIfPresent(String.self, forKey: .content)
        newName = try c.decodeIfPresent(String.self, forKey: .newName)
        recursive = Self.decodeLooseBool(c, .recursive)
        artifactType = try c.decodeIfPresent(String.self, forKey: .artifactType)
        artifactData = try c.decodeIfPresent(String.self, forKey: .artifactData)
        command = try c.decodeIfPresent(String.self, forKey: .command)
        payloadType = try c.decodeIfPresent(String.self, forKey: .payloadType)
        payloadSpec = try c.decodeIfPresent(String.self, forKey: .payloadSpec)
        frequency = Self.decodeLooseDouble(c, .frequency)
        protocolName = try c.decodeIfPresent(String.self, forKey: .protocolName)
        signalFile = try c.decodeIfPresent(String.self, forKey: .signalFile)
        script = try c.decodeIfPresent(String.self, forKey: .script)
        appName = try c.decodeIfPresent(String.self, forKey: .appName)
        appArgs = try c.decodeIfPresent(String.self, forKey: .appArgs)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        state = Self.decodeLooseBool(c, .state)
        query = try c.decodeIfPresent(String.self, forKey: .query)
        appId = try c.decodeIfPresent(String.self, forKey: .appId)
        repoUrl = try c.decodeIfPresent(String.self, forKey: .repoUrl)
        resourceUrl = try c.decodeIfPresent(String.self, forKey: .resourceUrl)
    }

    private static func decodeLooseBool(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Bool? {
        if let b = try? c.decodeIfPresent(Bool.self, forKey: key) { return b }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) {
            switch s.lowercased() { case "true", "yes", "1": return true
                                    case "false", "no", "0": return false
                                    default: return nil }
        }
        return nil
    }

    private static func decodeLooseDouble(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }
}

/// A structured command the agent asks Android to execute.
struct ExecuteCommand: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let action: CommandAction
    var args: CommandArgs
    var justification: String
    var expectedEffect: String

    init(id: UUID = UUID(),
         action: CommandAction,
         args: CommandArgs = CommandArgs(),
         justification: String = "",
         expectedEffect: String = "") {
        self.id = id
        self.action = action
        self.args = args
        self.justification = justification
        self.expectedEffect = expectedEffect
    }

    enum CodingKeys: String, CodingKey {
        case action, args, justification
        case expectedEffect = "expected_effect"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        action = try c.decode(CommandAction.self, forKey: .action)
        args = try c.decodeIfPresent(CommandArgs.self, forKey: .args) ?? CommandArgs()
        justification = try c.decodeIfPresent(String.self, forKey: .justification) ?? ""
        expectedEffect = try c.decodeIfPresent(String.self, forKey: .expectedEffect) ?? ""
    }
}

/// Outcome of executing a command.
struct CommandResult: Sendable, Equatable {
    var success: Bool
    var output: String
    var riskLevel: RiskLevel
    var wasBlocked: Bool

    init(success: Bool, output: String, riskLevel: RiskLevel = .low, wasBlocked: Bool = false) {
        self.success = success
        self.output = output
        self.riskLevel = riskLevel
        self.wasBlocked = wasBlocked
    }

    static func ok(_ output: String, risk: RiskLevel = .low) -> CommandResult {
        CommandResult(success: true, output: output, riskLevel: risk)
    }

    static func failure(_ output: String, risk: RiskLevel = .low, blocked: Bool = false) -> CommandResult {
        CommandResult(success: false, output: output, riskLevel: risk, wasBlocked: blocked)
    }
}
