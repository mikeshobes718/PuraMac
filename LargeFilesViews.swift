import AppKit
import Quartz
import QuickLookThumbnailing
import UserNotifications

final class LargeFilesTable: NSTableView {
    var onSpace: (() -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 {
            onSpace?()
            return
        }
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}

final class QuickLookItem: NSObject, QLPreviewItem {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    var previewItemURL: URL? { fileURL }
    var previewItemTitle: String? { fileURL.lastPathComponent }
}

final class LargeFilesView: NSView {
    private struct Row {
        let isDetail: Bool
        let itemIndex: Int
    }

    private var items: [LargeFileItem] = []
    private var rows: [Row] = []
    private var expandedItem: Int?
    private var selectedItems: Set<Int> = []
    private var scanning = false
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private var generatingKeys: Set<String> = []

    private let scanButton = NSButton(title: "Scan Home", target: nil, action: nil)
    private let moveButton = NSButton(title: "Move to Trash", target: nil, action: nil)
    private let quickLookButton = NSButton(title: "Quick Look", target: nil, action: nil)
    private let thumbToggle = NSButton(checkboxWithTitle: "Thumbnails", target: nil, action: nil)
    private let progressLabel = NSTextField(labelWithString: "Find files over 100 MB anywhere in your home folder.")
    private let totalLabel = NSTextField(labelWithString: "")
    private let table = LargeFilesTable()
    private let scroll = NSScrollView()

    private var thumbnailsOn: Bool {
        UserDefaults.standard.bool(forKey: "PuraMacLargeFilesThumbnails")
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        thumbnailCache.countLimit = 400

        let header = NSTextField(labelWithString: "Large Files")
        header.font = NSFont.systemFont(ofSize: 22, weight: .semibold)

        scanButton.bezelStyle = .rounded
        scanButton.target = self
        scanButton.action = #selector(startScan(_:))

        moveButton.bezelStyle = .rounded
        moveButton.target = self
        moveButton.action = #selector(moveClicked(_:))
        moveButton.isEnabled = false

        quickLookButton.bezelStyle = .rounded
        quickLookButton.target = self
        quickLookButton.action = #selector(quickLookClicked(_:))
        quickLookButton.isEnabled = false

        thumbToggle.target = self
        thumbToggle.action = #selector(thumbnailsToggled(_:))
        thumbToggle.state = thumbnailsOn ? .on : .off

        let headerRow = NSStackView(views: [header, NSView(), thumbToggle, quickLookButton, scanButton, moveButton])
        headerRow.orientation = .horizontal
        headerRow.spacing = 8
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        progressLabel.textColor = .secondaryLabelColor

        let previewCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("preview"))
        previewCol.title = ""
        previewCol.width = 60
        let checkCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("check"))
        checkCol.title = ""
        checkCol.width = 40
        let sizeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeCol.title = "Size"
        sizeCol.width = 100
        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "File"
        nameCol.width = 512
        let modCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("mod"))
        modCol.title = "Modified"
        modCol.width = 150
        table.addTableColumn(previewCol)
        table.addTableColumn(checkCol)
        table.addTableColumn(sizeCol)
        table.addTableColumn(nameCol)
        table.addTableColumn(modCol)
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(rowDoubleClicked(_:))
        table.rowHeight = 26
        table.usesAlternatingRowBackgroundColors = true
        table.onSpace = { [weak self] in self?.showQuickLook() }
        table.onEscape = { [weak self] in self?.collapseExpanded() }

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

    private func rebuildRows() {
        var out: [Row] = []
        for index in items.indices {
            out.append(Row(isDetail: false, itemIndex: index))
            if expandedItem == index {
                out.append(Row(isDetail: true, itemIndex: index))
            }
        }
        rows = out
    }

    private func itemIndex(forTableRow row: Int) -> Int? {
        guard row >= 0, row < rows.count else { return nil }
        return rows[row].isDetail ? nil : rows[row].itemIndex
    }

    private func detailRowPosition(forItem item: Int) -> Int? {
        rows.firstIndex(where: { $0.isDetail && $0.itemIndex == item })
    }

    private func collapseExpanded() {
        guard expandedItem != nil else { return }
        expandedItem = nil
        rebuildRows()
        table.reloadData()
    }

    private func toggleExpand(item: Int) {
        if expandedItem == item {
            expandedItem = nil
        } else {
            expandedItem = item
        }
        rebuildRows()
        table.reloadData()
        if let detailPos = detailRowPosition(forItem: item) {
            table.scrollRowToVisible(detailPos)
        }
    }

    @objc func startScan(_ sender: Any) {
        guard !scanning else { return }
        scanning = true
        items = []
        selectedItems = []
        expandedItem = nil
        rebuildRows()
        table.reloadData()
        scanButton.isEnabled = false
        moveButton.isEnabled = false
        quickLookButton.isEnabled = false
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
                self.rebuildRows()
                self.table.reloadData()
                self.scanButton.isEnabled = true
                let totalBytes = result.reduce(Int64(0)) { $0 + $1.sizeBytes }
                if result.isEmpty {
                    self.progressLabel.stringValue = "No files over 100 MB found in the scanned folders."
                } else {
                    self.progressLabel.stringValue = "Top \(result.count) files over 100 MB. Expand a row for a large preview, double-click for Quick Look."
                    self.moveButton.isEnabled = true
                }
                self.totalLabel.stringValue = result.isEmpty ? "" : String(format: "%d files, %@ total", result.count, SystemStats.formatBytes(totalBytes))
            }
        }
    }

    @objc private func thumbnailsToggled(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "PuraMacLargeFilesThumbnails")
        table.reloadData()
    }

    @objc private func rowDoubleClicked(_ sender: Any) {
        guard itemIndex(forTableRow: table.clickedRow) != nil else { return }
        showQuickLook()
    }

    @objc private func quickLookClicked(_ sender: Any) {
        showQuickLook()
    }

    private func showQuickLook() {
        guard itemIndex(forTableRow: table.selectedRow) != nil else { return }
        window?.makeFirstResponder(table)
        let panel = QLPreviewPanel.shared()
        panel?.makeKeyAndOrderFront(nil)
    }

    @objc private func moveClicked(_ sender: Any) {
        let chosen = selectedItems.sorted().map { items[$0] }
        guard !chosen.isEmpty else { return }
        var reviewRows: [ReviewRow] = []
        var total: Int64 = 0
        for item in chosen {
            total += item.sizeBytes
            reviewRows.append(ReviewRow(
                leading: SystemStats.formatBytes(item.sizeBytes),
                detail: abbreviateHome(item.path)))
        }
        ReviewSheets.show(
            on: window!,
            title: "Review removal",
            rows: reviewRows,
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
                self.selectedItems = []
                self.expandedItem = nil
                self.rebuildRows()
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

    private func kindDescription(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        if ["mov", "mp4", "m4v", "avi", "mkv", "wmv"].contains(ext) { return "Video" }
        if ["jpg", "jpeg", "png", "gif", "heic", "heif", "tiff", "bmp", "webp"].contains(ext) { return "Image" }
        if ext == "dmg" || ext == "iso" { return "Disk image" }
        if ["zip", "xip", "gz", "tgz"].contains(ext) { return "Archive" }
        if ext == "app" { return "Application" }
        if ext == "photoslibrary" || ext == "migratedphotolibrary" { return "Photos library" }
        return "File"
    }
}

extension LargeFilesView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row < rows.count else { return 26 }
        return rows[row].isDetail ? 302 : 26
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        !rows[row].isDetail
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        quickLookButton.isEnabled = itemIndex(forTableRow: table.selectedRow) != nil
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < rows.count else { return nil }
        let entry = rows[row]
        let item = items[entry.itemIndex]
        let cell = NSTableCellView()

        if entry.isDetail {
            guard tableColumn?.identifier.rawValue == "name" else { return cell }
            buildDetailCell(cell, item: item, itemIndex: entry.itemIndex)
            return cell
        }

        switch tableColumn?.identifier.rawValue {
        case "preview":
            buildPreviewCell(cell, item: item, row: row, itemIndex: entry.itemIndex)
        case "check":
            let box = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleRow(_:)))
            box.state = selectedItems.contains(entry.itemIndex) ? .on : .off
            box.identifier = NSUserInterfaceItemIdentifier(String(entry.itemIndex))
            box.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(box)
            NSLayoutConstraint.activate([
                box.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                box.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        case "size":
            let size = NSTextField(labelWithString: SystemStats.formatBytes(item.sizeBytes))
            size.font = NSFont.systemFont(ofSize: 12)
            size.lineBreakMode = .byTruncatingTail
            size.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(size)
            NSLayoutConstraint.activate([
                size.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                size.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
                size.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        case "mod":
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let mod = NSTextField(labelWithString: formatter.string(from: item.modified))
            mod.font = NSFont.systemFont(ofSize: 12)
            mod.textColor = .secondaryLabelColor
            mod.lineBreakMode = .byTruncatingTail
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
            name.cell?.truncatesLastVisibleLine = true
            name.cell?.wraps = false
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

    private func buildPreviewCell(_ cell: NSView, item: LargeFileItem, row: Int, itemIndex: Int) {
        let disclosure = NSButton(title: "", target: self, action: #selector(toggleExpandFromButton(_:)))
        disclosure.bezelStyle = .disclosure
        disclosure.setButtonType(.pushOnPushOff)
        disclosure.state = expandedItem == itemIndex ? .on : .off
        disclosure.identifier = NSUserInterfaceItemIdentifier(String(itemIndex))
        disclosure.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(disclosure)
        NSLayoutConstraint.activate([
            disclosure.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            disclosure.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])

        if !thumbnailsOn {
            return
        }

        let key = "chip|" + item.path + "|\(item.sizeBytes)"
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        cell.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: disclosure.trailingAnchor, constant: 2),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 38),
            imageView.heightAnchor.constraint(equalToConstant: 38)
        ])

        if let cached = thumbnailCache.object(forKey: key as NSString) {
            imageView.image = cached
            return
        }
        imageView.image = fallbackIcon(for: item.path)
        guard generatingKeys.insert(key).inserted else { return }
        generateThumbnail(key: key, path: item.path) { [weak self] image in
            guard let self = self, let image = image else { return }
            self.thumbnailCache.setObject(image, forKey: key as NSString)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let visible = self.table.rows(in: self.scroll.documentView?.visibleRect ?? .zero)
                if (visible.lowerBound - 5)...(visible.upperBound + 5) ~= row {
                    self.table.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0..<self.table.numberOfColumns))
                }
            }
        }
    }

    private func buildDetailCell(_ cell: NSView, item: LargeFileItem, itemIndex: Int) {
        let key = "big|" + item.path + "|\(item.sizeBytes)"

        let imageHolder = NSView()
        imageHolder.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(imageHolder)
        NSLayoutConstraint.activate([
            imageHolder.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 14),
            imageHolder.topAnchor.constraint(equalTo: cell.topAnchor, constant: 14),
            imageHolder.bottomAnchor.constraint(lessThanOrEqualTo: cell.bottomAnchor, constant: -14),
            imageHolder.widthAnchor.constraint(equalToConstant: 272),
            imageHolder.heightAnchor.constraint(equalToConstant: 272)
        ])

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageHolder.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: imageHolder.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: imageHolder.centerYAnchor),
            imageView.widthAnchor.constraint(lessThanOrEqualTo: imageHolder.widthAnchor),
            imageView.heightAnchor.constraint(lessThanOrEqualTo: imageHolder.heightAnchor)
        ])

        if let cached = thumbnailCache.object(forKey: key as NSString) {
            imageView.image = cached
        } else {
            let spinner = NSProgressIndicator()
            spinner.style = .spinning
            spinner.controlSize = .regular
            spinner.startAnimation(nil)
            spinner.translatesAutoresizingMaskIntoConstraints = false
            imageHolder.addSubview(spinner)
            NSLayoutConstraint.activate([
                spinner.centerXAnchor.constraint(equalTo: imageHolder.centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: imageHolder.centerYAnchor)
            ])
            let waiting = NSTextField(labelWithString: "Generating preview...")
            waiting.font = NSFont.systemFont(ofSize: 11)
            waiting.textColor = .secondaryLabelColor
            waiting.translatesAutoresizingMaskIntoConstraints = false
            imageHolder.addSubview(waiting)
            NSLayoutConstraint.activate([
                waiting.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 8),
                waiting.centerXAnchor.constraint(equalTo: imageHolder.centerXAnchor)
            ])
            if generatingKeys.insert(key).inserted {
                generateLargePreview(key: key, path: item.path) { [weak self] image in
                    guard let self = self else { return }
                    if let image = image {
                        self.thumbnailCache.setObject(image, forKey: key as NSString)
                    }
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self,
                              self.expandedItem == itemIndex,
                              let pos = self.detailRowPosition(forItem: itemIndex) else { return }
                        self.table.reloadData(forRowIndexes: IndexSet(integer: pos), columnIndexes: IndexSet(integersIn: 0..<self.table.numberOfColumns))
                    }
                }
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        let captions = NSStackView()
        captions.orientation = .vertical
        captions.alignment = .leading
        captions.spacing = 6
        captions.translatesAutoresizingMaskIntoConstraints = false

        let pathLabel = NSTextField(labelWithString: abbreviateHome(item.path))
        pathLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.cell?.truncatesLastVisibleLine = true
        pathLabel.cell?.wraps = false

        let kindLabel = NSTextField(labelWithString: kindDescription(for: item.path))
        kindLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)

        let sizeLine = NSTextField(labelWithString: "Size: " + SystemStats.formatBytes(item.sizeBytes))
        sizeLine.font = NSFont.systemFont(ofSize: 12)
        sizeLine.textColor = .secondaryLabelColor

        let modLine = NSTextField(labelWithString: "Modified: " + formatter.string(from: item.modified))
        modLine.font = NSFont.systemFont(ofSize: 12)
        modLine.textColor = .secondaryLabelColor

        let hint = NSTextField(labelWithString: "Double-click the row for the full Quick Look preview.")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor

        captions.addArrangedSubview(kindLabel)
        captions.addArrangedSubview(pathLabel)
        captions.addArrangedSubview(sizeLine)
        captions.addArrangedSubview(modLine)
        captions.addArrangedSubview(hint)
        cell.addSubview(captions)
        NSLayoutConstraint.activate([
            captions.leadingAnchor.constraint(equalTo: imageHolder.trailingAnchor, constant: 20),
            captions.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -12),
            captions.topAnchor.constraint(greaterThanOrEqualTo: cell.topAnchor, constant: 20),
            captions.bottomAnchor.constraint(lessThanOrEqualTo: cell.bottomAnchor, constant: -20),
            captions.centerYAnchor.constraint(equalTo: imageHolder.centerYAnchor),
            pathLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 200)
        ])
    }

    @objc private func toggleExpandFromButton(_ sender: NSButton) {
        guard let idString = sender.identifier?.rawValue, let item = Int(idString), item < items.count else { return }
        toggleExpand(item: item)
    }

    @objc private func toggleRow(_ sender: NSButton) {
        guard let idString = sender.identifier?.rawValue, let item = Int(idString), item < items.count else { return }
        if sender.state == .on {
            selectedItems.insert(item)
        } else {
            selectedItems.remove(item)
        }
    }

    private func isMediaFile(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "heic", "heif", "tiff", "bmp", "webp",
                "mov", "mp4", "m4v", "avi", "mkv", "wmv"].contains(ext)
    }

    private func fallbackIcon(for path: String) -> NSImage? {
        NSWorkspace.shared.icon(forFile: path)
    }

    private func generateThumbnail(key: String, path: String, completion: @escaping (NSImage?) -> Void) {
        let queue = DispatchQueue.global(qos: .utility)
        queue.async { [weak self] in
            defer { DispatchQueue.main.async { self?.generatingKeys.remove(key) } }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
                completion(nil)
                return
            }
            if self?.isMediaFile(path) != true {
                completion(self?.fallbackIcon(for: path))
                return
            }
            let request = QLThumbnailGenerator.Request(
                fileAt: URL(fileURLWithPath: path),
                size: CGSize(width: 40, height: 40),
                scale: NSScreen.main?.backingScaleFactor ?? 2,
                representationTypes: .thumbnail)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                if let rep = rep {
                    completion(rep.nsImage)
                } else {
                    completion(NSWorkspace.shared.icon(forFile: path))
                }
            }
        }
    }

    private func generateLargePreview(key: String, path: String, completion: @escaping (NSImage?) -> Void) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            defer { DispatchQueue.main.async { self?.generatingKeys.remove(key) } }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
                completion(nil)
                return
            }
            let ext = (path as NSString).pathExtension.lowercased()
            if ["jpg", "jpeg", "png", "heic", "heif", "tiff", "bmp", "webp"].contains(ext),
               let image = Self.decodedImageThumbnail(path: path, maxPixelSize: 1400) {
                completion(image)
                return
            }
            let request = QLThumbnailGenerator.Request(
                fileAt: URL(fileURLWithPath: path),
                size: CGSize(width: 600, height: 600),
                scale: 2,
                representationTypes: .all)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                if let rep = rep {
                    completion(rep.nsImage)
                } else {
                    completion(NSWorkspace.shared.icon(forFile: path))
                }
            }
        }
    }

    private static func decodedImageThumbnail(path: String, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width / 2, height: cgImage.height / 2))
    }
}

extension LargeFilesView: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel) {
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        1
    }

    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> QLPreviewItem? {
        let tableRow = table.selectedRow
        guard tableRow >= 0,
              let item = itemIndex(forTableRow: tableRow),
              item < items.count else { return nil }
        return QuickLookItem(fileURL: URL(fileURLWithPath: items[item].path))
    }
}
