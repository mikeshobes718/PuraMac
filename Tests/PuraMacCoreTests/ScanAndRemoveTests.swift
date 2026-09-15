import Testing
import Foundation
@testable import PuraMacCore

/// Builds a throwaway home directory so scanning and removal can be exercised
/// end to end without touching the real one.
struct FakeHome: ~Copyable {
    let root: URL

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("puramac-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    var path: String { root.path }

    @discardableResult
    func write(_ relative: String, bytes: Int, modified: Date? = nil) throws -> String {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        return url.path
    }

    func makeDirectory(_ relative: String) throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(relative), withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }
}

@Suite("DirectoryScanner")
struct DirectoryScannerTests {

    @Test("Totals every file beneath the root")
    func measuresRecursively() throws {
        let home = try FakeHome()
        try home.write("Library/Caches/appA/one.bin", bytes: 4096)
        try home.write("Library/Caches/appA/nested/two.bin", bytes: 4096)
        try home.write("Library/Caches/appB/three.bin", bytes: 4096)

        let measured = try DirectoryScanner.measure(root: home.path + "/Library/Caches")
        #expect(measured.fileCount == 3)
        #expect(measured.bytes >= 12288)
        #expect(measured.breakdown.count == 2)
        #expect(measured.breakdown.first?.name == "appA")
    }

    @Test("Immediate children carry their own recursive sizes")
    func childrenAreSizedIndependently() throws {
        let home = try FakeHome()
        try home.write("Library/Caches/big/a.bin", bytes: 8192)
        try home.write("Library/Caches/small/b.bin", bytes: 1024)

        let children = try DirectoryScanner.children(of: home.path + "/Library/Caches")
        #expect(children.count == 2)
        #expect(children[0].name == "big")
        #expect(children[0].bytes > children[1].bytes)
        let allAreDirectories = children.allSatisfy { $0.isDirectory }
        #expect(allAreDirectories)
    }

    @Test("A missing folder measures as empty rather than throwing")
    func missingRootIsEmpty() throws {
        let measured = try DirectoryScanner.measure(root: "/nope/does/not/exist")
        #expect(measured.fileCount == 0)
        #expect(measured.bytes == 0)
    }

    @Test("Scanning stops when the task is cancelled")
    func honoursCancellation() async throws {
        let home = try FakeHome()
        for index in 0..<200 {
            try home.write("Library/Caches/bulk/file\(index).bin", bytes: 16)
        }
        let root = home.path + "/Library/Caches"
        let task = Task<DirectoryMeasurement, Error> {
            while !Task.isCancelled { await Task.yield() }
            return try DirectoryScanner.measure(root: root)
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("scan should have thrown CancellationError")
        } catch is CancellationError {
            // expected
        }
    }
}

@Suite("CleanScanner")
struct CleanScannerTests {

    @Test("Homebrew downloads are not counted twice")
    func homebrewIsExcludedFromGeneralCaches() throws {
        let home = try FakeHome()
        try home.write("Library/Caches/appA/one.bin", bytes: 4096)
        try home.write("Library/Caches/Homebrew/formula.tar.gz", bytes: 8192)

        let caches = CleanCategory.all.first { $0.id == "caches" }!
        let brew = CleanCategory.all.first { $0.id == "brewcache" }!

        let cachesGroup = try CleanScanner.scanCategory(caches, home: home.path)
        let brewGroup = try CleanScanner.scanCategory(brew, home: home.path)

        #expect(cachesGroup.removablePaths.count == 1)
        #expect(cachesGroup.removablePaths[0].hasSuffix("/appA"))
        #expect(brewGroup.removablePaths.count == 1)
        #expect(brewGroup.bytes >= 8192)
    }

    @Test("Old downloads are selected by age, recent ones are left alone")
    func downloadsFilterByAge() throws {
        let home = try FakeHome()
        let old = Date().addingTimeInterval(-60 * 86_400)
        try home.write("Downloads/ancient.dmg", bytes: 2048, modified: old)
        try home.write("Downloads/fresh.dmg", bytes: 2048)

        let category = CleanCategory.all.first { $0.id == "downloads" }!
        let group = try CleanScanner.scanCategory(category, home: home.path)

        #expect(group.removablePaths.count == 1)
        #expect(group.removablePaths[0].hasSuffix("ancient.dmg"))
    }

    @Test("A folder that does not exist is reported, not treated as empty success")
    func missingCategoryIsFlagged() throws {
        let home = try FakeHome()
        let category = CleanCategory.all.first { $0.id == "deriveddata" }!
        let group = try CleanScanner.scanCategory(category, home: home.path)
        #expect(group.unavailableReason == "Not present on this Mac")
        #expect(!group.isActionable)
    }

    @Test("Measure-only categories never expose removable paths")
    func measureOnlyStaysUnactionable() throws {
        let home = try FakeHome()
        try home.write("Library/Containers/com.example/data.bin", bytes: 4096)
        let category = CleanCategory.all.first { $0.id == "containers" }!
        let group = try CleanScanner.scanCategory(category, home: home.path)

        #expect(group.bytes >= 4096)
        #expect(group.removablePaths.isEmpty)
        #expect(!group.isActionable)
    }

    @Test("The headline total excludes anything PuraMac will not remove")
    func reclaimableExcludesMeasureOnly() throws {
        let home = try FakeHome()
        try home.write("Library/Caches/appA/one.bin", bytes: 4096)
        try home.write("Library/Containers/com.example/huge.bin", bytes: 65536)

        let ids = ["caches", "containers"]
        let groups = try CleanCategory.all
            .filter { ids.contains($0.id) }
            .map { try CleanScanner.scanCategory($0, home: home.path) }
        let report = CleanScanReport(groups: groups, duration: 0)

        #expect(report.reclaimableBytes >= 4096)
        #expect(report.reclaimableBytes < 65536)
    }

    @Test("The AI summary carries sizes but never a path")
    func summaryIsAnonymized() throws {
        let home = try FakeHome()
        try home.write("Library/Caches/SecretProject/one.bin", bytes: 4096)
        let category = CleanCategory.all.first { $0.id == "caches" }!
        let report = CleanScanReport(groups: [try CleanScanner.scanCategory(category, home: home.path)], duration: 0)

        let summary = report.anonymizedSummary()
        #expect(summary.contains("Application caches"))
        #expect(!summary.contains("SecretProject"))
        #expect(!summary.contains("/"))
    }
}

@Suite("Trasher")
struct TrasherTests {

    @Test("Refuses a path the guard rejects instead of removing it")
    func refusesGuardedPaths() throws {
        let home = try FakeHome()
        try home.makeDirectory("Library/Keychains")
        let target = home.path + "/Library/Keychains"

        let outcome = try Trasher.remove(
            [RemovalRequest(path: target, knownBytes: 100)],
            style: .trash,
            home: home.path)

        #expect(outcome.removed.isEmpty)
        #expect(outcome.refused.count == 1)
        #expect(FileManager.default.fileExists(atPath: target))
    }

    @Test("Permanent deletion is confined to the Trash")
    func permanentDeleteOnlyInsideTrash() throws {
        let home = try FakeHome()
        let inTrash = try home.write(".Trash/junk.bin", bytes: 1024)
        let outsideTrash = try home.write("Library/Caches/app/keep.bin", bytes: 1024)

        let outcome = try Trasher.remove([
            RemovalRequest(path: inTrash, knownBytes: 1024),
            RemovalRequest(path: outsideTrash, knownBytes: 1024)
        ], style: .permanentDelete, home: home.path)

        #expect(!FileManager.default.fileExists(atPath: inTrash))
        #expect(FileManager.default.fileExists(atPath: outsideTrash), "only the Trash may be emptied")
        #expect(outcome.failures.count == 1)
        #expect(outcome.freedBytes == 1024)
    }

    @Test("Freed bytes come from the scan, so nothing is re-walked")
    func reportsKnownSizes() throws {
        let home = try FakeHome()
        let file = try home.write(".Trash/a.bin", bytes: 4096)
        let outcome = try Trasher.remove(
            [RemovalRequest(path: file, knownBytes: 4096)],
            style: .permanentDelete,
            home: home.path)
        #expect(outcome.freedBytes == 4096)
        #expect(outcome.isFullySuccessful)
    }

    @Test("A path that vanished between scan and clean is skipped quietly")
    func missingPathIsNotAFailure() throws {
        let home = try FakeHome()
        let outcome = try Trasher.remove(
            [RemovalRequest(path: home.path + "/.Trash/gone.bin", knownBytes: 10)],
            style: .permanentDelete,
            home: home.path)
        #expect(outcome.removed.isEmpty)
        #expect(outcome.failures.isEmpty)
    }
}
