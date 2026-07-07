import Foundation
import CoreBluetooth
import Observation

enum FlipperConnectionState: Equatable, Sendable {
    case poweredOff
    case unauthorized
    case idle
    case scanning
    case connecting
    case discovering
    case connected
    case disconnected(String?)

    var isConnected: Bool { self == .connected }
}

struct DiscoveredFlipper: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    var rssi: Int
}

enum FlipperError: LocalizedError {
    case notConnected
    case writeInFlight
    case timeout
    case serialServiceNotFound

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Flipper is not connected."
        case .writeInFlight: return "A BLE write is already in progress."
        case .timeout: return "The Flipper did not respond in time."
        case .serialServiceNotFound: return "Could not find the Flipper serial service."
        }
    }
}

/// Core Bluetooth transport for the Flipper Zero.
///
/// Concurrency model: Core Bluetooth is created with `queue: nil`, so all delegate callbacks
/// arrive on the main thread; the class is `@MainActor`-isolated to match, and the delegate
/// methods are `nonisolated` shims that hop back in via `MainActor.assumeIsolated`. Inbound
/// notification bytes are published through a single `AsyncStream`, giving exactly one reader
/// downstream — the structural fix for the retired Android build's `responseBuffer` data race.
@MainActor
@Observable
final class FlipperBLEManager: NSObject {

    // Observable UI state.
    private(set) var connectionState: FlipperConnectionState = .idle
    private(set) var discovered: [DiscoveredFlipper] = []
    private(set) var connectedName: String?
    private(set) var lastError: String?

    // Known Flipper serial service (used as a scan hint; discovery is property-based below).
    private static let serialServiceHint = CBUUID(string: "8fe5b3d5-2e7f-4a98-2a48-7acc60fe0000")
    private static let namePrefix = "Flipper"

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    // (all Core Bluetooth handles below are @ObservationIgnored — not observable UI state)
    @ObservationIgnored private var txCharacteristic: CBCharacteristic?
    @ObservationIgnored private var rxCharacteristic: CBCharacteristic?
    @ObservationIgnored private var writeContinuation: CheckedContinuation<Void, Error>?
    @ObservationIgnored private var inboundContinuation: AsyncStream<Data>.Continuation?
    @ObservationIgnored private var pendingConnectId: UUID?

    /// Single inbound byte stream consumed by `FlipperProtocol`. `nonisolated` so the protocol
    /// actor can read it without hopping onto the main actor.
    nonisolated let inboundBytes: AsyncStream<Data>

    override init() {
        var continuation: AsyncStream<Data>.Continuation!
        inboundBytes = AsyncStream { continuation = $0 }
        super.init()
        inboundContinuation = continuation
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public API

    func startScan() {
        lastError = nil
        guard central.state == .poweredOn else {
            connectionState = mapCentralState()
            return
        }
        discovered.removeAll()
        connectionState = .scanning
        central.scanForPeripherals(withServices: nil, options: nil)
    }

    func stopScan() {
        if central.state == .poweredOn { central.stopScan() }
        if connectionState == .scanning { connectionState = .idle }
    }

    func connect(_ id: UUID) {
        guard let match = central.retrievePeripherals(withIdentifiers: [id]).first
                ?? discoveredPeripheral(for: id) else {
            lastError = "That Flipper is no longer in range."
            return
        }
        central.stopScan()
        pendingConnectId = id
        peripheral = match
        match.delegate = self
        connectionState = .connecting
        central.connect(match, options: nil)
    }

    func disconnect() {
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        teardown(reason: nil)
    }

    /// Send raw bytes to the Flipper, chunked to the negotiated MTU. Serialized by the caller
    /// (`FlipperProtocol`), so at most one write is outstanding.
    ///
    /// The write type follows the characteristic's advertised properties: `.withResponse` when the
    /// characteristic supports it (we can await the write ack), otherwise `.withoutResponse` (no ack
    /// is delivered, so we pace with a short delay for flow control). Some Flipper firmwares expose a
    /// write-without-response-only serial characteristic, where always using `.withResponse` would
    /// fail and awaiting an ack would hang.
    func send(_ data: Data) async throws {
        guard let peripheral, let tx = txCharacteristic else { throw FlipperError.notConnected }
        let useResponse = tx.properties.contains(.write)
        let writeType: CBCharacteristicWriteType = useResponse ? .withResponse : .withoutResponse
        let mtu = peripheral.maximumWriteValueLength(for: writeType)
        let chunkSize = max(20, mtu)
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            let chunk = data.subdata(in: offset..<end)
            if useResponse {
                try await writeChunk(chunk, to: tx, on: peripheral)
            } else {
                peripheral.writeValue(chunk, for: tx, type: .withoutResponse)
                try await Task.sleep(for: .milliseconds(12)) // pace no-response writes
            }
            offset = end
        }
    }

    // MARK: - Internals

    @ObservationIgnored private var retainedPeripherals: [UUID: CBPeripheral] = [:]

    private func discoveredPeripheral(for id: UUID) -> CBPeripheral? { retainedPeripherals[id] }

    private func writeChunk(_ chunk: Data, to characteristic: CBCharacteristic, on peripheral: CBPeripheral) async throws {
        if writeContinuation != nil { throw FlipperError.writeInFlight }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            writeContinuation = cont
            peripheral.writeValue(chunk, for: characteristic, type: .withResponse)
        }
    }

    private func teardown(reason: String?) {
        writeContinuation?.resume(throwing: FlipperError.notConnected)
        writeContinuation = nil
        txCharacteristic = nil
        rxCharacteristic = nil
        peripheral = nil
        connectedName = nil
        pendingConnectId = nil
        connectionState = .disconnected(reason)
    }

    private func mapCentralState() -> FlipperConnectionState {
        switch central.state {
        case .poweredOff: return .poweredOff
        case .unauthorized: return .unauthorized
        default: return .idle
        }
    }

    fileprivate func handleInbound(_ data: Data) {
        inboundContinuation?.yield(data)
    }
}

// MARK: - CBCentralManagerDelegate

extension FlipperBLEManager: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            switch central.state {
            case .poweredOn:
                if connectionState == .poweredOff { connectionState = .idle }
            case .poweredOff:
                connectionState = .poweredOff
            case .unauthorized:
                connectionState = .unauthorized
            default:
                connectionState = .idle
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advName ?? peripheral.name ?? ""
        let advertisesSerial = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
            .contains(FlipperBLEManager.serialServiceHint) ?? false
        guard name.hasPrefix(FlipperBLEManager.namePrefix) || advertisesSerial else { return }

        MainActor.assumeIsolated {
            retainedPeripherals[peripheral.identifier] = peripheral
            let entry = DiscoveredFlipper(id: peripheral.identifier,
                                          name: name.isEmpty ? "Flipper" : name,
                                          rssi: RSSI.intValue)
            if let idx = discovered.firstIndex(where: { $0.id == entry.id }) {
                discovered[idx].rssi = entry.rssi
            } else {
                discovered.append(entry)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            connectedName = peripheral.name
            connectionState = .discovering
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            lastError = error?.localizedDescription ?? "Failed to connect."
            teardown(reason: lastError)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            if let error { lastError = error.localizedDescription }
            teardown(reason: error?.localizedDescription)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension FlipperBLEManager: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard error == nil, let services = peripheral.services else {
                lastError = error?.localizedDescription ?? "Service discovery failed."
                return
            }
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        MainActor.assumeIsolated {
            guard let characteristics = service.characteristics else { return }
            var foundTx: CBCharacteristic?
            var foundRx: CBCharacteristic?
            for ch in characteristics {
                if ch.properties.contains(.notify) || ch.properties.contains(.indicate) {
                    foundRx = ch
                }
                if ch.properties.contains(.write) || ch.properties.contains(.writeWithoutResponse) {
                    foundTx = ch
                }
            }
            // A service exposing both a writable and a notifying characteristic is the serial link.
            if let tx = foundTx, let rx = foundRx {
                txCharacteristic = tx
                rxCharacteristic = rx
                peripheral.setNotifyValue(true, for: rx)
                connectionState = .connected
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        MainActor.assumeIsolated {
            guard characteristic.uuid == rxCharacteristic?.uuid,
                  let value = characteristic.value, !value.isEmpty else { return }
            handleInbound(value)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didWriteValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        MainActor.assumeIsolated {
            let cont = writeContinuation
            writeContinuation = nil
            if let error { cont?.resume(throwing: error) } else { cont?.resume() }
        }
    }
}
