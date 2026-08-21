import AppKit
import ServiceManagement

final class LoginItemsView: NSView {
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "Reading login items...")
    private var entries: [String] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        let header = NSTextField(labelWithString: "Login Items")
        header.font = NSFont.systemFont(ofSize: 22, weight: .semibold)

        let openSettingsButton = NSButton(title: "Open System Settings", target: nil, action: nil)
        openSettingsButton.bezelStyle = .rounded
        openSettingsButton.target = self
        openSettingsButton.action = #selector(openSettings(_:))

        let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
        refreshButton.bezelStyle = .rounded
        refreshButton.target = self
        refreshButton.action = #selector(refreshClicked(_:))

        let headerRow = NSStackView(views: [header, NSView(), refreshButton, openSettingsButton])
        headerRow.orientation = .horizontal
        headerRow.spacing = 8
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "Item"
        nameCol.width = 620
        table.addTableColumn(nameCol)
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 26
        table.usesAlternatingRowBackgroundColors = true

        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = table
        scroll.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.textColor = .secondaryLabelColor

        let column = NSStackView(views: [headerRow, scroll, statusLabel])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 10
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        NSLayoutConstraint.activate([
            headerRow.widthAnchor.constraint(equalTo: column.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: column.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: column.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 340),
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            column.topAnchor.constraint(equalTo: topAnchor, constant: 22),
            column.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -20)
        ])

        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var names: [String] = []
            names.append(contentsOf: Self.launchAgentNames())
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.entries = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                self.table.reloadData()
                self.statusLabel.stringValue = names.isEmpty
                    ? "No third-party login items found."
                    : "\(names.count) login items. PuraMac only lists them, changes happen in System Settings."
            }
        }
    }

    static func launchAgentNames() -> [String] {
        let fm = FileManager.default
        let agents = ("~/Library/LaunchAgents" as NSString).expandingTildeInPath
        guard let contents = try? fm.contentsOfDirectory(atPath: agents) else { return [] }
        var names: [String] = []
        for file in contents where file.hasSuffix(".plist") {
            names.append((file as NSString).deletingPathExtension)
        }
        return names
    }

    @objc private func refreshClicked(_ sender: Any) {
        statusLabel.stringValue = "Reading login items..."
        reload()
    }

    @objc private func openSettings(_ sender: Any) {
        let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
        NSWorkspace.shared.open(url)
    }
}

extension LoginItemsView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        entries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < entries.count else { return nil }
        let cell = NSTableCellView()
        let name = NSTextField(labelWithString: entries[row])
        name.font = NSFont.systemFont(ofSize: 13)
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(name)
        cell.textField = name
        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            name.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            name.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }
}

final class SettingsView: NSView {
    private let autoCheck = NSButton(checkboxWithTitle: "Check disk space automatically", target: nil, action: nil)
    private let notifyCleanup = NSButton(checkboxWithTitle: "Notify when cleanup completes", target: nil, action: nil)
    private let loginToggle = NSButton(checkboxWithTitle: "Start PuraMac at login", target: nil, action: nil)
    private let modelCombo = NSComboBox()
    private let statusLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        let header = NSTextField(labelWithString: "Settings")
        header.font = NSFont.systemFont(ofSize: 22, weight: .semibold)

        let defaults = UserDefaults.standard
        autoCheck.state = defaults.object(forKey: "PuraMacAutoDiskCheck") == nil || defaults.bool(forKey: "PuraMacAutoDiskCheck") ? .on : .off
        notifyCleanup.state = defaults.object(forKey: "PuraMacNotifyCleanup") == nil || defaults.bool(forKey: "PuraMacNotifyCleanup") ? .on : .off
        autoCheck.target = self
        autoCheck.action = #selector(toggleAutoCheck(_:))
        notifyCleanup.target = self
        notifyCleanup.action = #selector(toggleNotify(_:))

        refreshLoginToggle()

        let modelLabel = NSTextField(labelWithString: "Default AI model")
        modelCombo.usesDataSource = false
        for model in OpenRouterClient.shared.modelOptions {
            modelCombo.addItem(withObjectValue: model)
        }
        let saved = defaults.string(forKey: "PuraMacModel") ?? OpenRouterClient.shared.defaultModel
        modelCombo.selectItem(withObjectValue: saved)
        if modelCombo.indexOfItem(withObjectValue: saved) < 0 {
            modelCombo.stringValue = saved
        }
        modelCombo.isEditable = true
        modelCombo.completes = true
        modelCombo.translatesAutoresizingMaskIntoConstraints = false
        modelCombo.target = self
        modelCombo.action = #selector(modelChanged(_:))

        let modelRow = NSStackView(views: [modelLabel, modelCombo])
        modelRow.orientation = .horizontal
        modelRow.spacing = 8
        modelRow.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.textColor = .secondaryLabelColor

        let column = NSStackView(views: [header, autoCheck, notifyCleanup, loginToggle, modelRow, statusLabel])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 12
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        NSLayoutConstraint.activate([
            modelCombo.widthAnchor.constraint(equalToConstant: 300),
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            column.topAnchor.constraint(equalTo: topAnchor, constant: 22)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func refreshLoginToggle() {
        if #available(macOS 13.0, *) {
            loginToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            loginToggle.isEnabled = false
        }
    }

    @objc private func toggleAutoCheck(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "PuraMacAutoDiskCheck")
    }

    @objc private func toggleNotify(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "PuraMacNotifyCleanup")
    }

    @objc private func toggleLogin(_ sender: NSButton) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            statusLabel.stringValue = ""
        } catch {
            statusLabel.stringValue = "Could not change login item: " + error.localizedDescription
        }
        refreshLoginToggle()
    }

    @objc private func modelChanged(_ sender: NSComboBox) {
        let value = sender.stringValue.trimmingCharacters(in: .whitespaces)
        if !value.isEmpty {
            UserDefaults.standard.set(value, forKey: "PuraMacModel")
        }
    }
}
