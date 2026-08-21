import AppKit
import ServiceManagement
import UserNotifications

final class NotifyDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var container: NSView!
    var sidebar: SidebarView!
    var contentHost: NSView!

    var dashboardView: DashboardView!
    var smartCleanView: SmartCleanView!
    var largeFilesView: LargeFilesView!
    var loginItemsView: LoginItemsView!
    var assistantView: AssistantView!
    var settingsView: SettingsView!

    let monitor = DiskSpaceMonitor.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "PuraMac"
        window.minSize = NSSize(width: 1000, height: 660)
        window.center()

        container = NSView(frame: NSRect(x: 0, y: 0, width: 1120, height: 720))
        window.contentView = container
        buildUI()
        buildMenu()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        requestNotificationPermissionIfNeeded()
        monitor.start()
        dashboardView.refresh(self)
    }

    func buildUI() {
        sidebar = SidebarView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.onSelect = { [weak self] id in self?.showPane(id) }
        container.addSubview(sidebar)

        contentHost = NSView()
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentHost)

        dashboardView = DashboardView()
        smartCleanView = SmartCleanView()
        largeFilesView = LargeFilesView()
        loginItemsView = LoginItemsView()
        assistantView = AssistantView()
        settingsView = SettingsView()

        let panes: [NSView] = [dashboardView, smartCleanView, largeFilesView, loginItemsView, assistantView, settingsView]
        for pane in panes {
            pane.translatesAutoresizingMaskIntoConstraints = false
            pane.isHidden = true
            contentHost.addSubview(pane)
            NSLayoutConstraint.activate([
                pane.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
                pane.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
                pane.topAnchor.constraint(equalTo: contentHost.topAnchor),
                pane.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor)
            ])
        }

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: container.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 208),
            contentHost.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentHost.topAnchor.constraint(equalTo: container.topAnchor),
            contentHost.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        sidebar.select(id: "dashboard")
        showPane("dashboard")
    }

    func showPane(_ id: String) {
        for (paneId, pane) in [("dashboard", dashboardView), ("clean", smartCleanView), ("large", largeFilesView), ("login", loginItemsView), ("ai", assistantView), ("settings", settingsView)] {
            pane?.isHidden = (paneId != id)
        }
        if id == "login" {
            loginItemsView.reload()
        }
    }

    func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu(title: "PuraMac")
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About PuraMac", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit PuraMac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        let scanItem = fileMenu.addItem(withTitle: "Scan Now", action: #selector(startScanFromMenu(_:)), keyEquivalent: "r")
        scanItem.target = self

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    @objc func startScanFromMenu(_ sender: Any) {
        sidebar.select(id: "clean")
        showPane("clean")
        smartCleanView.startScan(self)
    }

    func requestNotificationPermissionIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
