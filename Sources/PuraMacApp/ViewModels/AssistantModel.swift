import SwiftUI
import Observation
import PuraMacCore

@Observable
@MainActor
final class AssistantModel {
    var messages: [ChatMessage] = []
    var draft = ""
    var isStreaming = false
    var errorMessage: String?
    var models: [AIModel] = OpenRouterClient.fallbackModels
    var hasKey = Keychain.hasValue(for: Credentials.openRouterAccount)

    /// Set by Smart Clean after a scan. Category names and sizes only — this is
    /// the only scan data that ever leaves the Mac, and only when asked for.
    var lastScanSummary: String?

    private var streamTask: Task<Void, Never>?

    var model: String {
        get { Preferences.shared.aiModel }
        set { Preferences.shared.aiModel = newValue }
    }

    func refreshKeyState() {
        hasKey = Keychain.hasValue(for: Credentials.openRouterAccount)
    }

    func loadModels() async {
        models = await OpenRouterClient.shared.models()
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        draft = ""
        ask(text)
    }

    func analyzeLastScan() {
        guard let summary = lastScanSummary, !summary.isEmpty else {
            errorMessage = "Run a Smart Clean scan first, then I can look at what it found."
            return
        }
        ask("Here is an anonymised summary of cleanup categories on this Mac: \(summary). "
            + "Give me a short plan: what is safe to remove now, what deserves a second look, and any risks. Under 250 words.")
    }

    private func ask(_ text: String) {
        errorMessage = nil
        let history = messages
        messages.append(ChatMessage(role: .user, text: text))
        messages.append(ChatMessage(role: .assistant, text: ""))
        isStreaming = true

        let systemPrompt = buildSystemPrompt()
        let chosenModel = model

        streamTask = Task { [weak self] in
            do {
                let stream = OpenRouterClient.shared.stream(
                    model: chosenModel, system: systemPrompt, history: history, user: text)
                for try await fragment in stream {
                    guard let self, !Task.isCancelled else { break }
                    self.messages[self.messages.count - 1].text += fragment
                }
            } catch {
                guard let self else { return }
                self.errorMessage = error.localizedDescription
                if self.messages.last?.text.isEmpty == true {
                    self.messages.removeLast()
                }
            }
            self?.isStreaming = false
            self?.streamTask = nil
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    func clear() {
        stop()
        messages = []
        errorMessage = nil
    }

    private func buildSystemPrompt() -> String {
        let disk = SystemStats.bootDisk()
        let memory = SystemStats.memory()
        var lines = [
            "You are PuraMac's assistant, a practical macOS cleanup advisor.",
            "Answer in plain prose. No markdown headings, no bullet symbols unless genuinely listing steps.",
            "Be concrete and honest about risk. Never suggest deleting anything outside the user's home folder.",
            "",
            "This Mac right now:",
            "Model: \(SystemStats.modelIdentifier())",
            "OS: \(SystemStats.osVersion())",
            "Disk: \(Format.bytes(disk.freeBytes)) free of \(Format.bytes(disk.totalBytes))",
            "Memory: \(Format.percent(memory.usedFraction)) used, pressure \(memory.pressure.label)",
            "Uptime: \(SystemStats.uptime())"
        ]
        if let lastScanSummary {
            lines.append("Latest scan (category names and sizes only): \(lastScanSummary)")
        }
        return lines.joined(separator: "\n")
    }
}
