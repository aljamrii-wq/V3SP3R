import Foundation
import Observation

/// App configuration. The API key lives in the Keychain; everything else in UserDefaults.
@MainActor
@Observable
final class SettingsStore {

    private let defaults: UserDefaults
    private static let apiKeyAccount = "openrouter_api_key"

    // Backing store for the Keychain-held key (mirrored so the UI can observe changes).
    private var cachedApiKey: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cachedApiKey = Keychain.get(account: Self.apiKeyAccount)
        selectedModel = defaults.string(forKey: Keys.selectedModel) ?? Self.defaultModel
        operationMode = OperationMode(rawValue: defaults.string(forKey: Keys.operationMode) ?? "") ?? .standard
        autoApproveMedium = defaults.bool(forKey: Keys.autoApproveMedium)
        autoApproveHigh = defaults.bool(forKey: Keys.autoApproveHigh)
        let iters = defaults.integer(forKey: Keys.aiMaxIterations)
        aiMaxIterations = iters == 0 ? 8 : iters
        glassesBridgeURL = defaults.string(forKey: Keys.glassesBridgeURL)
    }

    // MARK: - API key (Keychain-backed)

    var apiKey: String? {
        get { cachedApiKey }
        set {
            cachedApiKey = newValue
            if let value = newValue, !value.isEmpty {
                Keychain.set(value, account: Self.apiKeyAccount)
            } else {
                Keychain.delete(account: Self.apiKeyAccount)
            }
        }
    }

    var hasApiKey: Bool { !(cachedApiKey ?? "").isEmpty }

    // MARK: - Preferences (UserDefaults-backed)

    var selectedModel: String { didSet { defaults.set(selectedModel, forKey: Keys.selectedModel) } }
    var operationMode: OperationMode { didSet { defaults.set(operationMode.rawValue, forKey: Keys.operationMode) } }
    var autoApproveMedium: Bool { didSet { defaults.set(autoApproveMedium, forKey: Keys.autoApproveMedium) } }
    var autoApproveHigh: Bool { didSet { defaults.set(autoApproveHigh, forKey: Keys.autoApproveHigh) } }
    var aiMaxIterations: Int { didSet { defaults.set(aiMaxIterations, forKey: Keys.aiMaxIterations) } }
    var glassesBridgeURL: String? { didSet { defaults.set(glassesBridgeURL, forKey: Keys.glassesBridgeURL) } }

    // MARK: - Constants

    static let defaultModel = "anthropic/claude-sonnet-4"

    static let recommendedModels: [String] = [
        "anthropic/claude-sonnet-4",
        "anthropic/claude-opus-4.6",
        "anthropic/claude-haiku-4",
        "nousresearch/hermes-4",
        "openai/gpt-4o"
    ]

    private enum Keys {
        static let selectedModel = "selected_model"
        static let operationMode = "operation_mode"
        static let autoApproveMedium = "auto_approve_medium"
        static let autoApproveHigh = "auto_approve_high"
        static let aiMaxIterations = "ai_max_iterations"
        static let glassesBridgeURL = "glasses_bridge_url"
    }
}
