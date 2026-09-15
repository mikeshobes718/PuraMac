import SwiftUI
import UserNotifications
import PuraMacCore

@main
struct PuraMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("PuraMac", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 940, minHeight: 620)
        }
        .defaultSize(width: 1180, height: 780)
        .commands { PuraMacCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
                .frame(width: 560, height: 460)
        }

        MenuBarExtra("PuraMac", systemImage: "sparkles", isInserted: $model.showMenuBarExtra) {
            MenuBarContent()
                .environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        Credentials.migrateLegacyKeyIfNeeded()
        Notifier.requestAuthorizationIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

struct PuraMacCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandMenu("Scan") {
            Button("Smart Clean Scan") {
                model.pane = .smartClean
                model.smartClean.startScan()
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Find Large Files") {
                model.pane = .largeFiles
                model.largeFiles.startScan()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Button("Find Duplicates") {
                model.pane = .duplicates
                model.duplicates.startScan()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Divider()

            Button("Cancel Running Scan") { model.cancelAllScans() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!model.isAnyScanRunning)
        }

        CommandGroup(after: .toolbar) {
            Button("Refresh System Stats") { Task { await model.dashboard.refresh() } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
}
