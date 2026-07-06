import SwiftUI

struct DeviceView: View {
    @Environment(FlipperBLEManager.self) private var ble
    @Environment(AppContainer.self) private var container

    @State private var info: FlipperDeviceInfo?
    @State private var loadingInfo = false
    @State private var infoError: String?

    var body: some View {
        NavigationStack {
            List {
                statusSection
                if ble.connectionState.isConnected {
                    deviceInfoSection
                } else {
                    scanSection
                }
            }
            .navigationTitle("Device")
            .task(id: ble.connectionState.isConnected) {
                if ble.connectionState.isConnected { await loadInfo() }
                else { info = nil }
            }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section("Status") {
            HStack(spacing: 12) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.title3)
                VStack(alignment: .leading) {
                    Text(statusTitle).font(.headline)
                    if let subtitle = statusSubtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if ble.connectionState.isConnected {
                    Button("Disconnect", role: .destructive) { ble.disconnect() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Scan

    private var scanSection: some View {
        Section {
            Button {
                if ble.connectionState == .scanning { ble.stopScan() } else { ble.startScan() }
            } label: {
                Label(ble.connectionState == .scanning ? "Stop scanning" : "Scan for Flippers",
                      systemImage: "antenna.radiowaves.left.and.right")
            }

            ForEach(ble.discovered) { flipper in
                Button {
                    ble.connect(flipper.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(flipper.name)
                            Text("Signal \(flipper.rssi) dBm")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
            }
        } header: {
            Text("Nearby")
        } footer: {
            if let error = ble.lastError { Text(error).foregroundStyle(.red) }
        }
    }

    // MARK: - Device info

    private var deviceInfoSection: some View {
        Section {
            if loadingInfo {
                HStack { ProgressView(); Text("Reading device info…") }
            } else if let info {
                infoRow("Name", info.name)
                infoRow("Firmware", info.firmwareVersion)
                infoRow("Hardware", info.hardwareModel)
                if let battery = info.batteryPercent { infoRow("Battery", "\(battery)%") }
                if let total = info.storageTotalBytes {
                    let used = total - (info.storageFreeBytes ?? 0)
                    infoRow("Storage", "\(byteString(used)) / \(byteString(total))")
                }
            } else if let infoError {
                Text(infoError).foregroundStyle(.red)
            }
            Button {
                Task { await loadInfo() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        } header: {
            Text("Flipper")
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospaced()
        }
    }

    // MARK: - Helpers

    private func loadInfo() async {
        loadingInfo = true
        infoError = nil
        defer { loadingInfo = false }
        do {
            info = try await container.fs.deviceInfo()
        } catch {
            infoError = error.localizedDescription
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var statusIcon: String {
        switch ble.connectionState {
        case .connected: return "checkmark.circle.fill"
        case .poweredOff: return "bolt.slash.fill"
        case .unauthorized: return "lock.fill"
        case .scanning, .connecting, .discovering: return "arrow.triangle.2.circlepath"
        default: return "dot.radiowaves.left.and.right"
        }
    }

    private var statusColor: Color {
        switch ble.connectionState {
        case .connected: return .green
        case .poweredOff, .unauthorized: return .red
        default: return .secondary
        }
    }

    private var statusTitle: String {
        switch ble.connectionState {
        case .connected: return "Connected"
        case .poweredOff: return "Bluetooth is off"
        case .unauthorized: return "Bluetooth permission needed"
        case .scanning: return "Scanning…"
        case .connecting: return "Connecting…"
        case .discovering: return "Discovering services…"
        case .disconnected: return "Disconnected"
        case .idle: return "Not connected"
        }
    }

    private var statusSubtitle: String? {
        switch ble.connectionState {
        case .connected: return ble.connectedName
        case .disconnected(let reason): return reason
        case .unauthorized: return "Enable Bluetooth for Vesper in Settings."
        default: return nil
        }
    }
}
