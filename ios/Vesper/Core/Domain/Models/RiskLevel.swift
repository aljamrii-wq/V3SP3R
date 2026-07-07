import Foundation

/// Risk classification for an agent action. Android enforces reality; the model's own
/// opinion of risk is discarded and re-derived here.
enum RiskLevel: String, Codable, CaseIterable, Sendable, Comparable {
    case low
    case medium
    case high
    case blocked

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .blocked: return "Blocked"
        }
    }

    private var order: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .blocked: return 3
        }
    }

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool { lhs.order < rhs.order }
}

/// Operator posture. Unlike the retired Android build (where these were cosmetic),
/// the assessor actually consults the active mode's blocked actions.
enum OperationMode: String, Codable, CaseIterable, Sendable {
    case standard
    case recon
    case stealth

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .recon: return "Recon"
        case .stealth: return "Stealth"
        }
    }

    /// Actions this mode forbids outright (escalated to `.blocked`).
    var blockedActions: Set<CommandAction> {
        switch self {
        case .standard:
            return []
        case .recon:
            // Recon = observe only. No transmitting / emulation / HID.
            return [.subghzTransmit, .irTransmit, .nfcEmulate, .rfidEmulate,
                    .ibuttonEmulate, .badusbExecute, .pushArtifact]
        case .stealth:
            // Stealth = no RF emissions or installs at all.
            return [.subghzTransmit, .irTransmit, .nfcEmulate, .rfidEmulate,
                    .ibuttonEmulate, .badusbExecute, .pushArtifact,
                    .installFaphubApp, .ledControl, .vibroControl, .launchApp]
        }
    }
}
