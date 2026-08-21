import AppKit
import UserNotifications

final class SmartCleanView: NSView {
    private var groups: [CleanGroup] = []
    private var scanning = false
    private var cleaned = false

    private let scanButton = NSButton(title: "Scan", target: nil, action: nil)
    private let cleanButton = NSButton(title: "Clean Selected", target: nil, action: nil)
    private let progressLabel = NSTextField(labelWithString: "Run a scan to see what can be reclaimed.")
    private let totalLabel = NSTextField(labelWithString: "")
    private let table = NSTableView()
    private let scroll = NSScrollView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        let header = NSTextField(labelWithString: "Smart Clean")
        header.font = NSFont.systemFont(ofSize: 22, weight: .semibold)

        scanButton.bezelStyle = .rounded
        scanButton.target = self
        scanButton.action = #selector(startScan(_:))
        scanButton.keyEquivalent = "\r"

        cleanButton.bezelStyle = .rounded
        cleanButton.target = self
        cleanButton.action = #selector(cleanClicked(_:))
        cleanButton.isEnabled = false

        let headerRow = NSStackView(views: [header, NSView(), scanButton, cleanButton])
        headerRow.orientation = .horizontal
        headerRow.spacing = 8
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        progressLabel.textColor = .secondaryLabelColor

        let idCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("check"))
        idCol.title = "Clean"
        idCol.width = 60
        let titleCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        titleCol.title = "Category"
        titleCol.width = 260
        let sizeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeCol.title = "Reclaimable"
        sizeCol.width = 110
        let countCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("count"))
        countCol.title = "Items"
        countCol.width = 80
        let detailCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("detail"))
        detailCol.title = "Details"
        detailCol.width = 380
        table.addTableColumn(idCol)
        table.addTableColumn(titleCol)
        table.addTableColumn(sizeCol)
        table.addTableColumn(countCol)
        table.addTableColumn(detailCol)
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 30
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.headerView = nil

        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = table
        scroll.translatesAutoresizingMaskIntoConstraints = false

        totalLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)

        let column = NSStackView(views: [headerRow, progressLabel, scroll, totalLabel])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 10
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        column.setCustomSpacing(14, after: progressLabel)

        NSLayoutConstraint.activate([
            headerRow.widthAnchor.constraint(equalTo: column.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: column.widthAnchor),
            totalLabel.widthAnchor.constraint(equalTo: column.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 300),
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            column.topAnchor.constraint(equalTo: topAnchor, constant: 22),
            column.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -20)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func startScan(_ sender: Any) {
        guard !scanning else { return }
        scanning = true
        cleaned = false
        groups = []
        table.reloadData()
        scanButton.isEnabled = false
        cleanButton.isEnabled = false
        totalLabel.stringValue = ""
        progressLabel.stringValue = "Scanning..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let result = ScanEngine.shared.scanCleanGroups { text in
                DispatchQueue.main.async {
                    self.progressLabel.stringValue = text
                }
            }
            DispatchQueue.main.async {
                self.scanning = false
                self.groups = result
                self.table.reloadData()
                self.scanButton.isEnabled = true
                self.updateTotals()
                let reclaimable = result.filter { $0.fileCount > 0 }
                if reclaimable.isEmpty {
                    self.progressLabel.stringValue = "Scan finished. Nothing reclaimable found."
                } else {
                    self.progressLabel.stringValue = "Scan finished. Review the list, then Clean Selected."
                    self.cleanButton.isEnabled = true
                }
                self.notifyScanComplete(total: self.reclaimableTotal())
            }
        }
    }

    private func reclaimableTotal() -> Int64 {
        groups.reduce(0) { $0 + ($1.fileCount > 0 ? $1.totalBytes : 0) }
    }

    private func selectedTotal() -> Int64 {
        groups.filter { $0.checked && $0.fileCount > 0 }.reduce(0) { $0 + $1.totalBytes }
    }

    private func updateTotals() {
        let total = reclaimableTotal()
        if groups.isEmpty {
            totalLabel.stringValue = ""
        } else if total > 0 {
            totalLabel.stringValue = "Total reclaimable: " + SystemStats.formatBytes(total) + ". Items are moved to the Trash, nothing is deleted outright."
        } else {
            totalLabel.stringValue = "Nothing to reclaim right now."
        }
    }

    private func notifyScanComplete(total: Int64) {
        guard total > 0 else { return }
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "PuraMacNotifyCleanup") == nil || defaults.bool(forKey: "PuraMacNotifyCleanup") else { return }
        let content = UNMutableNotificationContent()
        content.title = "PuraMac"
        content.body = "Scan complete: " + SystemStats.formatBytes(total) + " reclaimable."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "puramac-scan-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    @objc func cleanClicked(_ sender: Any) {
        let selected = groups.filter { $0.checked && $0.fileCount > 0 }
        guard !selected.isEmpty else { return }
        presentReviewSheet(groups: selected)
    }

    private func presentReviewSheet(groups selected: [CleanGroup]) {
        let alert = NSAlert()
        alert.messageText = "Review cleanup"
        alert.informativeText = reviewText(groups: selected)
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window!) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.performClean(groups: selected)
        }
    }

    private func reviewText(groups selected: [CleanGroup]) -> String {
        var lines: [String] = []
        var total: Int64 = 0
        for group in selected {
            total += group.totalBytes
            var line = group.title + ": " + SystemStats.formatBytes(group.totalBytes)
            if group.id == "downloads" {
                line += " across \(group.fileCount) files"
            } else if group.id == "trash" {
                line += " across \(group.fileCount) items"
            } else {
                line += " in \(group.fileCount) files"
            }
            lines.append(line)
            for path in group.paths.prefix(3) {
                lines.append("   " + abbreviateHome(path))
            }
        }
        lines.append("")
        lines.append("Total: " + SystemStats.formatBytes(total))
        lines.append("Everything goes to the Trash so you can undo it.")
        return lines.joined(separator: "\n")
    }

    private func abbreviateHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func performClean(groups selected: [CleanGroup]) {
        scanButton.isEnabled = false
        cleanButton.isEnabled = false
        progressLabel.stringValue = "Cleaning..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let result = ScanEngine.shared.clean(groups: selected) { text in
                DispatchQueue.main.async {
                    self.progressLabel.stringValue = text
                }
            }
            DispatchQueue.main.async {
                self.scanButton.isEnabled = true
                self.cleaned = true
                self.groups = []
                self.table.reloadData()
                self.totalLabel.stringValue = ""
                let freedText = SystemStats.formatBytes(result.freedBytes)
                if result.failedCount > 0 {
                    self.progressLabel.stringValue = "Cleanup finished: " + freedText + " moved to Trash. \(result.failedCount) items could not be moved."
                } else {
                    self.progressLabel.stringValue = "Cleanup finished: " + freedText + " moved to Trash."
                }
                self.notifyCleanupComplete(freed: result.freedBytes)
            }
        }
    }

    private func notifyCleanupComplete(freed: Int64) {
        guard freed > 0 else { return }
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "PuraMacNotifyCleanup") != nil && !defaults.bool(forKey: "PuraMacNotifyCleanup") {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "PuraMac"
        content.body = "PuraMac freed " + SystemStats.formatBytes(freed) + "."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "puramac-clean-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

extension SmartCleanView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        groups.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < groups.count else { return nil }
        let group = groups[row]
        let cell = NSTableCellView()

        switch tableColumn?.identifier.rawValue {
        case "check":
            if group.fileCount > 0 {
                let box = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleGroup(_:)))
                box.state = group.checked ? .on : .off
                box.identifier = NSUserInterfaceItemIdentifier(String(row))
                box.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(box)
                NSLayoutConstraint.activate([
                    box.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                    box.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            }
        case "title":
            let title = NSTextField(labelWithString: group.title)
            title.font = NSFont.systemFont(ofSize: 13, weight: group.skippedNote == nil ? .medium : .regular)
            title.textColor = group.skippedNote == nil ? .labelColor : .tertiaryLabelColor
            title.lineBreakMode = .byTruncatingTail
            title.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(title)
            cell.textField = title
            NSLayoutConstraint.activate([
                title.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                title.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        case "size":
            let text = group.skippedNote != nil ? "" : (group.fileCount > 0 ? SystemStats.formatBytes(group.totalBytes) : "0 KB")
            let size = NSTextField(labelWithString: text)
            size.font = NSFont.systemFont(ofSize: 13)
            size.alignment = .right
            size.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(size)
            NSLayoutConstraint.activate([
                size.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                size.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                size.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        case "count":
            let text = group.skippedNote != nil ? "" : "\(group.fileCount)"
            let count = NSTextField(labelWithString: text)
            count.font = NSFont.systemFont(ofSize: 13)
            count.textColor = .secondaryLabelColor
            count.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(count)
            NSLayoutConstraint.activate([
                count.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                count.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                count.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        default:
            let detailText: String
            if let note = group.skippedNote {
                detailText = note
            } else if group.id == "downloads" {
                detailText = group.paths.prefix(3).map { abbreviateHome($0) }.joined(separator: "\n")
            } else {
                let samples = group.paths.prefix(3).map { abbreviateHome($0) }.joined(separator: "\n")
                detailText = samples.isEmpty ? group.detail : samples
            }
            let detail = NSTextField(wrappingLabelWithString: detailText)
            detail.font = NSFont.systemFont(ofSize: 11)
            detail.textColor = .secondaryLabelColor
            detail.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(detail)
            NSLayoutConstraint.activate([
                detail.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                detail.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                detail.topAnchor.constraint(equalTo: cell.topAnchor, constant: 4),
                detail.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -4)
            ])
        }
        return cell
    }

    @objc private func toggleGroup(_ sender: NSButton) {
        guard let idString = sender.identifier?.rawValue, let row = Int(idString), row < groups.count else { return }
        groups[row].checked = sender.state == .on
        updateTotals()
    }
}
