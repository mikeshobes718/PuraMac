import SwiftUI
import QuickLook
import PuraMacCore

struct LargeFilesView: View {
    @Environment(AppModel.self) private var model
    @State private var showReview = false
    @State private var quickLookURL: URL?

    private var files: LargeFilesModel { model.largeFiles }

    var body: some View {
        @Bindable var files = model.largeFiles

        VStack(alignment: .leading, spacing: 14) {
            PaneHeader(
                title: "Large Files",
                subtitle: "The biggest files in your personal folders. System and app data is left alone."
            ) {
                HStack(spacing: 10) {
                    Picker("Minimum", selection: $files.minimumMB) {
                        Text("50 MB").tag(50)
                        Text("100 MB").tag(100)
                        Text("500 MB").tag(500)
                        Text("1 GB").tag(1000)
                    }
                    .labelsHidden()
                    .frame(width: 96)

                    Picker("Age", selection: $files.olderThanDays) {
                        Text("Any age").tag(Int?.none)
                        Text("Over 90 days").tag(Int?.some(90))
                        Text("Over 1 year").tag(Int?.some(365))
                    }
                    .labelsHidden()
                    .frame(width: 128)

                    Button {
                        files.startScan()
                    } label: {
                        Label("Scan", systemImage: "magnifyingglass")
                    }
                    .disabled(files.isBusy)
                }
            }

            if files.isBusy {
                ProgressBanner(text: files.progressText, fraction: files.progressFraction) { files.cancel() }
            }
            if let error = files.errorMessage {
                MessageBanner(kind: .error, text: error) { files.errorMessage = nil }
            }
            if let status = files.statusMessage, !files.isBusy {
                MessageBanner(kind: .info, text: status) { files.statusMessage = nil }
            }

            if files.files.isEmpty && !files.isBusy {
                EmptyStateView(
                    symbol: "doc.badge.ellipsis",
                    title: "No large files listed",
                    message: "PuraMac searches Desktop, Documents, Downloads, Movies, Music and Pictures. Press space on any result for a Quick Look before deciding.",
                    actionTitle: "Search now",
                    action: { files.startScan() })
            } else {
                table
                footer
            }
        }
        .paneLayout()
        .quickLookPreview($quickLookURL)
        .sheet(isPresented: $showReview) {
            ReviewSheet(
                title: "Move files to the Trash",
                items: files.selectedEntries.map {
                    ReviewItem(path: $0.path, bytes: $0.bytes, kind: kind(for: $0.path))
                },
                totalBytes: files.selectedBytes,
                confirmTitle: "Move to Trash",
                note: "These go to the Trash, so you can put them back if you change your mind.",
                onConfirm: { files.moveSelectedToTrash() })
        }
    }

    private var table: some View {
        Table(files.files) {
            TableColumn("") { entry in
                Toggle("", isOn: Binding(
                    get: { files.selected.contains(entry.path) },
                    set: { _ in files.toggle(entry.path) }))
                .labelsHidden()
                .accessibilityLabel("Select \(entry.name)")
            }
            .width(28)

            TableColumn("File") { entry in
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name).lineLimit(1)
                    Text(Format.abbreviate((entry.path as NSString).deletingLastPathComponent))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            TableColumn("Kind") { entry in
                Text(kind(for: entry.path)).foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Size") { entry in
                Text(Format.bytes(entry.bytes)).monospacedDigit()
            }
            .width(min: 80, ideal: 90)

            TableColumn("Modified") { entry in
                Text(entry.modified.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 110)

            TableColumn("") { entry in
                HStack(spacing: 2) {
                    Button {
                        quickLookURL = URL(fileURLWithPath: entry.path)
                    } label: {
                        Image(systemName: "eye")
                    }
                    .buttonStyle(.borderless)
                    .help("Quick Look")
                    RevealButton(path: entry.path)
                }
            }
            .width(56)
        }
    }

    private var footer: some View {
        HStack {
            Text(files.selected.isEmpty
                 ? "\(Format.count(files.files.count, singular: "file")) · \(Format.bytes(files.totalBytes))"
                 : "\(Format.count(files.selected.count, singular: "file")) selected · \(Format.bytes(files.selectedBytes))")
                .font(.headline)
            Spacer()
            Button {
                showReview = true
            } label: {
                Label("Review and Move to Trash", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .disabled(files.selected.isEmpty || files.isBusy)
        }
    }

    private func kind(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "mov", "mp4", "m4v", "avi", "mkv", "wmv": return "Video"
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "tiff", "webp": return "Image"
        case "dmg", "iso", "sparsebundle": return "Disk image"
        case "zip", "xip", "gz", "tgz", "7z", "rar": return "Archive"
        case "pdf": return "PDF"
        case "mp3", "wav", "aiff", "m4a", "flac": return "Audio"
        default: return "File"
        }
    }
}
