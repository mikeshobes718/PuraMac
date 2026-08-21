import AppKit

struct ReviewRow {
    let leading: String
    let detail: String
}

final class ReviewSheetController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private var rows: [ReviewRow] = []
    private let footerText: String
    private let confirmTitle: String
    private let onConfirm: () -> Void
    private weak var sheetWindow: NSWindow?

    private let table = NSTableView()
    private var scrollViewHeight: CGFloat

    init(title: String, rows: [ReviewRow], footerText: String, confirmTitle: String, onConfirm: @escaping () -> Void) {
        self.rows = rows
        self.footerText = footerText
        self.confirmTitle = confirmTitle
        self.onConfirm = onConfirm
        self.scrollViewHeight = min(360, max(120, CGFloat(rows.count) * 24 + 8))
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: scrollViewHeight + 118))

        let header = NSTextField(labelWithString: title ?? "")
        header.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        header.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(header)

        let leadCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("lead"))
        leadCol.title = "Item"
        leadCol.width = 170
        let detailCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("detail"))
        detailCol.title = "Path"
        detailCol.width = 370
        table.addTableColumn(leadCol)
        table.addTableColumn(detailCol)
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 24
        table.headerView = nil
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.focusRingType = .none

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = table
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)

        let footer = NSTextField(wrappingLabelWithString: footerText)
        footer.font = NSFont.systemFont(ofSize: 12)
        footer.textColor = .secondaryLabelColor
        footer.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(footer)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked(_:)))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        cancel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(cancel)

        let confirm = NSButton(title: confirmTitle, target: self, action: #selector(confirmClicked(_:)))
        confirm.bezelStyle = .rounded
        confirm.keyEquivalent = "\r"
        confirm.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(confirm)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            scroll.heightAnchor.constraint(equalToConstant: scrollViewHeight),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            footer.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10),
            cancel.trailingAnchor.constraint(equalTo: confirm.leadingAnchor, constant: -8),
            cancel.centerYAnchor.constraint(equalTo: confirm.centerYAnchor),
            confirm.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            confirm.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])

        view = content
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < rows.count else { return nil }
        let entry = rows[row]
        let cell = NSTableCellView()
        let isDetail = tableColumn?.identifier.rawValue == "detail"
        let field = NSTextField(labelWithString: isDetail ? entry.detail : entry.leading)
        field.font = NSFont.systemFont(ofSize: isDetail ? 11 : 12)
        if !isDetail {
            field.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        }
        field.lineBreakMode = .byTruncatingTail
        field.cell?.truncatesLastVisibleLine = true
        field.cell?.wraps = false
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        cell.textField = field
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    @objc private func cancelClicked(_ sender: Any) {
        dismiss()
    }

    @objc private func confirmClicked(_ sender: Any) {
        dismiss()
        onConfirm()
    }

    private func dismiss() {
        guard let sheetWin = view.window, let parent = sheetWindow else { return }
        parent.endSheet(sheetWin)
    }

    func present(asSheetFor parent: NSWindow) {
        sheetWindow = parent
        let sheetWin = NSWindow(contentViewController: self)
        sheetWin.styleMask = [.titled, .fullSizeContentView]
        sheetWin.titleVisibility = .hidden
        sheetWin.isMovable = false
        parent.beginSheet(sheetWin) { _ in }
    }
}

enum ReviewSheets {
    static func show(on parent: NSWindow,
                     title: String,
                     rows: [ReviewRow],
                     totalBytes: Int64,
                     itemCount: Int,
                     confirmTitle: String,
                     undoNote: String,
                     onConfirm: @escaping () -> Void) {
        let footer = "\(itemCount == 1 ? "1 item" : "\(itemCount) items"), "
            + SystemStats.formatBytes(totalBytes)
            + " total. "
            + undoNote
        let controller = ReviewSheetController(
            title: title,
            rows: rows,
            footerText: footer,
            confirmTitle: confirmTitle,
            onConfirm: onConfirm)
        controller.present(asSheetFor: parent)
    }
}
