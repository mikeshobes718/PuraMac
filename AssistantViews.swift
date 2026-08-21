import AppKit

final class AssistantView: NSView {
    private let transcript = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 300))
    private let scroll = NSScrollView()
    private let input = NSTextField()
    private let sendButton = NSButton(title: "Send", target: nil, action: nil)
    private let analyzeButton = NSButton(title: "Analyze my scan", target: nil, action: nil)
    private let modelCombo = NSComboBox()
    private let statusLabel = NSTextField(labelWithString: "Ask anything about this Mac, or run a scan first and get cleanup advice.")

    private var history: [ChatMessage] = []
    private var busy = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        let header = NSTextField(labelWithString: "AI Assistant")
        header.font = NSFont.systemFont(ofSize: 22, weight: .semibold)

        modelCombo.usesDataSource = false
        for model in OpenRouterClient.shared.modelOptions {
            modelCombo.addItem(withObjectValue: model)
        }
        let saved = UserDefaults.standard.string(forKey: "PuraMacModel") ?? OpenRouterClient.shared.defaultModel
        modelCombo.selectItem(withObjectValue: saved)
        if modelCombo.indexOfItem(withObjectValue: saved) < 0 {
            modelCombo.stringValue = saved
        }
        modelCombo.isEditable = true
        modelCombo.completes = true
        modelCombo.translatesAutoresizingMaskIntoConstraints = false
        modelCombo.target = self
        modelCombo.action = #selector(modelChanged(_:))

        let modelRow = NSStackView(views: [NSTextField(labelWithString: "Model"), modelCombo])
        modelRow.orientation = .horizontal
        modelRow.spacing = 8
        modelRow.translatesAutoresizingMaskIntoConstraints = false

        transcript.isRichText = false
        transcript.font = NSFont.systemFont(ofSize: 12)
        transcript.isEditable = false
        transcript.autoresizingMask = [.width]
        transcript.string = "PuraMac assistant ready. Nothing about your files leaves this Mac except category names and sizes you choose to send.\n\n"
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = transcript
        scroll.translatesAutoresizingMaskIntoConstraints = false

        input.font = NSFont.systemFont(ofSize: 13)
        input.placeholderString = "Ask about disk, memory, cleanup, anything Mac..."
        input.target = self
        input.action = #selector(sendChat(_:))
        input.translatesAutoresizingMaskIntoConstraints = false

        sendButton.bezelStyle = .rounded
        sendButton.target = self
        sendButton.action = #selector(sendChat(_:))

        analyzeButton.bezelStyle = .rounded
        analyzeButton.target = self
        analyzeButton.action = #selector(analyzeScan(_:))
        analyzeButton.toolTip = "Sends only category names and sizes from your last Smart Clean scan"

        let inputRow = NSStackView(views: [input, sendButton])
        inputRow.orientation = .horizontal
        inputRow.spacing = 8
        inputRow.translatesAutoresizingMaskIntoConstraints = false

        let column = NSStackView(views: [header, modelRow, analyzeButton, scroll, inputRow, statusLabel])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 10
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        column.setCustomSpacing(12, after: analyzeButton)

        for view in [modelRow, scroll, inputRow] {
            view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        }
        input.widthAnchor.constraint(greaterThanOrEqualToConstant: 420).isActive = true

        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            column.topAnchor.constraint(equalTo: topAnchor, constant: 22),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 300)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func modelChanged(_ sender: NSComboBox) {
        UserDefaults.standard.set(sender.stringValue, forKey: "PuraMacModel")
    }

    private func currentModel() -> String {
        let value = modelCombo.stringValue.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? OpenRouterClient.shared.defaultModel : value
    }

    private func appendTranscript(_ text: String) {
        let attr = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.textColor
        ])
        transcript.textStorage?.append(attr)
        transcript.scrollRangeToVisible(NSRange(location: (transcript.string as NSString).length, length: 0))
    }

    private func setBusy(_ value: Bool, message: String) {
        busy = value
        sendButton.isEnabled = !value
        analyzeButton.isEnabled = !value
        input.isEnabled = !value
        statusLabel.stringValue = message
    }

    private func systemContext() -> String {
        let disk = SystemStats.diskInfo()
        let memory = SystemStats.memoryInfo()
        var lines: [String] = [
            "You are PuraMac's assistant, a macOS cleanup advisor. Be concise and practical. Use plain text, no markdown headings.",
            "System context:",
            "Disk: " + (disk.valid ? SystemStats.formatBytes(disk.freeBytes) + " free of " + SystemStats.formatBytes(disk.totalBytes) : "unknown"),
            "Memory: " + String(format: "%.0f%%", memory.usedPercent * 100) + " used, pressure " + memory.pressureLabel,
            "Uptime: " + SystemStats.uptimeText(),
            "OS: " + SystemStats.osVersionText()
        ]
        if let scanSummary = UserDefaults.standard.string(forKey: "PuraMacLastScanSummary") {
            lines.append("Latest Smart Clean scan (category names and sizes only): " + scanSummary)
        }
        return lines.joined(separator: "\n")
    }

    @objc func sendChat(_ sender: Any) {
        guard !busy else { return }
        let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input.stringValue = ""
        appendTranscript("You: " + text + "\n\n")
        setBusy(true, message: "Thinking...")
        let model = currentModel()
        OpenRouterClient.shared.complete(model: model, system: systemContext(), history: history, user: text) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setBusy(false, message: "Ready")
                switch result {
                case .failure(let error):
                    if case .message(let text) = error {
                        self.appendTranscript("PuraMac: error, " + text + "\n\n")
                    }
                case .success(let content):
                    self.history.append(ChatMessage(role: "user", content: text))
                    self.history.append(ChatMessage(role: "assistant", content: content))
                    self.appendTranscript("PuraMac: " + content + "\n\n")
                }
            }
        }
    }

    @objc private func analyzeScan(_ sender: Any) {
        guard !busy else { return }
        guard let summary = UserDefaults.standard.string(forKey: "PuraMacLastScanSummary"), !summary.isEmpty else {
            appendTranscript("PuraMac: run a Smart Clean scan first, then I can analyze it.\n\n")
            return
        }
        let prompt = "Here is an anonymized summary of cleanup categories on this Mac: " + summary + ". Give a short cleanup plan: what is safe to remove now, what to check first, and any risks. Keep it under 250 words."
        appendTranscript("You: Analyze my scan (" + summary + ")\n\n")
        setBusy(true, message: "Analyzing scan...")
        let model = currentModel()
        let system = "You are PuraMac's cleanup advisor. You receive only category names and sizes, never file paths or personal data. Give concrete, risk-aware cleanup advice in plain text, under 250 words."
        OpenRouterClient.shared.complete(model: model, system: system, user: prompt) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setBusy(false, message: "Ready")
                switch result {
                case .failure(let error):
                    if case .message(let text) = error {
                        self.appendTranscript("PuraMac: error, " + text + "\n\n")
                    }
                case .success(let content):
                    self.appendTranscript("PuraMac: " + content + "\n\n")
                }
            }
        }
    }

    static func anonymizedSummary(from groups: [CleanGroup]) -> String {
        var parts: [String] = []
        for group in groups where group.fileCount > 0 {
            parts.append(group.title + ": " + SystemStats.formatBytes(group.totalBytes) + " across " + String(group.fileCount) + " files")
        }
        return parts.joined(separator: ", ")
    }
}
