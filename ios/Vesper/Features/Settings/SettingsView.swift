import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(PermissionService.self) private var permissions

    @State private var apiKeyDraft = ""
    @State private var savedFlash = false

    var body: some View {
        @Bindable var settings = settings

        return NavigationStack {
            Form {
                apiKeySection
                modelSection(settings: settings)
                safetySection(settings: settings)
                permissionsSection
                aboutSection
            }
            .navigationTitle("Settings")
            .onAppear { apiKeyDraft = settings.apiKey ?? "" }
        }
    }

    // MARK: - API key

    private var apiKeySection: some View {
        Section {
            SecureField("sk-or-…", text: $apiKeyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            HStack {
                Button("Save key") {
                    settings.apiKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    savedFlash = true
                    Task { try? await Task.sleep(for: .seconds(2)); savedFlash = false }
                }
                .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                if savedFlash {
                    Label("Saved to Keychain", systemImage: "checkmark.seal.fill")
                        .font(.caption).foregroundStyle(.green)
                } else if settings.hasApiKey {
                    Label("Key set", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
                }
            }
            if settings.hasApiKey {
                Button("Remove key", role: .destructive) {
                    settings.apiKey = nil
                    apiKeyDraft = ""
                }
            }
        } header: {
            Text("OpenRouter API Key")
        } footer: {
            Text("Stored securely in the iOS Keychain. Get a key at openrouter.ai.")
        }
    }

    // MARK: - Model

    private func modelSection(settings: SettingsStore) -> some View {
        Section("Model") {
            Picker("Model", selection: Binding(
                get: { settings.selectedModel },
                set: { settings.selectedModel = $0 }
            )) {
                ForEach(SettingsStore.recommendedModels, id: \.self) { model in
                    Text(model).tag(model)
                }
                if !SettingsStore.recommendedModels.contains(settings.selectedModel) {
                    Text(settings.selectedModel).tag(settings.selectedModel)
                }
            }
            Stepper("Max steps: \(settings.aiMaxIterations)",
                    value: Binding(get: { settings.aiMaxIterations },
                                   set: { settings.aiMaxIterations = $0 }),
                    in: 1...20)
        }
    }

    // MARK: - Safety

    private func safetySection(settings: SettingsStore) -> some View {
        Section {
            Picker("Operation mode", selection: Binding(
                get: { settings.operationMode },
                set: { settings.operationMode = $0 }
            )) {
                ForEach(OperationMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            Toggle("Auto-approve medium risk", isOn: Binding(
                get: { settings.autoApproveMedium }, set: { settings.autoApproveMedium = $0 }))
            Toggle("Auto-approve high risk", isOn: Binding(
                get: { settings.autoApproveHigh }, set: { settings.autoApproveHigh = $0 }))
        } header: {
            Text("Safety")
        } footer: {
            Text("Recon and Stealth modes block transmit/emulation actions. Irreversible actions "
                 + "(delete, BadUSB, RF transmit, installs) always require confirmation, even with "
                 + "auto-approve on.")
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        Section {
            let unlocks = permissions.activeUnlocks()
            if unlocks.isEmpty {
                Text("No protected paths unlocked.").foregroundStyle(.secondary)
            } else {
                ForEach(unlocks) { unlock in
                    HStack {
                        Text(unlock.pathPrefix).monospaced()
                        Spacer()
                        Button("Lock", role: .destructive) { permissions.lock(unlock.id) }
                            .font(.caption)
                    }
                }
            }
            Button("Unlock /int for 1 hour") {
                permissions.unlock(prefix: "/int", duration: 3600)
            }
        } header: {
            Text("Protected paths")
        } footer: {
            Text("Internal storage and firmware paths are protected by default.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App", value: "Vesper for iOS")
            LabeledContent("Transport", value: "Bluetooth LE")
            Text("An AI brain for your Flipper Zero. Use only on devices you own or are authorized to test.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
