import SwiftUI
import PuraMacCore

struct AssistantView: View {
    @Environment(AppModel.self) private var model

    private var assistant: AssistantModel { model.assistant }

    var body: some View {
        @Bindable var assistant = model.assistant

        VStack(alignment: .leading, spacing: 12) {
            PaneHeader(
                title: "Assistant",
                subtitle: "Ask about this Mac. Only category names and sizes are ever sent — never file paths."
            ) {
                HStack(spacing: 8) {
                    Picker("Model", selection: $assistant.model) {
                        ForEach(assistant.models) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240)

                    Button("Clear") { assistant.clear() }
                        .disabled(assistant.messages.isEmpty)
                }
            }

            if !assistant.hasKey {
                MessageBanner(
                    kind: .error,
                    text: "No OpenRouter API key yet. Add one in Settings (⌘,) to use the assistant.")
            }
            if let error = assistant.errorMessage {
                MessageBanner(kind: .error, text: error) { assistant.errorMessage = nil }
            }

            transcript

            HStack(spacing: 8) {
                Button {
                    assistant.analyzeLastScan()
                } label: {
                    Label("Analyse last scan", systemImage: "wand.and.stars")
                }
                .disabled(assistant.isStreaming || assistant.lastScanSummary == nil)
                .help(assistant.lastScanSummary == nil
                      ? "Run a Smart Clean scan first"
                      : "Sends only category names and sizes")

                TextField("Ask about disk, memory, cleanup…", text: $assistant.draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { assistant.send() }
                    .disabled(assistant.isStreaming || !assistant.hasKey)

                if assistant.isStreaming {
                    Button("Stop", role: .cancel) { assistant.stop() }
                } else {
                    Button("Send") { assistant.send() }
                        .buttonStyle(.borderedProminent)
                        .disabled(assistant.draft.trimmingCharacters(in: .whitespaces).isEmpty || !assistant.hasKey)
                }
            }
        }
        .paneLayout()
        .task {
            await assistant.loadModels()
            assistant.refreshKeyState()
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if assistant.messages.isEmpty {
                        EmptyStateView(
                            symbol: "bubble.left.and.text.bubble.right",
                            title: "Ask anything about this Mac",
                            message: "The assistant sees your disk, memory and OS version, plus category totals from your last scan. It never sees a file name or path.")
                    }
                    ForEach(assistant.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(.vertical, 6)
            }
            .onChange(of: assistant.messages.last?.text) {
                if let last = assistant.messages.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.cardBackground, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.hairline, lineWidth: 0.5))
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(message.role == .user ? "You" : "PuraMac")
                .font(.caption.weight(.semibold))
                .foregroundStyle(message.role == .user ? Color.accentColor : .secondary)
            if message.text.isEmpty {
                ProgressView().controlSize(.small)
            } else {
                Text(message.text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            message.role == .user ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.04),
            in: .rect(cornerRadius: 10))
        .padding(.horizontal, 12)
    }
}
