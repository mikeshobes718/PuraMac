import AppKit
import UserNotifications

final class LargeFilesView: NSView {
    private var items: [LargeFileItem] = []
    private var selected: Set<Int> = []
    private var scanning = false

    private let scanButton = NSButton(title: "Scan Home", target: nil, action: nil)
    private let moveButton = NSButton(title: "Move to Trash", target: nil, action: nil)
    private let progressLabel = NSTextField(labelWithString: "Find files over 100 MB anywhere in your home folder.")
    private let totalLabel = NSTextField(labelWithString: "")
    private let table = NSTableView()
    private let scroll = NSScrollView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        let header = NSTextField(labelWithString: "Large Files")
        header.font = NSFont.systemFont(ofSize: 22, weight: .semibold)

        scanButton.bezelStyle = .rounded
        scanButton.target = self
        scanButton.action = #selector(startScan(_:))

        moveButton.bezelStyle = .rounded
        moveButton.target = self
        moveButton.action = #selector(moveClicked(_:))
        moveButton.isEnabled = false

        let headerRow = NSStackView(views: [header, NSView(), scanButton, moveButton])
        headerRow.orientation = .horizontal
        headerRow.spacing = 8
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        progressLabel.textColor = .secondaryLabelColor

        let checkCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("check"))
        checkCol.title = ""
        checkCol.width = 40
        let sizeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeCol.title = "Size"
        sizeCol.width = 100
        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "File"
        nameCol.width = 560
        let modCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("mod"))
        modCol.title = "Modified"
        modCol.width = 150
        table.addTableColumn(checkCol)
        table.addTableColumn(sizeCol)
        table.addTableColumn(nameCol)
        table.addTableColumn(modCol)
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 26
        table.usesAlternatingRowBackgroundColors = true

        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = table
        scroll.translatesAutoresizingMaskIntoConstraints = false

        totalLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        let column = NSStackView(views: [headerRow, progressLabel, scroll, totalLabel])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 10
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        NSLayoutConstraint.activate([
            headerRow.widthAnchor.constraint(equalTo: column.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: column.widthAnchor),
            totalLabel.widthAnchor.constraint(equalTo: column.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 320),
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
        items = []
        selected = []
        table.reloadData()
        scanButton.isEnabled = false
        moveButton.isEnabled = false
        totalLabel.stringValue = ""
        progressLabel.stringValue = "Scanning home folder..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let result = LargeFileScanner().scan(minimumBytes: 100_000_000) { text in
                DispatchQueue.main.async {
                    self.progressLabel.stringValue = text
                }
            }
            DispatchQueue.main.async {
                self.scanning = false
                self.items = result
                self.table.reloadData()
                self.scanButton.isEnabled = true
                let totalBytes = result.reduce(Int64(0)) { $0 + $1.sizeBytes }
                if result.isEmpty {
                    self.progressLabel.stringValue = "No files over 100 MB found in the scanned folders."
                } else {
                    self.progressLabel.stringValue = "Top \(result.count) files over 100 MB. Select rows, then Move to Trash."
                    self.moveButton.isEnabled = true
                }
                self.totalLabel.stringValue = result.isEmpty ? "" : String(format: "%d files, %@ total", result.count, SystemStats.formatBytes(totalBytes))
            }
        }
    }

    @objc private func moveClicked(_ sender: Any) {
        let chosen = selected.sorted().map { items[$0] }
        guard !chosen.isEmpty else { return }
        var rows: [ReviewRow] = []
        var total: Int64 = 0
        for item in chosen {
            total += item.sizeBytes
            rows.append(ReviewRow(
                leading: SystemStats.formatBytes(item.sizeBytes),
                detail: abbreviateHome(item.path)))
        }
        ReviewSheets.show(
            on: window!,
            title: "Review removal",
            rows: rows,
            totalBytes: total,
            itemCount: chosen.count,
            confirmTitle: "Move to Trash",
            undoNote: "Files go to the Trash so you can undo this.") { [weak self] in
                self?.performMove(paths: chosen.map { $0.path })
            }
    }

    private func abbreviateHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func performMove(paths: [String]) {
        scanButton.isEnabled = false
        moveButton.isEnabled = false
        progressLabel.stringValue = "Moving to Trash..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var freed: Int64 = 0
            var failed = 0
            let fm = FileManager.default
            for path in paths {
                let sized = fileSize(at: path)
                do {
                    var resultingURL: NSURL?
                    try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &resultingURL)
                    freed += sized
                } catch {
                    failed += 1
                }
            }
            DispatchQueue.main.async {
                self.scanButton.isEnabled = true
                let freedText = SystemStats.formatBytes(freed)
                if failed > 0 {
                    self.progressLabel.stringValue = "Moved " + freedText + " to Trash. \(failed) files could not be moved."
                } else {
                    self.progressLabel.stringValue = "Moved " + freedText + " to Trash."
                }
                self.items.removeAll { item in paths.contains(item.path) }
                self.selected = []
                self.table.reloadData()
                self.moveButton.isEnabled = !self.items.isEmpty
                let content = UNMutableNotificationContent()
                content.title = "PuraMac"
                content.body = "PuraMac freed " + freedText + "."
                content.sound = .default
                let request = UNNotificationRequest(identifier: "puramac-large-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
                UNUserNotificationCenter.current().add(request)
            }
        }
    }

    private func fileSize(at path: String) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let raw = attrs[.size] as? NSNumber else { return 0 }
            return raw.int64Value
        }
        var total: Int64 = 0
        if let enumerator = fm.enumerator(atPath: path) {
            while let rel = enumerator.nextObject() as? String {
                let full = path + "/" + rel
                var inner: ObjCBool = false
                guard fm.fileExists(atPath: full, isDirectory: &inner), !inner.boolValue else { continue }
                if let attrs = try? fm.attributesOfItem(atPath: full),
                   let raw = attrs[.size] as? NSNumber {
                    total += raw.int64Value
                }
            }
        }
        return total
    }
}

extension LargeFilesView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < items.count else { return nil }
        let item = items[row]
        let cell = NSTableCellView()

        switch tableColumn?.identifier.rawValue {
        case "check":
            let box = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleRow(_:)))
            box.state = selected.contains(row) ? .on : .off
            box.identifier = NSUserInterfaceItemIdentifier(String(row))
            box.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(box)
            NSLayoutConstraint.activate([
                box.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                box.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        case "size":
            let size = NSTextField(labelWithString: SystemStats.formatBytes(item.sizeBytes))
            size.font = NSFont.systemFont(ofSize: 12)
            size.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(size)
            NSLayoutConstraint.activate([
                size.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                size.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                size.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        case "mod":
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let mod = NSTextField(labelWithString: formatter.string(from: item.modified))
            mod.font = NSFont.systemFont(ofSize: 12)
            mod.textColor = .secondaryLabelColor
            mod.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(mod)
            NSLayoutConstraint.activate([
                mod.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                mod.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                mod.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        default:
            let name = NSTextField(labelWithString: item.path)
            name.font = NSFont.systemFont(ofSize: 12)
            name.lineBreakMode = .byTruncatingMiddle
            name.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(name)
            cell.textField = name
            NSLayoutConstraint.activate([
                name.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                name.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                name.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        return cell
    }

    @objc private func toggleRow(_ sender: NSButton) {
        guard let idString = sender.identifier?.rawValue, let row = Int(idString), row < items.count else { return }
        if sender.state == .on {
            selected.insert(row)
        } else {
            selected.remove(row)
        }
    }
}
