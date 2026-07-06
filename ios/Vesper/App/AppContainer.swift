import Foundation
import Observation

/// Manual dependency container (the iOS analogue of the retired Hilt `AppModule`). Owns the
/// long-lived services and wires them together.
@MainActor
@Observable
final class AppContainer {

    let ble: FlipperBLEManager
    let proto: FlipperProtocol
    let fs: FlipperFileSystem
    let settings: SettingsStore
    let permissions: PermissionService
    let audit: AuditService
    let persistence: PersistenceController
    let openRouter: OpenRouterClient
    let executor: CommandExecutor
    let agent: VesperAgent

    init() {
        ble = FlipperBLEManager()
        proto = FlipperProtocol(transport: ble)
        fs = FlipperFileSystem(proto: proto)
        settings = SettingsStore()
        permissions = PermissionService()
        audit = AuditService()
        persistence = PersistenceController()
        openRouter = OpenRouterClient()
        executor = CommandExecutor(fs: fs,
                                   ble: ble,
                                   permissions: permissions,
                                   audit: audit,
                                   settings: settings)
        agent = VesperAgent(client: openRouter,
                            executor: executor,
                            settings: settings,
                            audit: audit,
                            persistence: persistence)

        // Persist every audit entry.
        audit.sink = { [weak self] entry in
            self?.persistence.persist(entry)
        }

        // Begin consuming inbound BLE bytes.
        let proto = self.proto
        Task { await proto.start() }
    }
}
