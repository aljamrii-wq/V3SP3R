import Foundation

/// Snapshot of a connected Flipper's status, parsed from CLI `info` / `storage info` output.
struct FlipperDeviceInfo: Sendable, Equatable {
    var name: String
    var firmwareVersion: String
    var hardwareModel: String
    var batteryPercent: Int?
    var storageUsedBytes: Int64?
    var storageTotalBytes: Int64?
    var raw: [String: String]

    init(name: String = "Flipper",
         firmwareVersion: String = "unknown",
         hardwareModel: String = "unknown",
         batteryPercent: Int? = nil,
         storageUsedBytes: Int64? = nil,
         storageTotalBytes: Int64? = nil,
         raw: [String: String] = [:]) {
        self.name = name
        self.firmwareVersion = firmwareVersion
        self.hardwareModel = hardwareModel
        self.batteryPercent = batteryPercent
        self.storageUsedBytes = storageUsedBytes
        self.storageTotalBytes = storageTotalBytes
        self.raw = raw
    }

    var storageFreeBytes: Int64? {
        guard let used = storageUsedBytes, let total = storageTotalBytes else { return nil }
        return max(0, total - used)
    }
}

/// A single entry from `storage list`.
struct FlipperFileEntry: Identifiable, Sendable, Equatable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let isDirectory: Bool
    let sizeBytes: Int64?
}
