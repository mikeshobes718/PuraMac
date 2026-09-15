import SwiftUI
import Observation
import PuraMacCore

/// Shared shape for every long-running pane: one cancellable task, a progress
/// line, and an error the view can actually show instead of swallowing.
@Observable
@MainActor
class ScanModelBase {
    var isBusy = false
    var progressText = ""
    var progressFraction: Double?
    var errorMessage: String?
    var statusMessage: String?

    var onCleanFinished: ((CleanupRecord) -> Void)?

    fileprivate var task: Task<Void, Never>?

    func cancel() {
        task?.cancel()
        task = nil
        isBusy = false
        progressText = ""
        progressFraction = nil
        statusMessage = "Cancelled."
    }

    fileprivate func begin(_ message: String) {
        errorMessage = nil
        statusMessage = nil
        progressText = message
        progressFraction = nil
        isBusy = true
    }

    fileprivate func finish() {
        isBusy = false
        progressText = ""
        progressFraction = nil
        task = nil
    }

    fileprivate func handle(_ error: Error) {
        if error is CancellationError { return }
        errorMessage = error.localizedDescription
        Log.scan.error("\(error.localizedDescription, privacy: .public)")
    }

    fileprivate func describe(_ outcome: RemovalOutcome, noun: String) -> String {
        var parts = ["Moved \(Format.bytes(outcome.freedBytes)) to the Trash"]
        if !outcome.failures.isEmpty {
            parts.append("\(outcome.failures.count) \(noun) could not be moved")
        }
        if !outcome.refused.isEmpty {
            parts.append("\(outcome.refused.count) refused for safety")
        }
        return parts.joined(separator: " · ") + "."
    }
}

// MARK: - Smart Clean

@Observable
@MainActor
final class SmartCleanModel: ScanModelBase {
    var report: CleanScanReport?
    var expanded: Set<String> = []

    var groups: [CleanGroup] { report?.groups ?? [] }
    var selectedBytes: Int64 { report?.selectedBytes ?? 0 }
    var reclaimableBytes: Int64 { report?.reclaimableBytes ?? 0 }
    var hasSelection: Bool { groups.contains { $0.isActionable && $0.isSelected } }

    func startScan() {
        guard !isBusy else { return }
        begin("Starting scan…")
        report = nil
        expanded = []

        task = Task { [weak self] in
            do {
                let result = try await CleanScanner.scan { progress in
                    Task { @MainActor in
                        self?.progressText = progress.message
                        self?.progressFraction = progress.fraction
                    }
                }
                guard !Task.isCancelled else { return }
                self?.report = result
                self?.statusMessage = result.reclaimableBytes > 0
                    ? "Found \(Format.bytes(result.reclaimableBytes)) you can reclaim."
                    : "Nothing to reclaim right now — this Mac is already tidy."
                self?.notifyIfWanted(result)
            } catch {
                self?.handle(error)
            }
            self?.finish()
        }
    }

    private func notifyIfWanted(_ result: CleanScanReport) {
        guard Preferences.shared.notifyOnFinish, result.reclaimableBytes > 0 else { return }
        Notifier.post(
            title: "Scan complete",
            body: "\(Format.bytes(result.reclaimableBytes)) can be reclaimed.")
    }

    func toggle(_ groupID: String) {
        guard var report, let index = report.groups.firstIndex(where: { $0.id == groupID }) else { return }
        report.groups[index].isSelected.toggle()
        self.report = report
    }

    func setExpanded(_ groupID: String, _ value: Bool) {
        if value { expanded.insert(groupID) } else { expanded.remove(groupID) }
    }

    func selectAllSafe() {
        guard var report else { return }
        for index in report.groups.indices where report.groups[index].isActionable {
            report.groups[index].isSelected = report.groups[index].category.safety == .safe
        }
        self.report = report
    }

    func deselectAll() {
        guard var report else { return }
        for index in report.groups.indices {
            report.groups[index].isSelected = false
        }
        self.report = report
    }

    var selectedGroups: [CleanGroup] {
        groups.filter { $0.isActionable && $0.isSelected }
    }

    func performClean() {
        let selected = selectedGroups
        guard !selected.isEmpty, !isBusy else { return }
        begin("Moving items to the Trash…")

        task = Task { [weak self] in
            var combined = RemovalOutcome()
            do {
                // Each category is removed with its own style, so emptying the
                // Trash stays a genuine delete while everything else is reversible.
                for group in selected {
                    let requests = group.removalRequests
                    let outcome = try Trasher.remove(
                        requests,
                        style: group.category.removal
                    ) { name, index, total in
                        Task { @MainActor in
                            self?.progressText = name.isEmpty ? "Finishing…" : "Removing \(name)…"
                            self?.progressFraction = total > 0 ? Double(index) / Double(total) : nil
                        }
                    }
                    combined.removed += outcome.removed
                    combined.failures += outcome.failures
                    combined.refused += outcome.refused
                }
            } catch {
                self?.handle(error)
            }

            guard let self else { return }
            self.statusMessage = self.describe(combined, noun: "items")
            if combined.freedBytes > 0 {
                self.onCleanFinished?(CleanupRecord(
                    summary: "Smart Clean · " + selected.map(\.category.title).joined(separator: ", "),
                    freedBytes: combined.freedBytes,
                    items: combined.removed))
                if Preferences.shared.notifyOnFinish {
                    Notifier.post(title: "Cleanup complete",
                                  body: "PuraMac freed \(Format.bytes(combined.freedBytes)).")
                }
            }
            self.report = nil
            self.finish()
        }
    }
}

// MARK: - Large files

@Observable
@MainActor
final class LargeFilesModel: ScanModelBase {
    var files: [SizedEntry] = []
    var selected: Set<String> = []
    var minimumMB: Int = Preferences.shared.largeFileThresholdMB
    var olderThanDays: Int?

    var selectedBytes: Int64 {
        files.filter { selected.contains($0.path) }.reduce(0) { $0 + $1.bytes }
    }
    var totalBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }

    func startScan() {
        guard !isBusy else { return }
        begin("Searching your folders…")
        files = []
        selected = []
        Preferences.shared.largeFileThresholdMB = minimumMB

        let query = LargeFileQuery(
            minimumBytes: Int64(minimumMB) * 1_000_000,
            olderThanDays: olderThanDays)

        task = Task { [weak self] in
            do {
                let found = try await Task.detached(priority: .userInitiated) {
                    try LargeFileScanner.scan(query) { message in
                        Task { @MainActor in self?.progressText = message }
                    }
                }.value
                guard !Task.isCancelled else { return }
                self?.files = found
                self?.statusMessage = found.isEmpty
                    ? "No files over \(self?.minimumMB ?? 0) MB in the folders PuraMac searches."
                    : "\(Format.count(found.count, singular: "file")) · \(Format.bytes(found.reduce(0) { $0 + $1.bytes })) total."
            } catch {
                self?.handle(error)
            }
            self?.finish()
        }
    }

    func toggle(_ path: String) {
        if selected.contains(path) { selected.remove(path) } else { selected.insert(path) }
    }

    var selectedEntries: [SizedEntry] { files.filter { selected.contains($0.path) } }

    func moveSelectedToTrash() {
        let entries = selectedEntries
        guard !entries.isEmpty, !isBusy else { return }
        begin("Moving files to the Trash…")

        task = Task { [weak self] in
            do {
                let outcome = try Trasher.remove(
                    entries.map { RemovalRequest(path: $0.path, knownBytes: $0.bytes) },
                    style: .trash
                ) { name, index, total in
                    Task { @MainActor in
                        self?.progressText = name.isEmpty ? "Finishing…" : "Removing \(name)…"
                        self?.progressFraction = total > 0 ? Double(index) / Double(total) : nil
                    }
                }
                guard let self else { return }
                let removedPaths = Set(outcome.removed.map(\.originalPath))
                self.files.removeAll { removedPaths.contains($0.path) }
                self.selected = []
                self.statusMessage = self.describe(outcome, noun: "files")
                if outcome.freedBytes > 0 {
                    self.onCleanFinished?(CleanupRecord(
                        summary: "Large Files · \(Format.count(outcome.removed.count, singular: "file"))",
                        freedBytes: outcome.freedBytes,
                        items: outcome.removed))
                }
            } catch {
                self?.handle(error)
            }
            self?.finish()
        }
    }
}

// MARK: - Duplicates

@Observable
@MainActor
final class DuplicatesModel: ScanModelBase {
    var groups: [DuplicateGroup] = []
    var selected: Set<String> = []

    var reclaimableBytes: Int64 { groups.reduce(0) { $0 + $1.reclaimableBytes } }
    var selectedBytes: Int64 {
        groups.flatMap(\.files).filter { selected.contains($0.path) }.reduce(0) { $0 + $1.bytes }
    }

    func startScan() {
        guard !isBusy else { return }
        begin("Indexing files…")
        groups = []
        selected = []

        task = Task { [weak self] in
            do {
                let found = try await Task.detached(priority: .userInitiated) {
                    try DuplicateFinder.scan(roots: FileWalker.defaultRoots()) { message in
                        Task { @MainActor in self?.progressText = message }
                    }
                }.value
                guard !Task.isCancelled else { return }
                self?.groups = found
                self?.selectExtraCopies()
                self?.statusMessage = found.isEmpty
                    ? "No duplicates found in your personal folders."
                    : "\(Format.count(found.count, singular: "group")) · \(Format.bytes(found.reduce(0) { $0 + $1.reclaimableBytes })) reclaimable."
            } catch {
                self?.handle(error)
            }
            self?.finish()
        }
    }

    /// Pre-selects every copy except the oldest in each group, which is the one
    /// most likely to be the original.
    func selectExtraCopies() {
        selected = []
        for group in groups {
            guard let keep = group.suggestedKeep else { continue }
            for file in group.files where file.path != keep.path {
                selected.insert(file.path)
            }
        }
    }

    func toggle(_ path: String) {
        if selected.contains(path) { selected.remove(path) } else { selected.insert(path) }
    }

    /// Never let a group be wiped entirely — one copy always stays.
    var wouldEraseAnyGroup: Bool {
        groups.contains { group in group.files.allSatisfy { selected.contains($0.path) } }
    }

    func removeSelected() {
        guard !selected.isEmpty, !isBusy, !wouldEraseAnyGroup else { return }
        let entries = groups.flatMap(\.files).filter { selected.contains($0.path) }
        begin("Moving duplicates to the Trash…")

        task = Task { [weak self] in
            do {
                let outcome = try Trasher.remove(
                    entries.map { RemovalRequest(path: $0.path, knownBytes: $0.bytes) },
                    style: .trash
                ) { name, index, total in
                    Task { @MainActor in
                        self?.progressText = name.isEmpty ? "Finishing…" : "Removing \(name)…"
                        self?.progressFraction = total > 0 ? Double(index) / Double(total) : nil
                    }
                }
                guard let self else { return }
                let removed = Set(outcome.removed.map(\.originalPath))
                self.groups = self.groups.compactMap { group in
                    var copy = group
                    copy.files.removeAll { removed.contains($0.path) }
                    return copy.files.count > 1 ? copy : nil
                }
                self.selected = []
                self.statusMessage = self.describe(outcome, noun: "copies")
                if outcome.freedBytes > 0 {
                    self.onCleanFinished?(CleanupRecord(
                        summary: "Duplicates · \(Format.count(outcome.removed.count, singular: "copy", plural: "copies"))",
                        freedBytes: outcome.freedBytes,
                        items: outcome.removed))
                }
            } catch {
                self?.handle(error)
            }
            self?.finish()
        }
    }
}

// MARK: - Uninstaller

@Observable
@MainActor
final class UninstallerModel: ScanModelBase {
    var apps: [InstalledApp] = []
    var selectedApp: InstalledApp?
    var plan: UninstallPlan?
    var searchText = ""

    var filteredApps: [InstalledApp] {
        guard !searchText.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    func loadApps() {
        guard !isBusy else { return }
        begin("Reading installed applications…")

        task = Task { [weak self] in
            do {
                let found = try await Task.detached(priority: .userInitiated) {
                    try AppUninstaller.installedApps { message in
                        Task { @MainActor in self?.progressText = message }
                    }
                }.value
                guard !Task.isCancelled else { return }
                self?.apps = found
                self?.statusMessage = "\(Format.count(found.count, singular: "app")) installed."
            } catch {
                self?.handle(error)
            }
            self?.finish()
        }
    }

    func select(_ app: InstalledApp) {
        selectedApp = app
        plan = nil
        Task { [weak self] in
            do {
                let built = try await Task.detached(priority: .userInitiated) {
                    try AppUninstaller.plan(for: app)
                }.value
                guard self?.selectedApp == app else { return }
                self?.plan = built
            } catch {
                self?.handle(error)
            }
        }
    }

    func uninstall() {
        guard let plan, !isBusy else { return }
        begin("Uninstalling \(plan.app.name)…")

        task = Task { [weak self] in
            do {
                let result = try AppUninstaller.uninstall(plan: plan) { name, index, total in
                    Task { @MainActor in
                        self?.progressText = name.isEmpty ? "Finishing…" : "Removing \(name)…"
                        self?.progressFraction = total > 0 ? Double(index) / Double(total) : nil
                    }
                }
                guard let self else { return }
                self.statusMessage = self.describe(result, noun: "items")
                if result.freedBytes > 0 {
                    self.onCleanFinished?(CleanupRecord(
                        summary: "Uninstalled \(plan.app.name)",
                        freedBytes: result.freedBytes,
                        items: result.removed))
                    if Preferences.shared.notifyOnFinish {
                        Notifier.post(title: "\(plan.app.name) uninstalled",
                                      body: "Freed \(Format.bytes(result.freedBytes)).")
                    }
                }
                self.apps.removeAll { $0.bundlePath == plan.app.bundlePath }
                self.selectedApp = nil
                self.plan = nil
            } catch {
                self?.handle(error)
            }
            self?.finish()
        }
    }
}

// MARK: - Login items

@Observable
@MainActor
final class LoginItemsModel: ScanModelBase {
    var items: [LoginItem] = []
    var selected: Set<String> = []

    func reload() {
        items = LoginItems.scan()
        selected = []
        statusMessage = items.isEmpty
            ? "No third-party login items found."
            : "\(Format.count(items.count, singular: "login item")) found."
    }

    func toggle(_ path: String) {
        if selected.contains(path) { selected.remove(path) } else { selected.insert(path) }
    }

    func disableSelected() {
        let chosen = items.filter { selected.contains($0.plistPath) }
        guard !chosen.isEmpty else { return }
        do {
            let outcome = try LoginItems.disable(chosen)
            let removed = Set(outcome.removed.map(\.originalPath))
            items.removeAll { removed.contains($0.plistPath) }
            selected = []
            statusMessage = "Moved \(Format.count(outcome.removed.count, singular: "login item")) to the Trash."
            if outcome.freedBytes >= 0 && !outcome.removed.isEmpty {
                onCleanFinished?(CleanupRecord(
                    summary: "Disabled \(Format.count(outcome.removed.count, singular: "login item"))",
                    freedBytes: outcome.freedBytes,
                    items: outcome.removed))
            }
        } catch {
            handle(error)
        }
    }
}
