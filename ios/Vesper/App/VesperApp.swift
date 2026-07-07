import SwiftUI

@main
struct VesperApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
                .environment(container.agent)
                .environment(container.ble)
                .environment(container.settings)
                .environment(container.audit)
                .environment(container.permissions)
                .tint(.accentColor)
        }
    }
}
