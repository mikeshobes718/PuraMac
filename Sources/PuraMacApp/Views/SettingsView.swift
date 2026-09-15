import SwiftUI
import ServiceManagement
import PuraMacCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var apiKeyDraft = ""
    @State private var keyStatus: String?
    @State private var launchAtLogin = false
    @State private var launchError: String?

    var body: some View {
        @Bindable var preferences = model.preferences

        TabView {
            general(preferences: preferences)
                .tabItem { Label("General", systemImage: "gearshape") }
            assistant(preferences: preferences)
                .tabItem { Label("Assistant", systemImage: "bubble.left") }
            about
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .task { refreshLaunchState() }
        .forceWindowAppearance(preferences.appearance.colorScheme)
    }

    private func general(preferences: Preferences) -> some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: Binding(
                    get: { preferences.appearance },
                    set: { preferences.appearance = $0 })) {
                    ForEach(AppAppearance.allCases) { option in
                        Label(option.label, systemImage: option.symbol).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("System follows this Mac's own light/dark setting. Light and Dark pin PuraMac regardless.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle("Warn me when disk space runs low", isOn: Binding(
                    get: { preferences.autoDiskCheck },
                    set: { preferences.autoDiskCheck = $0 }))
                Toggle("Notify me when a scan or cleanup finishes", isOn: Binding(
                    get: { preferences.notifyOnFinish },
                    set: { preferences.notifyOnFinish = $0 }))

                Picker("Warn below", selection: Binding(
                    get: { preferences.lowDiskThreshold },
                    set: { preferences.lowDiskThreshold = $0 })) {
                    Text("5% free").tag(0.05)
                    Text("10% free").tag(0.10)
                    Text("15% free").tag(0.15)
                    Text("20% free").tag(0.20)
                }
                .disabled(!preferences.autoDiskCheck)
            }

            Section("Menu bar and login") {
                Toggle("Show PuraMac in the menu bar", isOn: Binding(
                    get: { preferences.showMenuBarExtra },
                    set: { preferences.showMenuBarExtra = $0 }))
                Toggle("Start PuraMac at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }))
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Scanning") {
                Picker("Large file threshold", selection: Binding(
                    get: { preferences.largeFileThresholdMB },
                    set: { preferences.largeFileThresholdMB = $0 })) {
                    Text("50 MB").tag(50)
                    Text("100 MB").tag(100)
                    Text("500 MB").tag(500)
                    Text("1 GB").tag(1000)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func assistant(preferences: Preferences) -> some View {
        Form {
            Section("OpenRouter API key") {
                SecureField("sk-or-…", text: $apiKeyDraft)
                HStack {
                    Button("Save Key") { saveKey() }
                        .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Remove Key", role: .destructive) { removeKey() }
                        .disabled(!model.assistant.hasKey)
                    Spacer()
                    if let keyStatus {
                        Text(keyStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(model.assistant.hasKey
                     ? "A key is stored in your login keychain. It is never written to disk in plain text and never logged."
                     : "No key stored yet. Get one at openrouter.ai, then paste it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Default model") {
                Picker("Model", selection: Binding(
                    get: { preferences.aiModel },
                    set: { preferences.aiModel = $0 })) {
                    ForEach(model.assistant.models) { option in
                        VStack(alignment: .leading) {
                            Text(option.name)
                            if !option.subtitle.isEmpty {
                                Text(option.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tag(option.id)
                    }
                }
                Button("Refresh model list") {
                    Task { model.assistant.models = await OpenRouterClient.shared.models(forceRefresh: true) }
                }
            }

            Section("What gets sent") {
                Text("Your disk and memory totals, the macOS version, and — only when you ask for an analysis — the category names and sizes from your last scan. File names, paths and contents never leave this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { model.assistant.refreshKeyState() }
    }

    private var about: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("PuraMac").font(.title2.weight(.semibold))
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0")")
                .foregroundStyle(.secondary)
            Text("PuraMac never deletes outright and never touches anything outside your home folder. Every removal goes to the Trash first, and every removal is listed before it happens.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private func saveKey() {
        do {
            try Credentials.setOpenRouterKey(apiKeyDraft)
            apiKeyDraft = ""
            keyStatus = "Saved to keychain."
            model.assistant.refreshKeyState()
        } catch {
            keyStatus = error.localizedDescription
        }
    }

    private func removeKey() {
        do {
            try Credentials.setOpenRouterKey(nil)
            keyStatus = "Key removed."
            model.assistant.refreshKeyState()
        } catch {
            keyStatus = error.localizedDescription
        }
    }

    private func refreshLaunchState() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchError = nil
        } catch {
            launchError = "Could not change this: \(error.localizedDescription)"
        }
        refreshLaunchState()
    }
}
