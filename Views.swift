import AppKit
import UserNotifications

final class DiskSpaceMonitor {
    static let shared = DiskSpaceMonitor()
    static let lastLowDiskKey = "PuraMacLastLowDiskNotice"

    private var timer: Timer?

    func start() {
        checkOnce()
        let t = Timer(timeInterval: 1800, target: self, selector: #selector(check), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc func check() {
        checkOnce()
    }

    private func checkOnce() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "PuraMacAutoDiskCheck") == nil || defaults.bool(forKey: "PuraMacAutoDiskCheck") else { return }
        let info = SystemStats.diskInfo()
        guard info.valid, info.totalBytes > 0 else { return }
        let freeFraction = Double(info.freeBytes) / Double(info.totalBytes)
        guard freeFraction < 0.10 else { return }
        if let last = defaults.object(forKey: Self.lastLowDiskKey) as? Date,
           Date().timeIntervalSince(last) < 86400 {
            return
        }
        defaults.set(Date(), forKey: Self.lastLowDiskKey)
        let content = UNMutableNotificationContent()
        content.title = "PuraMac"
        content.body = "Low disk space: only " + SystemStats.formatBytes(info.freeBytes) + " free (" + String(format: "%.0f", freeFraction * 100) + "%)."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "puramac-lowdisk", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

final class SidebarView: NSView {
    struct Entry {
        let id: String
        let symbol: String
        let title: String
    }

    let entries: [Entry] = [
        Entry(id: "dashboard", symbol: "gauge", title: "Dashboard"),
        Entry(id: "clean", symbol: "sparkles", title: "Smart Clean"),
        Entry(id: "large", symbol: "doc.badge.ellipsis", title: "Large Files"),
        Entry(id: "login", symbol: "power", title: "Login Items"),
        Entry(id: "ai", symbol: "bubble.left.and.text.bubble.right", title: "AI Assistant"),
        Entry(id: "settings", symbol: "gearshape", title: "Settings")
    ]

    var onSelect: ((String) -> Void)?
    private var buttons: [SidebarButton] = []
    private var selectedId = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1).cgColor

        let titleField = NSTextField(labelWithString: "PuraMac")
        titleField.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        titleField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleField)

        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 4
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        for entry in entries {
            let button = SidebarButton(entry: entry)
            button.onTap = { [weak self] in
                self?.select(id: entry.id)
                self?.onSelect?(entry.id)
            }
            column.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: 184).isActive = true
            button.heightAnchor.constraint(equalToConstant: 34).isActive = true
            buttons.append(button)
        }

        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            column.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 14)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func select(id: String) {
        selectedId = id
        for button in buttons {
            button.setSelected(button.entry.id == id)
        }
    }
}

final class SidebarButton: NSControl {
    let entry: SidebarView.Entry
    var onTap: (() -> Void)?
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    init(entry: SidebarView.Entry) {
        self.entry = entry
        super.init(frame: NSRect(x: 0, y: 0, width: 184, height: 34))
        wantsLayer = true
        layer?.cornerRadius = 7

        if let image = NSImage(systemSymbolName: entry.symbol, accessibilityDescription: entry.title) {
            iconView.image = image
        }
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        label.stringValue = entry.title
        label.font = NSFont.systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        setSelected(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSelected(_ selected: Bool) {
        if selected {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
            label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            label.font = NSFont.systemFont(ofSize: 13)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onTap?()
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .button
    }

    override func accessibilityLabel() -> String? {
        entry.title
    }

    override func isAccessibilityElement() -> Bool {
        true
    }

    override func accessibilityPerformPress() -> Bool {
        onTap?()
        return true
    }
}

final class StatCard: NSView {
    private let titleField: NSTextField
    private let valueField: NSTextField
    private let detailField: NSTextField

    init(title: String) {
        titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleField.textColor = .secondaryLabelColor

        valueField = NSTextField(labelWithString: "")
        valueField.font = NSFont.systemFont(ofSize: 22, weight: .semibold)

        detailField = NSTextField(labelWithString: "")
        detailField.font = NSFont.systemFont(ofSize: 12)
        detailField.textColor = .secondaryLabelColor
        detailField.lineBreakMode = .byWordWrapping
        detailField.maximumNumberOfLines = 2

        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 110))
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.97, alpha: 1).cgColor
        layer?.cornerRadius = 10

        for sub in [titleField, valueField, detailField] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            addSubview(sub)
        }
        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            valueField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            valueField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 6),
            detailField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            detailField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            detailField.topAnchor.constraint(equalTo: valueField.bottomAnchor, constant: 4)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(value: String, detail: String) {
        valueField.stringValue = value
        detailField.stringValue = detail
    }
}

final class DashboardView: NSView {
    private let diskCard = StatCard(title: "Disk")
    private let memoryCard = StatCard(title: "Memory")
    private let cpuCard = StatCard(title: "CPU")
    private let batteryCard = StatCard(title: "Battery")
    private let systemCard = StatCard(title: "System")
    private let statusLabel = NSTextField(labelWithString: "Ready")
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        let header = NSTextField(labelWithString: "Dashboard")
        header.font = NSFont.systemFont(ofSize: 22, weight: .semibold)

        refreshButton.bezelStyle = .rounded
        refreshButton.target = self
        refreshButton.action = #selector(refresh(_:))

        let headerRow = NSStackView(views: [header, NSView(), refreshButton])
        headerRow.orientation = .horizontal
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        let row1 = NSStackView(views: [diskCard, memoryCard, cpuCard])
        row1.orientation = .horizontal
        row1.distribution = .fillEqually
        row1.spacing = 14
        row1.translatesAutoresizingMaskIntoConstraints = false

        let row2 = NSStackView(views: [batteryCard, systemCard, NSView()])
        row2.orientation = .horizontal
        row2.distribution = .fillEqually
        row2.spacing = 14
        row2.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.textColor = .secondaryLabelColor

        let column = NSStackView(views: [headerRow, row1, row2, statusLabel])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 16
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        for view in [headerRow, row1, row2] {
            view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        }
        for card in [diskCard, memoryCard, cpuCard, batteryCard, systemCard] {
            card.heightAnchor.constraint(equalToConstant: 116).isActive = true
        }

        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            column.topAnchor.constraint(equalTo: topAnchor, constant: 22)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func refresh(_ sender: Any) {
        statusLabel.stringValue = "Refreshing..."
        refreshButton.isEnabled = false

        let disk = SystemStats.diskInfo()
        if disk.valid {
            let usedPercent = Double(disk.usedBytes) / Double(max(1, disk.totalBytes)) * 100
            diskCard.set(
                value: SystemStats.formatBytes(disk.freeBytes) + " free",
                detail: SystemStats.formatBytes(disk.usedBytes) + " used of " + SystemStats.formatBytes(disk.totalBytes) + String(format: " (%.0f%% full)", usedPercent))
        } else {
            diskCard.set(value: "Unknown", detail: "Could not read disk info")
        }

        let memory = SystemStats.memoryInfo()
        memoryCard.set(
            value: String(format: "%.0f%% used", memory.usedPercent * 100),
            detail: SystemStats.formatBytes(memory.usedBytes) + " of " + SystemStats.formatBytes(memory.totalBytes) + ", pressure " + memory.pressureLabel)

        batteryCard.set(value: "", detail: "")
        let battery = SystemStats.batteryInfo()
        if battery.present {
            batteryCard.set(value: "\(battery.percent)%", detail: battery.text)
        } else {
            batteryCard.set(value: "None", detail: battery.text)
        }

        systemCard.set(
            value: SystemStats.osVersionText(),
            detail: "Uptime " + SystemStats.uptimeText())

        statusLabel.stringValue = "Measuring CPU..."
        SystemStats.cpuUsage { [weak self] cpu in
            guard let self = self else { return }
            self.cpuCard.set(
                value: String(format: "%.0f%%", cpu.usagePercent),
                detail: "\(cpu.coreCount) cores sampled")
            self.statusLabel.stringValue = "Up to date"
            self.refreshButton.isEnabled = true
        }
    }
}
