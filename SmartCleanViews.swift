import AppKit
import UserNotifications

private struct CleanRow {
    enum Kind {
        case group
        case item
    }
    let kind: Kind
    let groupIndex: Int?
    let item: CleanItem?

    static func group(_ index: Int) -> CleanRow {
        CleanRow(kind: .group, groupIndex: index, item: nil)
    }
    static func item(_ groupIndex: Int, _ cleanItem: CleanItem) -> CleanRow {
        CleanRow(kind: .item, groupIndex: groupIndex, item: cleanItem)
    }
}

final class SmartCleanView: NSView {
    private var groups: [CleanGroup] = []
    private var expanded: Set<Int> = []
    private var rows: [CleanRow] = []
    private var scanning = false

    private let scanButton = NSButton(title: "Scan", target: nil, action: nil)
    private let cleanButton = NSButton(title: "Move Selected to Trash", target: nil, action: nil)
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

        let checkCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("check"))
        checkCol.title = "Clean"
        checkCol.width = 56
        let mainCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        mainCol.title = "Category"
        mainCol.width = 560
        let sizeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeCol.title = "Reclaimable"
        sizeCol.width = 120
        let countCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("count"))
        countCol.title = "Items"
        countCol.width = 80
        table.addTableColumn(checkCol)
        table.addTableColumn(mainCol)
        table.addTableColumn(sizeCol)
        table.addTableColumn(countCol)
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 44
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

    private func rebuildRows() {
        var newRows: [CleanRow] = []
        for index in groups.indices {
            newRows.append(.group(index))
            guard expanded.contains(index) else { continue }
            for item in groups[index].largestItems.prefix(6) {
                newRows.append(.item(index, item))
            }
        }
        rows = newRows
    }

    @objc func startScan(_ sender: Any) {
        guard !scanning else { return }
        scanning = true
        groups = []
        expanded = []
        rows = []
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
                self.rebuildRows()
                self.table.reloadData()
                self.scanButton.isEnabled = true
                self.updateTotals()
                let reclaimable = result.filter { $0.fileCount > 0 && $0.skippedNote == nil }
                if reclaimable.isEmpty {
                    self.progressLabel.stringValue = "Scan finished. Nothing reclaimable found."
                } else {
                    self.progressLabel.stringValue = "Scan finished. Expand any category to see exactly what would be trashed."
                    self.cleanButton.isEnabled = true
                }
                self.notifyScanComplete(total: self.reclaimableTotal())
            }
        }
    }

    private func reclaimableTotal() -> Int64 {
        groups.reduce(0) { $0 + ($1.fileCount > 0 && $1.id != "brewcache" ? $1.totalBytes : 0) }
    }

    private func selectedTotal() -> Int64 {
        groups.filter { $0.checked && $0.fileCount > 0 && $0.id != "brewcache" }.reduce(0) { $0 + $1.totalBytes }
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
        var reviewRows: [ReviewRow] = []
        var total: Int64 = 0
        var itemCount = 0
        for group in selected {
            total += group.totalBytes
            itemCount += max(1, group.fileCount)
            var leading = group.title + "  " + SystemStats.formatBytes(group.totalBytes)
            if group.fileCount > 0 {
                leading += ", \(group.fileCount) files"
            }
            reviewRows.append(ReviewRow(leading: leading, detail: group.detail))
            for path in group.paths.prefix(3) {
                reviewRows.append(ReviewRow(leading: "", detail: abbreviateHome(path)))
            }
        }
        ReviewSheets.show(
            on: window!,
            title: "Review cleanup",
            rows: reviewRows,
            totalBytes: total,
            itemCount: itemCount,
            confirmTitle: "Move to Trash",
            undoNote: "Everything goes to the Trash so you can undo it.") { [weak self] in
                self?.performClean(groups: selected)
            }
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
                self.groups = []
                self.expanded = []
                self.rows = []
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
        rows.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch rows[row].kind {
        case .group: return 44
        case .item: return 22
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .group = rows[row].kind {
            return true
        }
        return false
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        table.deselectAll(nil)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < rows.count else { return nil }
        let entry = rows[row]
        let cell = NSTableCellView()

        switch entry.kind {
        case .group:
            guard let index = entry.groupIndex, index < groups.count else { return cell }
            buildGroupCell(cell, column: tableColumn?.identifier.rawValue ?? "", index: index)
        case .item:
            buildItemCell(cell, column: tableColumn?.identifier.rawValue ?? "", entry: entry)
        }
        return cell
    }

    private func buildGroupCell(_ cell: NSView, column: String, index: Int) {
        let group = groups[index]
        switch column {
        case "check":
            guard group.fileCount > 0 && group.id != "brewcache" else { return }
            let box = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleGroup(_:)))
            box.state = group.checked ? .on : .off
            box.identifier = NSUserInterfaceItemIdentifier(String(index))
            box.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(box)
            NSLayoutConstraint.activate([
                box.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                box.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        case "main":
            let title = NSTextField(labelWithString: group.title)
            title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            title.textColor = .labelColor
            title.lineBreakMode = .byTruncatingTail
            title.translatesAutoresizingMaskIntoConstraints = false

            let subtitle = NSTextField(labelWithString: group.skippedNote ?? group.detail)
            subtitle.font = NSFont.systemFont(ofSize: 11)
            subtitle.textColor = .secondaryLabelColor
            subtitle.lineBreakMode = .byTruncatingTail
            subtitle.translatesAutoresizingMaskIntoConstraints = false

            let canExpand = !group.largestItems.isEmpty && group.skippedNote == nil
            var disclosure: NSButton?
            if canExpand {
                let button = NSButton(title: "", target: self, action: #selector(toggleExpand(_:)))
                button.bezelStyle = .disclosure
                button.setButtonType(.pushOnPushOff)
                button.state = expanded.contains(index) ? .on : .off
                button.identifier = NSUserInterfaceItemIdentifier(String(index))
                button.translatesAutoresizingMaskIntoConstraints = false
                disclosure = button
                cell.addSubview(button)
            }

            cell.addSubview(title)
            cell.addSubview(subtitle)

            var constraints: [NSLayoutConstraint] = [
                title.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                title.topAnchor.constraint(equalTo: cell.topAnchor, constant: 6),
                subtitle.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                subtitle.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
                subtitle.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -6)
            ]
            if let disclosure = disclosure {
                constraints.append(disclosure.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2))
                constraints.append(disclosure.centerYAnchor.constraint(equalTo: cell.centerYAnchor))
                constraints[0] = title.leadingAnchor.constraint(equalTo: disclosure.trailingAnchor, constant: 4)
                constraints[4] = subtitle.leadingAnchor.constraint(equalTo: disclosure.trailingAnchor, constant: 4)
            }
            NSLayoutConstraint.activate(constraints)
        case "size":
            let text = group.skippedNote != nil ? "" : (group.fileCount > 0 ? SystemStats.formatBytes(group.totalBytes) : "0 KB")
            let size = NSTextField(labelWithString: text)
            size.font = NSFont.systemFont(ofSize: 13)
            size.alignment = .right
            size.lineBreakMode = .byTruncatingTail
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
            count.alignment = .center
            count.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(count)
            NSLayoutConstraint.activate([
                count.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                count.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                count.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        default:
            break
        }
    }

    private func buildItemCell(_ cell: NSView, column: String, entry: CleanRow) {
        guard let item = entry.item else { return }
        switch column {
        case "check", "count":
            break
        case "size":
            let size = NSTextField(labelWithString: SystemStats.formatBytes(item.sizeBytes))
            size.font = NSFont.systemFont(ofSize: 11)
            size.textColor = .secondaryLabelColor
            size.alignment = .right
            size.lineBreakMode = .byTruncatingTail
            size.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(size)
            NSLayoutConstraint.activate([
                size.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                size.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                size.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        case "main":
            let name = NSTextField(labelWithString: abbreviateHome(item.path))
            name.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            name.textColor = .secondaryLabelColor
            name.lineBreakMode = .byTruncatingTail
            name.cell?.truncatesLastVisibleLine = true
            name.cell?.wraps = false
            name.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(name)
            NSLayoutConstraint.activate([
                name.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 28),
                name.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                name.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        default:
            break
        }
    }

    @objc private func toggleGroup(_ sender: NSButton) {
        guard let idString = sender.identifier?.rawValue, let index = Int(idString), index < groups.count else { return }
        groups[index].checked = sender.state == .on
        updateTotals()
    }

    @objc private func toggleExpand(_ sender: NSButton) {
        guard let idString = sender.identifier?.rawValue, let index = Int(idString), index < groups.count else { return }
        if expanded.contains(index) {
            expanded.remove(index)
            sender.state = .off
        } else {
            expanded.insert(index)
            sender.state = .on
        }
        rebuildRows()
        table.reloadData()
    }
}
