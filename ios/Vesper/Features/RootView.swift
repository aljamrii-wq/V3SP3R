import SwiftUI

struct RootView: View {
    @Environment(FlipperBLEManager.self) private var ble

    var body: some View {
        TabView {
            ChatView()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.text.bubble.right") }

            DeviceView()
                .tabItem { Label("Device", systemImage: "dot.radiowaves.left.and.right") }

            AuditView()
                .tabItem { Label("Audit", systemImage: "list.bullet.rectangle") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
