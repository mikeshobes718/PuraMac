import Foundation

public struct CleanGroup: Sendable, Identifiable {
    public let category: CleanCategory
    public var bytes: Int64
    public var itemCount: Int
    /// Exact paths captured during the scan. Removal replays this list rather
    /// than re-reading the folder, so nothing created after the scan is touched.
    public var removablePaths: [String]
    /// Size of every removable path. Kept separate from `breakdown`, which is
    /// truncated for display — sizing removals off a truncated list silently
    /// reported 0 bytes for everything past the cut.
    public var removableSizes: [String: Int64]
    public var breakdown: [SizedEntry]
    public var unavailableReason: String?
    public var refused: [String]
    public var isSelected: Bool

    public var id: String { category.id }
    public var isActionable: Bool {
        unavailableReason == nil && category.removal != .measureOnly && !removablePaths.isEmpty
    }

    /// Exactly what removal should act on: every recorded path, each carrying
    /// the size measured for it during the scan.
    public var removalRequests: [RemovalRequest] {
        removablePaths.map { RemovalRequest(path: $0, knownBytes: removableSizes[$0] ?? 0) }
    }

    public func size(of path: String) -> Int64 {
        removableSizes[path] ?? 0
    }

    init(category: CleanCategory) {
        self.category = category
        self.bytes = 0
        self.itemCount = 0
        self.removablePaths = []
        self.removableSizes = [:]
        self.breakdown = []
        self.unavailableReason = nil
        self.refused = []
        self.isSelected = category.defaultSelected
    }
}

public struct ScanProgress: Sendable {
    public var message: String
    public var completed: Int
    public var total: Int
    public var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
}

public struct CleanScanReport: Sendable {
    public var groups: [CleanGroup]
    public var duration: TimeInterval

    public init(groups: [CleanGroup], duration: TimeInterval) {
        self.groups = groups
        self.duration = duration
    }

    /// Bytes PuraMac could actually reclaim. Measure-only categories are excluded
    /// so the headline number never promises space the app will not free.
    public var reclaimableBytes: Int64 {
        groups.filter { $0.isActionable }.reduce(0) { $0 + $1.bytes }
    }

    public var selectedBytes: Int64 {
        groups.filter { $0.isActionable && $0.isSelected }.reduce(0) { $0 + $1.bytes }
    }

    public var selectedItemCount: Int {
        groups.filter { $0.isActionable && $0.isSelected }.reduce(0) { $0 + $1.itemCount }
    }

    /// Category names and sizes only — never a file path. This is the sole shape
    /// of scan data the AI assistant is ever allowed to see.
    public func anonymizedSummary() -> String {
        groups
            .filter { $0.itemCount > 0 && $0.unavailableReason == nil }
            .map { "\($0.category.title): \(Format.bytes($0.bytes)) across \(Format.count($0.itemCount, singular: "item"))" }
            .joined(separator: ", ")
    }
}

private actor ProgressTracker {
    private var completed = 0
    private let total: Int
    private let sink: @Sendable (ScanProgress) -> Void

    init(total: Int, sink: @escaping @Sendable (ScanProgress) -> Void) {
        self.total = total
        self.sink = sink
    }

    func note(_ message: String) {
        sink(ScanProgress(message: message, completed: completed, total: total))
    }

    func finish(_ title: String) {
        completed += 1
        sink(ScanProgress(message: "Scanned \(title)", completed: completed, total: total))
    }
}

public enum CleanScanner {

    public static func scan(
        categories: [CleanCategory] = CleanCategory.all,
        home: String = NSHomeDirectory(),
        onProgress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
    ) async throws -> CleanScanReport {
        let started = Date()
        let tracker = ProgressTracker(total: categories.count, sink: onProgress)

        let groups = try await withThrowingTaskGroup(of: (Int, CleanGroup).self) { group in
            for (index, category) in categories.enumerated() {
                group.addTask {
                    await tracker.note("Scanning \(category.title)…")
                    let scanned = try scanCategory(category, home: home)
                    await tracker.finish(category.title)
                    return (index, scanned)
                }
            }
            var collected: [(Int, CleanGroup)] = []
            for try await entry in group { collected.append(entry) }
            return collected.sorted { $0.0 < $1.0 }.map { $0.1 }
        }

        return CleanScanReport(groups: groups, duration: Date().timeIntervalSince(started))
    }

    static func scanCategory(_ category: CleanCategory, home: String = NSHomeDirectory()) throws -> CleanGroup {
        var group = CleanGroup(category: category)
        let root = category.source.expandedPath(home: home)

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else {
            group.unavailableReason = "Not present on this Mac"
            return group
        }

        switch category.source {
        case .wholeDirectory:
            let measured = try DirectoryScanner.measure(root: root)
            group.bytes = measured.bytes
            group.itemCount = measured.fileCount
            group.breakdown = measured.breakdown

        case .directoryChildren(_, let excluding):
            let children = try DirectoryScanner.children(of: root)
                .filter { !excluding.contains($0.name) }
            try apply(children: children, to: &group, home: home)

        case .childrenOlderThan(_, let days):
            let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
            let children = try DirectoryScanner.children(of: root)
                .filter { $0.modified < cutoff }
            try apply(children: children, to: &group, home: home)
        }

        if group.itemCount == 0 && group.unavailableReason == nil && group.bytes == 0 {
            group.unavailableReason = "Already clean"
        }
        return group
    }

    private static func apply(children: [SizedEntry], to group: inout CleanGroup, home: String) throws {
        let partitioned = PathGuard.partition(children.map(\.path), home: home)
        let allowed = Set(partitioned.allowed)
        let usable = children.filter { allowed.contains($0.path) }

        group.removablePaths = usable.map(\.path)
        group.removableSizes = Dictionary(usable.map { ($0.path, $0.bytes) },
                                          uniquingKeysWith: { first, _ in first })
        group.bytes = usable.reduce(0) { $0 + $1.bytes }
        group.itemCount = usable.count
        group.breakdown = Array(usable.prefix(12))
        group.refused = partitioned.refused.map(\.path)

        if usable.isEmpty && !partitioned.refused.isEmpty {
            group.unavailableReason = "Protected on this Mac"
        }
    }
}
