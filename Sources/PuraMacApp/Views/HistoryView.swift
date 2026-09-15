import SwiftUI
import PuraMacCore

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    private var history: HistoryModel { model.history }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaneHeader(
                title: "History",
                subtitle: "Everything PuraMac has removed, and what can still be put back."
            ) {
                Button("Clear History") { Task { await history.clear() } }
                    .disabled(history.records.isEmpty)
            }

            if let message = history.message {
                MessageBanner(kind: .info, text: message) { history.message = nil }
            }

            if history.records.isEmpty {
                EmptyStateView(
                    symbol: "clock.arrow.circlepath",
                    title: "Nothing removed yet",
                    message: "Once PuraMac cleans something, it is listed here with the option to undo it while the files are still in the Trash.")
            } else {
                List {
                    ForEach(history.records) { record in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.summary).font(.body.weight(.medium)).lineLimit(1)
                                Text("\(record.date.formatted(date: .abbreviated, time: .shortened)) · \(Format.count(record.items.count, singular: "item"))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Format.bytes(record.freedBytes))
                                .font(.body.monospacedDigit())
                            Button("Put Back") {
                                Task { await history.undo(record) }
                            }
                            .disabled(!record.canUndo)
                            .help(record.canUndo
                                  ? "Move these items out of the Trash and back where they were"
                                  : "This cleanup was permanent and cannot be undone")
                        }
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.inset)
                .alternatingRowBackgrounds()
            }
        }
        .paneLayout()
        .task { await history.reload() }
    }
}
