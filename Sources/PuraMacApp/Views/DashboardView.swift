import SwiftUI
import PuraMacCore

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    private var dashboard: DashboardModel { model.dashboard }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PaneHeader(
                    title: "This Mac",
                    subtitle: dashboard.lastUpdated.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" }
                        ?? "Reading system information…"
                ) {
                    Button {
                        Task { await dashboard.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(dashboard.isRefreshing)
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                }

                hero

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                    memoryTile
                    cpuTile
                    batteryTile
                    systemTile
                    swapTile
                    thermalTile
                }

                quickActions
            }
            .paneLayout()
        }
        .task { await dashboard.refresh() }
    }

    // MARK: Hero

    private var hero: some View {
        let disk = dashboard.disk
        return Card(padding: 22) {
            HStack(alignment: .center, spacing: 26) {
                RingGauge(
                    progress: disk.isValid ? disk.usedFraction : 0,
                    lineWidth: 18,
                    tint: Palette.usage(disk.usedFraction)
                ) {
                    VStack(spacing: 1) {
                        Text(disk.isValid ? Format.percent(disk.usedFraction) : "—")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("used")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 148, height: 148)

                VStack(alignment: .leading, spacing: 8) {
                    Text(disk.isValid ? disk.name : "Storage")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text(disk.isValid ? Format.bytes(disk.freeBytes) : "Unknown")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.brand)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text(disk.isValid
                         ? "free of \(Format.bytes(disk.totalBytes)) · \(Format.bytes(disk.usedBytes)) in use"
                         : "Could not read the boot volume")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Image(systemName: adviceSymbol)
                            .foregroundStyle(Palette.usage(disk.usedFraction))
                        Text(advice)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)

                    Button {
                        model.pane = .smartClean
                        model.smartClean.startScan()
                    } label: {
                        Label("Scan this Mac", systemImage: "sparkles")
                    }
                    .buttonStyle(GlowButtonStyle())
                    .padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var advice: String {
        let disk = dashboard.disk
        if !disk.isValid { return "Storage information is unavailable." }
        if disk.freeFraction < 0.10 { return "Running low — a Smart Clean scan is the quickest place to start." }
        if disk.freeFraction < 0.20 { return "Getting tight. Large files and duplicates are usually the biggest wins." }
        return "Plenty of room. A scan every few weeks keeps caches from creeping up."
    }

    private var adviceSymbol: String {
        let free = dashboard.disk.freeFraction
        if free < 0.10 { return "exclamationmark.triangle.fill" }
        if free < 0.20 { return "info.circle.fill" }
        return "checkmark.seal.fill"
    }

    // MARK: Tiles

    private var memoryTile: some View {
        let memory = dashboard.memory
        return StatTile(
            title: "Memory",
            value: Format.percent(memory.usedFraction),
            detail: "\(Format.bytes(memory.usedBytes)) of \(Format.bytes(memory.totalBytes)) · pressure \(memory.pressure.label)",
            symbol: "memorychip",
            tint: memory.pressure == .normal ? Palette.safety(.safe)
                : (memory.pressure == .warning ? Palette.safety(.review) : Palette.safety(.caution)),
            progress: memory.usedFraction)
    }

    private var cpuTile: some View {
        let cpu = dashboard.cpu
        return StatTile(
            title: "Processor",
            value: Format.percent(cpu.usageFraction),
            detail: "\(cpu.coreCount) cores · \(Format.percent(cpu.userFraction)) user, \(Format.percent(cpu.systemFraction)) system",
            symbol: "cpu",
            tint: Palette.usage(cpu.usageFraction),
            progress: cpu.usageFraction)
    }

    private var batteryTile: some View {
        let battery = dashboard.battery
        return StatTile(
            title: "Battery",
            value: battery.isPresent ? "\(battery.percent)%" : "—",
            detail: battery.isPresent
                ? battery.summary + (battery.healthLabel.map { " · \($0.lowercased())" } ?? "")
                : "This Mac runs on mains power",
            symbol: battery.isCharging ? "battery.100.bolt" : "battery.75",
            tint: battery.percent < 20 && !battery.isOnAC ? Palette.safety(.caution) : Palette.safety(.safe),
            progress: battery.isPresent ? Double(battery.percent) / 100 : nil)
    }

    private var systemTile: some View {
        StatTile(
            title: "System",
            value: SystemStats.osVersion(),
            detail: "\(SystemStats.modelIdentifier()) · up \(SystemStats.uptime())",
            symbol: "desktopcomputer",
            tint: Palette.brandMid)
    }

    private var swapTile: some View {
        let memory = dashboard.memory
        return StatTile(
            title: "Swap",
            value: memory.swapUsedBytes > 0 ? Format.bytes(memory.swapUsedBytes) : "None",
            detail: memory.swapUsedBytes > 0
                ? "macOS is paging to disk — closing heavy apps frees real memory"
                : "Nothing paged to disk right now",
            symbol: "arrow.left.arrow.right.circle",
            tint: memory.swapUsedBytes > 0 ? Palette.safety(.review) : Palette.safety(.safe))
    }

    private var thermalTile: some View {
        let state = dashboard.cpu.thermalState
        return StatTile(
            title: "Thermals",
            value: state,
            detail: state == "Nominal"
                ? "Running cool, no throttling"
                : "macOS is managing heat — performance may be reduced",
            symbol: "thermometer.medium",
            tint: state == "Nominal" ? Palette.safety(.safe) : Palette.safety(.review))
    }

    // MARK: Quick actions

    private var quickActions: some View {
        Card {
            VStack(alignment: .leading, spacing: 13) {
                Text("Reclaim space").font(.headline)
                HStack(spacing: 11) {
                    action("Smart Clean", "sparkles", "Caches, logs and build leftovers", Palette.brandStart) {
                        model.pane = .smartClean
                        model.smartClean.startScan()
                    }
                    action("Large Files", "doc.badge.ellipsis", "Anything over \(model.largeFiles.minimumMB) MB", Palette.brandMid) {
                        model.pane = .largeFiles
                        model.largeFiles.startScan()
                    }
                    action("Duplicates", "doc.on.doc", "Identical copies you only need once", Palette.brandEnd) {
                        model.pane = .duplicates
                        model.duplicates.startScan()
                    }
                    action("Uninstall", "trash.square", "Apps plus the files they leave behind", Palette.safety(.caution)) {
                        model.pane = .uninstaller
                        model.uninstaller.loadApps()
                    }
                }
            }
        }
    }

    private func action(_ title: String, _ symbol: String, _ subtitle: String,
                        _ tint: Color, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Palette.ramp(tint), in: .rect(cornerRadius: 9))
                    .shadow(color: tint.opacity(0.45), radius: 6, y: 2)
                Text(title).font(.callout.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}
