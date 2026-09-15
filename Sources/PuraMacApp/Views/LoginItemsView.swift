import SwiftUI
import PuraMacCore

struct LoginItemsView: View {
    @Environment(AppModel.self) private var model
    @State private var showReview = false

    private var loginItems: LoginItemsModel { model.loginItems }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaneHeader(
                title: "Login Items",
                subtitle: "Helpers that start automatically. Disabling one moves its job file to the Trash."
            ) {
                HStack(spacing: 8) {
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button {
                        loginItems.reload()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }

            if let error = loginItems.errorMessage {
                MessageBanner(kind: .error, text: error) { loginItems.errorMessage = nil }
            }
            if let status = loginItems.statusMessage {
                MessageBanner(kind: .info, text: status) { loginItems.statusMessage = nil }
            }

            if loginItems.items.isEmpty {
                EmptyStateView(
                    symbol: "power",
                    title: "No third-party login items",
                    message: "Nothing outside macOS is set to launch at login from your user folder.",
                    actionTitle: "Check again",
                    action: { loginItems.reload() })
            } else {
                Table(loginItems.items) {
                    TableColumn("") { item in
                        Toggle("", isOn: Binding(
                            get: { loginItems.selected.contains(item.plistPath) },
                            set: { _ in loginItems.toggle(item.plistPath) }))
                        .labelsHidden()
                        .accessibilityLabel("Select \(item.displayName)")
                    }
                    .width(28)

                    TableColumn("Item") { item in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.displayName).lineLimit(1)
                            Text(item.label).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }

                    TableColumn("Starts at login") { item in
                        Text(item.runAtLoad ? "Yes" : "On demand")
                            .foregroundStyle(item.runAtLoad ? .primary : .secondary)
                    }
                    .width(min: 100, ideal: 120)

                    TableColumn("") { item in
                        RevealButton(path: item.program ?? item.plistPath)
                    }
                    .width(34)
                }

                HStack {
                    Text("\(Format.count(loginItems.selected.count, singular: "item")) selected")
                        .font(.headline)
                    Spacer()
                    Button {
                        showReview = true
                    } label: {
                        Label("Disable Selected", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(loginItems.selected.isEmpty)
                }
            }
        }
        .paneLayout()
        .onAppear { if loginItems.items.isEmpty { loginItems.reload() } }
        .sheet(isPresented: $showReview) {
            let chosen = loginItems.items.filter { loginItems.selected.contains($0.plistPath) }
            ReviewSheet(
                title: "Disable login items",
                items: chosen.map { ReviewItem(path: $0.plistPath, bytes: 0, kind: "Login item") },
                totalBytes: 0,
                confirmTitle: "Move to Trash",
                note: "The job definition goes to the Trash. Put it back to re-enable the item, then log in again.",
                onConfirm: { loginItems.disableSelected() })
        }
    }
}
