import SwiftUI
import Observation
import PuraMacCore

enum Pane: String, CaseIterable, Identifiable, Hashable {
    case dashboard, smartClean, largeFiles, duplicates, uninstaller, loginItems, assistant, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .smartClean: return "Smart Clean"
        case .largeFiles: return "Large Files"
        case .duplicates: return "Duplicates"
        case .uninstaller: return "Uninstaller"
        case .loginItems: return "Login Items"
        case .assistant: return "Assistant"
        case .history: return "History"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .smartClean: return "sparkles"
        case .largeFiles: return "doc.badge.ellipsis"
        case .duplicates: return "doc.on.doc"
        case .uninstaller: return "trash.square"
        case .loginItems: return "power"
        case .assistant: return "bubble.left.and.text.bubble.right"
        case .history: return "clock.arrow.circlepath"
        }
    }

    var section: String {
        switch self {
        case .dashboard: return "Overview"
        case .smartClean, .largeFiles, .duplicates, .uninstaller: return "Reclaim space"
        case .loginItems, .assistant, .history: return "Manage"
        }
    }
}

@Observable
@MainActor
final class AppModel {
    var pane: Pane = .dashboard

    let preferences = Preferences.shared
    let dashboard = DashboardModel()
    let smartClean = SmartCleanModel()
    let largeFiles = LargeFilesModel()
    let duplicates = DuplicatesModel()
    let uninstaller = UninstallerModel()
    let loginItems = LoginItemsModel()
    let assistant = AssistantModel()
    let history = HistoryModel()

    private var diskMonitor: Task<Void, Never>?

    var showMenuBarExtra: Bool {
        get { preferences.showMenuBarExtra }
        set { preferences.showMenuBarExtra = newValue }
    }

    var isAnyScanRunning: Bool {
        smartClean.isBusy || largeFiles.isBusy || duplicates.isBusy || uninstaller.isBusy
    }

    init() {
        smartClean.onCleanFinished = { [weak self] record in
            Task { await self?.history.record(record) }
        }
        largeFiles.onCleanFinished = { [weak self] record in
            Task { await self?.history.record(record) }
        }
        duplicates.onCleanFinished = { [weak self] record in
            Task { await self?.history.record(record) }
        }
        uninstaller.onCleanFinished = { [weak self] record in
            Task { await self?.history.record(record) }
        }
        startDiskMonitor()
        Task { await dashboard.refresh() }
        Task { await history.reload() }
    }

    func cancelAllScans() {
        smartClean.cancel()
        largeFiles.cancel()
        duplicates.cancel()
        uninstaller.cancel()
    }

    /// Warns once a day at most, so a genuinely full disk is noticed without the
    /// app becoming something the user learns to ignore.
    private func startDiskMonitor() {
        diskMonitor = Task { [weak self] in
            while !Task.isCancelled {
                self?.checkDiskSpace()
                try? await Task.sleep(for: .seconds(1800))
            }
        }
    }

    private func checkDiskSpace() {
        guard preferences.autoDiskCheck else { return }
        let disk = SystemStats.bootDisk()
        guard disk.isValid, disk.freeFraction < preferences.lowDiskThreshold else { return }

        let store = UserDefaults.standard
        if let last = store.object(forKey: PreferenceKey.lastLowDiskNotice) as? Date,
           Date().timeIntervalSince(last) < 86_400 { return }
        store.set(Date(), forKey: PreferenceKey.lastLowDiskNotice)

        Notifier.post(
            title: "Low disk space",
            body: "Only \(Format.bytes(disk.freeBytes)) free (\(Format.percent(disk.freeFraction))). Run a Smart Clean scan to see what can go.",
            identifier: "puramac-lowdisk")
    }
}

@Observable
@MainActor
final class DashboardModel {
    var disk = DiskInfo()
    var memory = MemoryInfo()
    var cpu = CPUInfo()
    var battery = BatteryInfo()
    var isRefreshing = false
    var lastUpdated: Date?

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        disk = SystemStats.bootDisk()
        memory = SystemStats.memory()
        battery = SystemStats.battery()
        cpu = await SystemStats.cpu()
        lastUpdated = Date()
    }
}

@Observable
@MainActor
final class HistoryModel {
    var records: [CleanupRecord] = []
    var message: String?

    func reload() async {
        records = await CleanupHistory.shared.records()
    }

    func record(_ record: CleanupRecord) async {
        await CleanupHistory.shared.append(record)
        await reload()
    }

    /// Puts a previous cleanup back where it came from, item by item.
    func undo(_ record: CleanupRecord) async {
        let outcome = Trasher.putBack(record.items)
        if outcome.removed.isEmpty {
            message = "Nothing could be restored — those items are no longer in the Trash."
        } else if outcome.failures.isEmpty {
            message = "Restored \(Format.count(outcome.removed.count, singular: "item"))."
            await CleanupHistory.shared.remove(id: record.id)
        } else {
            message = "Restored \(outcome.removed.count) of \(record.items.count) items."
        }
        await reload()
    }

    func clear() async {
        await CleanupHistory.shared.clear()
        await reload()
    }
}
