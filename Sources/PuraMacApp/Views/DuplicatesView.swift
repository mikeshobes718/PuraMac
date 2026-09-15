import SwiftUI
import PuraMacCore

struct DuplicatesView: View {
    @Environment(AppModel.self) private var model
    @State private var showReview = false

    private var duplicates: DuplicatesModel { model.duplicates }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaneHeader(
                title: "Duplicates",
                subtitle: "Byte-for-byte identical files. One copy of each is always kept."
            ) {
                HStack(spacing: 8) {
                    if !duplicates.groups.isEmpty {
                        Button("Keep oldest") { duplicates.selectExtraCopies() }
                    }
                    Button {
                        duplicates.startScan()
                    } label: {
                        Label("Scan", systemImage: "magnifyingglass")
                    }
                    .disabled(duplicates.isBusy)
                }
            }

            if duplicates.isBusy {
                ProgressBanner(text: duplicates.progressText, fraction: duplicates.progressFraction) {
                    duplicates.cancel()
                }
            }
            if let error = duplicates.errorMessage {
                MessageBanner(kind: .error, text: error) { duplicates.errorMessage = nil }
            }
            if let status = duplicates.statusMessage, !duplicates.isBusy {
                MessageBanner(kind: .info, text: status) { duplicates.statusMessage = nil }
            }
            if duplicates.wouldEraseAnyGroup {
                MessageBanner(
                    kind: .error,
                    text: "One group has every copy selected. Leave at least one copy of each file, or PuraMac will not proceed.")
            }

            if duplicates.groups.isEmpty && !duplicates.isBusy {
                EmptyStateView(
                    symbol: "doc.on.doc",
                    title: "No duplicates found yet",
                    message: "PuraMac compares files by size, then by a partial fingerprint, then in full — so only genuinely identical files are ever listed.",
                    actionTitle: "Look for duplicates",
                    action: { duplicates.startScan() })
            } else {
                list
                footer
            }
        }
        .paneLayout()
        .sheet(isPresented: $showReview) {
            let entries = duplicates.groups.flatMap(\.files).filter { duplicates.selected.contains($0.path) }
            ReviewSheet(
                title: "Remove duplicate copies",
                items: entries.map { ReviewItem(path: $0.path, bytes: $0.bytes, kind: "Duplicate") },
                totalBytes: duplicates.selectedBytes,
                confirmTitle: "Move to Trash",
                note: "At least one copy of every file stays exactly where it is. The rest go to the Trash.",
                onConfirm: { duplicates.removeSelected() })
        }
    }

    private var list: some View {
        List {
            ForEach(duplicates.groups) { group in
                Section {
                    ForEach(group.files) { file in
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(
                                get: { duplicates.selected.contains(file.path) },
                                set: { _ in duplicates.toggle(file.path) }))
                            .labelsHidden()
                            .accessibilityLabel("Select copy at \(Format.abbreviate(file.path))")

                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.name).lineLimit(1)
                                Text(Format.abbreviate((file.path as NSString).deletingLastPathComponent))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            if group.suggestedKeep?.path == file.path {
                                Text("oldest")
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.green.opacity(0.16), in: .capsule)
                                    .foregroundStyle(.green)
                            }

                            Spacer()
                            Text(file.modified.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            RevealButton(path: file.path)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    HStack {
                        Text("\(Format.count(group.files.count, singular: "copy", plural: "copies")) · \(Format.bytes(group.fileSize)) each")
                        Spacer()
                        Text("saves \(Format.bytes(group.reclaimableBytes))")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        HStack {
            Text("\(Format.count(duplicates.selected.count, singular: "copy", plural: "copies")) selected · \(Format.bytes(duplicates.selectedBytes))")
                .font(.headline)
            Spacer()
            Button {
                showReview = true
            } label: {
                Label("Review and Move to Trash", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .disabled(duplicates.selected.isEmpty || duplicates.isBusy || duplicates.wouldEraseAnyGroup)
        }
    }
}
