import SwiftUI
import PuraMacCore

struct UninstallerView: View {
    @Environment(AppModel.self) private var model
    @State private var showReview = false

    private var uninstaller: UninstallerModel { model.uninstaller }

    var body: some View {
        @Bindable var uninstaller = model.uninstaller

        VStack(alignment: .leading, spacing: 14) {
            PaneHeader(
                title: "Uninstaller",
                subtitle: "Removes an app together with the caches, preferences and containers it leaves behind."
            ) {
                Button {
                    uninstaller.loadApps()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(uninstaller.isBusy)
            }

            if uninstaller.isBusy {
                ProgressBanner(text: uninstaller.progressText, fraction: uninstaller.progressFraction) {
                    uninstaller.cancel()
                }
            }
            if let error = uninstaller.errorMessage {
                MessageBanner(kind: .error, text: error) { uninstaller.errorMessage = nil }
            }
            if let status = uninstaller.statusMessage, !uninstaller.isBusy {
                MessageBanner(kind: .info, text: status) { uninstaller.statusMessage = nil }
            }

            if uninstaller.apps.isEmpty && !uninstaller.isBusy {
                EmptyStateView(
                    symbol: "trash.square",
                    title: "No applications listed",
                    message: "PuraMac lists apps in your Applications folders. Apps built into macOS are never shown, because removing them is not something this app should do.",
                    actionTitle: "List applications",
                    action: { uninstaller.loadApps() })
            } else {
                HSplitView {
                    appList
                        .frame(minWidth: 260, idealWidth: 320)
                    detail
                        .frame(minWidth: 340)
                }
            }
        }
        .paneLayout()
        .searchable(text: $uninstaller.searchText, prompt: "Filter applications")
        .sheet(isPresented: $showReview) {
            if let plan = uninstaller.plan {
                ReviewSheet(
                    title: "Uninstall \(plan.app.name)",
                    items: [ReviewItem(path: plan.app.bundlePath, bytes: plan.app.bytes, kind: "Application")]
                        + plan.leftovers.map { ReviewItem(path: $0.path, bytes: $0.bytes, kind: $0.kind) },
                    totalBytes: plan.totalBytes,
                    confirmTitle: "Move to Trash",
                    note: "The app and everything listed here go to the Trash together, so the whole uninstall can be undone.",
                    onConfirm: { uninstaller.uninstall() })
            }
        }
    }

    private var appList: some View {
        List(uninstaller.filteredApps, selection: Binding(
            get: { uninstaller.selectedApp?.bundlePath },
            set: { path in
                if let app = uninstaller.apps.first(where: { $0.bundlePath == path }) {
                    uninstaller.select(app)
                }
            })
        ) { app in
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath))
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).lineLimit(1)
                    Text(app.version.map { "Version \($0)" } ?? "Unknown version")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Format.bytes(app.bytes))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .tag(app.bundlePath)
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let app = uninstaller.selectedApp {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Card {
                        HStack(spacing: 12) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath))
                                .resizable().frame(width: 52, height: 52)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.name).font(.title3.weight(.semibold))
                                Text(app.bundleID ?? "No bundle identifier")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Text("\(Format.bytes(app.bytes))"
                                     + (app.lastOpened.map { " · last opened \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }

                    if let plan = uninstaller.plan {
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Files left behind").font(.headline)
                                    Spacer()
                                    Text(Format.bytes(plan.leftoverBytes))
                                        .foregroundStyle(.secondary)
                                }
                                if plan.leftovers.isEmpty {
                                    Text("None found. This app keeps to itself.")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(plan.leftovers) { leftover in
                                        HStack(spacing: 8) {
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(leftover.kind).font(.caption.weight(.medium))
                                                Text(Format.abbreviate(leftover.path))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                            }
                                            Spacer()
                                            Text(Format.bytes(leftover.bytes))
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                            RevealButton(path: leftover.path)
                                        }
                                    }
                                }
                            }
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Total \(Format.bytes(plan.totalBytes))").font(.headline)
                                Text("App bundle plus \(Format.count(plan.leftovers.count, singular: "leftover"))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                showReview = true
                            } label: {
                                Label("Uninstall", systemImage: "trash")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(uninstaller.isBusy)
                        }
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Looking for leftover files…").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(4)
            }
        } else {
            EmptyStateView(
                symbol: "hand.point.left",
                title: "Select an application",
                message: "Pick an app on the left and PuraMac will show you everything that would go with it.")
        }
    }
}
