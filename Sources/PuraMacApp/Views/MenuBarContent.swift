import SwiftUI
import PuraMacCore

/// A compact read-out plus the two actions worth reaching without opening the
/// window. Anything destructive still routes through the main app.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let disk = model.dashboard.disk
            let memory = model.dashboard.memory

            if disk.isValid {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(disk.name).font(.callout.weight(.medium))
                        Spacer()
                        Text("\(Format.bytes(disk.freeBytes)) free")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: disk.usedFraction)
                        .tint(Palette.usage(disk.usedFraction))
                }
            }

            HStack {
                Label("Memory", systemImage: "memorychip").font(.caption)
                Spacer()
                Text("\(Format.percent(memory.usedFraction)) · \(memory.pressure.label)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
                model.pane = .smartClean
                model.smartClean.startScan()
            } label: {
                Label("Run Smart Clean Scan", systemImage: "sparkles")
            }
            .disabled(model.smartClean.isBusy)

            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open PuraMac", systemImage: "macwindow")
            }

            Divider()

            Button("Quit PuraMac") { NSApp.terminate(nil) }
        }
        .buttonStyle(.plain)
        .padding(14)
        .frame(width: 260)
        .task { await model.dashboard.refresh() }
        .forceWindowAppearance(model.preferences.appearance.colorScheme)
    }
}
