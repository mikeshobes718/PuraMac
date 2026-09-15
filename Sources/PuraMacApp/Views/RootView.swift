import SwiftUI
import PuraMacCore

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            List(selection: $model.pane) {
                ForEach(sections, id: \.name) { section in
                    Section(section.name) {
                        ForEach(section.panes) { pane in
                            SidebarRow(pane: pane, isSelected: model.pane == pane)
                                .tag(pane)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 216, max: 250)
            .safeAreaInset(edge: .bottom) { diskFooter }
        } detail: {
            detail
                .navigationTitle(model.pane.title)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        PaneTitleLabel(pane: model.pane)
                    }
                }
        }
        .forceWindowAppearance(model.preferences.appearance.colorScheme)
    }

    private var sections: [(name: String, panes: [Pane])] {
        let order = ["Overview", "Reclaim space", "Manage"]
        return order.map { name in
            (name, Pane.allCases.filter { $0.section == name })
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.pane {
        case .dashboard: DashboardView()
        case .smartClean: SmartCleanView()
        case .largeFiles: LargeFilesView()
        case .duplicates: DuplicatesView()
        case .uninstaller: UninstallerView()
        case .loginItems: LoginItemsView()
        case .assistant: AssistantView()
        case .history: HistoryView()
        }
    }

    private var diskFooter: some View {
        let disk = model.dashboard.disk
        return VStack(alignment: .leading, spacing: 6) {
            Divider()
            if disk.isValid {
                HStack(spacing: 6) {
                    Text(disk.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(Format.percent(disk.usedFraction))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.10))
                        Capsule()
                            .fill(Palette.ramp(Palette.usage(disk.usedFraction)))
                            .frame(width: max(4, geo.size.width * min(1, disk.usedFraction)))
                    }
                }
                .frame(height: 5)
                Text("\(Format.bytes(disk.freeBytes)) free")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 13)
        .padding(.bottom, 11)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(disk.isValid
            ? "\(disk.name), \(Format.bytes(disk.freeBytes)) free of \(Format.bytes(disk.totalBytes))"
            : "Disk usage unavailable")
    }
}

/// The window titlebar's centre content. The default `.navigationTitle` text
/// alone reads as bare, unstyled OS chrome next to the rest of the app's
/// gradient-and-glyph design language, so the titlebar gets the same tinted
/// icon chip treatment as a sidebar row.
private struct PaneTitleLabel: View {
    let pane: Pane

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: pane.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Palette.brand, in: .rect(cornerRadius: 6))
            Text(pane.title)
                .font(.system(size: 13, weight: .semibold))
        }
    }
}

/// Sidebar row with a tinted glyph chip, so the navigation reads as a set of
/// tools rather than a plain text list.
private struct SidebarRow: View {
    let pane: Pane
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: pane.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(Palette.brandMid))
                .frame(width: 24, height: 24)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7).fill(Palette.brand)
                            .shadow(color: Palette.brandMid.opacity(0.5), radius: 5, y: 2)
                    } else {
                        RoundedRectangle(cornerRadius: 7).fill(Palette.brandMid.opacity(0.12))
                    }
                }
            Text(pane.title)
                .font(.body.weight(isSelected ? .semibold : .regular))
        }
        .padding(.vertical, 2)
        .animation(.spring(duration: 0.25), value: isSelected)
    }
}
