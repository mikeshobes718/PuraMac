import SwiftUI
import PuraMacCore

struct SmartCleanView: View {
    @Environment(AppModel.self) private var model
    @State private var showReview = false

    private var clean: SmartCleanModel { model.smartClean }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaneHeader(
                title: "Smart Clean",
                subtitle: "Caches, logs and build leftovers that rebuild themselves."
            ) {
                HStack(spacing: 8) {
                    if !clean.groups.isEmpty {
                        Button("Safe only") { clean.selectAllSafe() }
                        Button("None") { clean.deselectAll() }
                    }
                    Button {
                        clean.startScan()
                    } label: {
                        Label(clean.groups.isEmpty ? "Scan" : "Rescan", systemImage: "arrow.clockwise")
                    }
                    .disabled(clean.isBusy)
                    .keyboardShortcut("r", modifiers: .command)
                }
            }

            if clean.isBusy {
                ProgressBanner(text: clean.progressText, fraction: clean.progressFraction) {
                    clean.cancel()
                }
            }
            if let error = clean.errorMessage {
                MessageBanner(kind: .error, text: error) { clean.errorMessage = nil }
            }
            if let status = clean.statusMessage, !clean.isBusy {
                MessageBanner(kind: .info, text: status) { clean.statusMessage = nil }
            }

            if clean.groups.isEmpty && !clean.isBusy {
                EmptyStateView(
                    symbol: "sparkles",
                    title: "Nothing scanned yet",
                    message: "PuraMac looks through caches, logs, build folders and old downloads. It shows you exactly what it found and removes nothing until you say so.",
                    actionTitle: "Scan this Mac",
                    action: { clean.startScan() })
            } else {
                categoryList
                footer
            }
        }
        .paneLayout()
        .sheet(isPresented: $showReview) { reviewSheet }
        .onChange(of: clean.reclaimableBytes) {
            model.assistant.lastScanSummary = clean.report?.anonymizedSummary()
        }
    }

    private var categoryList: some View {
        List {
            ForEach(clean.groups) { group in
                CategoryRow(
                    group: group,
                    isExpanded: clean.expanded.contains(group.id),
                    onToggleSelect: { clean.toggle(group.id) },
                    onToggleExpand: { clean.setExpanded(group.id, !clean.expanded.contains(group.id)) })
            }
        }
        .listStyle(.inset)
        .alternatingRowBackgrounds()
    }

    private var footer: some View {
        Card(padding: 15) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(clean.hasSelection ? "Selected" : "Reclaimable")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(Format.bytes(clean.hasSelection ? clean.selectedBytes : clean.reclaimableBytes))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.brand)
                        .contentTransition(.numericText())
                    Text("Everything except emptying the Trash goes to the Trash first, so you can put it back.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 16)
                Button {
                    showReview = true
                } label: {
                    Label("Review and Clean", systemImage: "trash")
                }
                .buttonStyle(GlowButtonStyle())
                .disabled(!clean.hasSelection || clean.isBusy)
                .opacity(clean.hasSelection && !clean.isBusy ? 1 : 0.5)
            }
        }
    }

    private var reviewSheet: some View {
        let selected = clean.selectedGroups
        let items = selected.flatMap { group in
            group.removablePaths.map { path in
                ReviewItem(
                    path: path,
                    bytes: group.size(of: path),
                    kind: group.category.title)
            }
        }
        let permanent = selected.contains { $0.category.removal == .permanentDelete }
        return ReviewSheet(
            title: "Review cleanup",
            items: items,
            totalBytes: clean.selectedBytes,
            confirmTitle: permanent ? "Remove Permanently" : "Move to Trash",
            note: permanent
                ? "This selection includes emptying the Trash, which cannot be undone. Everything else goes to the Trash."
                : "Everything here goes to the Trash, so you can put it back if you change your mind.",
            isPermanent: permanent,
            onConfirm: { clean.performClean() })
    }
}

private struct CategoryRow: View {
    let group: CleanGroup
    let isExpanded: Bool
    let onToggleSelect: () -> Void
    let onToggleExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(get: { group.isSelected }, set: { _ in onToggleSelect() }))
                    .labelsHidden()
                    .disabled(!group.isActionable)
                    .accessibilityLabel("Select \(group.category.title)")

                if !group.breakdown.isEmpty {
                    Button(action: onToggleExpand) {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .foregroundStyle(.secondary)
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? "Collapse \(group.category.title)" : "Expand \(group.category.title)")
                } else {
                    Color.clear.frame(width: 12)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(group.category.title).font(.body.weight(.medium))
                        SafetyBadge(safety: group.category.safety)
                        if group.category.removal == .measureOnly {
                            Text("Shown only")
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15), in: .capsule)
                        }
                    }
                    Text(group.unavailableReason ?? group.category.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(group.unavailableReason == nil ? Format.bytes(group.bytes) : "—")
                        .font(.body.monospacedDigit())
                    if group.itemCount > 0 {
                        Text(Format.count(group.itemCount, singular: "item"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(group.breakdown) { entry in
                        HStack(spacing: 8) {
                            Text(entry.name)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(Format.bytes(entry.bytes))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            RevealButton(path: entry.path)
                        }
                    }
                    if group.removablePaths.count > group.breakdown.count {
                        Text("and \(group.removablePaths.count - group.breakdown.count) more")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.leading, 44)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 5)
        .opacity(group.unavailableReason == nil ? 1 : 0.55)
    }
}
