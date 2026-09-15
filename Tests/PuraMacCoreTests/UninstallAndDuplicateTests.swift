import Testing
import Foundation
@testable import PuraMacCore

@Suite("UninstallGuard")
struct UninstallGuardTests {
    let home = "/Users/testuser"

    @Test("Only accepts app bundles in real applications folders")
    func validatesBundleLocation() {
        #expect(UninstallGuard.validateBundle("/Applications/Acme.app", home: home) == nil)
        #expect(UninstallGuard.validateBundle("/Users/testuser/Applications/Acme.app", home: home) == nil)
        #expect(UninstallGuard.validateBundle("/Applications/Acme", home: home) == .notAnApp)
        #expect(UninstallGuard.validateBundle("/Users/testuser/Downloads/Acme.app", home: home) == .unrecognizedLocation)
        #expect(UninstallGuard.validateBundle("/System/Applications/Mail.app", home: home) == .unrecognizedLocation)
    }

    @Test("A leftover must name the app in its own filename")
    func leftoverMustIdentifyTheApp() {
        let ids = ["com.acme.Widget", "Widget"]
        #expect(UninstallGuard.validateLeftover(
            "/Users/testuser/Library/Preferences/com.acme.Widget.plist", identifiers: ids, home: home) == nil)
        #expect(UninstallGuard.validateLeftover(
            "/Users/testuser/Library/Containers/com.acme.Widget", identifiers: ids, home: home) == nil)
        #expect(UninstallGuard.validateLeftover(
            "/Users/testuser/Library/Caches/com.other.App", identifiers: ids, home: home) == .doesNotIdentifyApp)
    }

    @Test("The containing folders themselves can never be selected")
    func cannotSelectContainerFolders() {
        let ids = ["Preferences", "Containers", "Caches", "Library"]
        for folder in ["Preferences", "Containers", "Caches"] {
            let path = "/Users/testuser/Library/\(folder)"
            #expect(UninstallGuard.validateLeftover(path, identifiers: ids, home: home) != nil,
                    "\(path) must never be removable as a leftover")
        }
    }

    @Test("Keychains and iCloud stay unreachable even with a matching name")
    func neverReachesPreciousData() {
        let ids = ["Keychains", "Mobile Documents", "login"]
        #expect(UninstallGuard.validateLeftover(
            "/Users/testuser/Library/Keychains/login.keychain-db", identifiers: ids, home: home) != nil)
        #expect(UninstallGuard.validateLeftover(
            "/Users/testuser/Library/Mobile Documents/anything", identifiers: ids, home: home) != nil)
    }

    @Test("Anything outside the user's Library is rejected")
    func rejectsOutsideLibrary() {
        #expect(UninstallGuard.validateLeftover(
            "/Users/testuser/Documents/Widget.txt", identifiers: ["Widget"], home: home) == .unrecognizedLocation)
        #expect(UninstallGuard.validateLeftover(
            "/etc/Widget.conf", identifiers: ["Widget"], home: home) == .unrecognizedLocation)
    }

    @Test("Short identifiers are dropped so common words cannot match broadly")
    func shortIdentifiersAreDiscarded() {
        let app = InstalledApp(
            name: "Go", bundlePath: "/Applications/Go.app", bundleID: nil,
            version: nil, bytes: 0, lastOpened: nil, isAppleApp: false)
        #expect(AppUninstaller.identifiers(for: app).isEmpty)
    }
}

@Suite("DuplicateFinder")
struct DuplicateFinderTests {

    @Test("Finds identical files and reports what keeping one copy saves")
    func findsIdenticalFiles() throws {
        let home = try FakeHome()
        let payload = Data(repeating: 0x7A, count: 200_000)
        for name in ["Documents/a.bin", "Documents/nested/b.bin", "Desktop/c.bin"] {
            let url = URL(fileURLWithPath: home.path + "/" + name)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try payload.write(to: url)
        }

        let groups = try DuplicateFinder.scan(
            roots: [home.path + "/Documents", home.path + "/Desktop"],
            minimumBytes: 1000)

        #expect(groups.count == 1)
        #expect(groups[0].files.count == 3)
        #expect(groups[0].reclaimableBytes == groups[0].fileSize * 2)
        #expect(groups[0].suggestedKeep != nil)
    }

    @Test("Same-size but different content is not a duplicate")
    func sameSizeIsNotEnough() throws {
        let home = try FakeHome()
        try FileManager.default.createDirectory(
            atPath: home.path + "/Documents", withIntermediateDirectories: true)
        try Data(repeating: 0x01, count: 120_000)
            .write(to: URL(fileURLWithPath: home.path + "/Documents/one.bin"))
        try Data(repeating: 0x02, count: 120_000)
            .write(to: URL(fileURLWithPath: home.path + "/Documents/two.bin"))

        let groups = try DuplicateFinder.scan(roots: [home.path + "/Documents"], minimumBytes: 1000)
        #expect(groups.isEmpty)
    }

    @Test("Files below the size floor are ignored")
    func respectsMinimumSize() throws {
        let home = try FakeHome()
        try home.write("Documents/tiny-a.bin", bytes: 10)
        try home.write("Documents/tiny-b.bin", bytes: 10)
        let groups = try DuplicateFinder.scan(roots: [home.path + "/Documents"], minimumBytes: 1_000_000)
        #expect(groups.isEmpty)
    }
}

@Suite("LoginItems")
struct LoginItemsTests {

    @Test("Reads label, program and launch-at-login from the job definition")
    func parsesAgentPlists() throws {
        let home = try FakeHome()
        try home.makeDirectory("Library/LaunchAgents")
        let plist: [String: Any] = [
            "Label": "com.acme.helper",
            "ProgramArguments": ["/Applications/Acme.app/Contents/MacOS/Helper", "--quiet"],
            "RunAtLoad": true
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: home.path + "/Library/LaunchAgents/com.acme.helper.plist"))

        let items = LoginItems.scan(home: home.path)
        #expect(items.count == 1)
        #expect(items[0].label == "com.acme.helper")
        #expect(items[0].runAtLoad)
        #expect(items[0].program == "/Applications/Acme.app/Contents/MacOS/Helper")
        #expect(!items[0].isAppleProvided)
    }

    @Test("A malformed plist still lists rather than disappearing")
    func toleratesMalformedPlists() throws {
        let home = try FakeHome()
        try home.makeDirectory("Library/LaunchAgents")
        try Data("not a plist".utf8)
            .write(to: URL(fileURLWithPath: home.path + "/Library/LaunchAgents/broken.plist"))
        let items = LoginItems.scan(home: home.path)
        #expect(items.count == 1)
        #expect(items[0].label == "broken")
    }
}

@Suite("Uninstall identifier collisions")
struct UninstallIdentifierCollisionTests {
    let home = "/Users/testuser"

    /// A generically-named app must not reach another vendor's files just
    /// because its name appears as a trailing component of their identifier.
    @Test("A bare app name never matches another vendor's identifier")
    func bareNameDoesNotCollide() {
        let ids = ["com.example.sync", "Sync"]
        let foreign = [
            "/Users/testuser/Library/Preferences/com.microsoft.onedrive.sync.plist",
            "/Users/testuser/Library/Caches/com.google.drive.sync",
            "/Users/testuser/Library/Application Support/com.dropbox.sync.helper"
        ]
        for path in foreign {
            #expect(UninstallGuard.validateLeftover(path, identifiers: ids, home: home) == .doesNotIdentifyApp,
                    "\(path) belongs to another app and must not be matched")
        }
    }

    @Test("The app's own files still match")
    func ownFilesStillMatch() {
        let ids = ["com.example.sync", "Sync"]
        let own = [
            "/Users/testuser/Library/Preferences/com.example.sync.plist",
            "/Users/testuser/Library/Containers/com.example.sync",
            "/Users/testuser/Library/Group Containers/group.com.example.sync",
            "/Users/testuser/Library/Preferences/Sync.plist",
            "/Users/testuser/Library/Caches/Sync-helper"
        ]
        for path in own {
            #expect(UninstallGuard.validateLeftover(path, identifiers: ids, home: home) == nil,
                    "\(path) belongs to this app and should be matched")
        }
    }

    @Test("A fully qualified identifier is still matched anywhere it appears")
    func qualifiedIdentifiersStayFlexible() {
        #expect(UninstallGuard.isQualified("com.acme.Widget"))
        #expect(!UninstallGuard.isQualified("Widget"))
    }
}

@Suite("Removal sizing")
struct RemovalSizingTests {

    /// Sizes used to be read from the display breakdown, which is truncated —
    /// so a category with many entries under-reported everything past the cut.
    @Test("Every removable path carries its real size, past the display cut")
    func sizesCoverAllRemovablePaths() throws {
        let home = try FakeHome()
        for index in 0..<25 {
            try home.write("Library/Caches/app\(index)/data.bin", bytes: 4096)
        }

        let category = CleanCategory.all.first { $0.id == "caches" }!
        let group = try CleanScanner.scanCategory(category, home: home.path)

        #expect(group.removablePaths.count == 25)
        #expect(group.breakdown.count == 12, "breakdown stays truncated for display")

        let requests = group.removalRequests
        #expect(requests.count == 25)
        #expect(requests.allSatisfy { $0.knownBytes > 0 }, "no path may be sized at zero")
        #expect(requests.reduce(0) { $0 + $1.knownBytes } == group.bytes,
                "the sum of removal sizes must equal the scanned total")
    }

    @Test("Freed bytes reported after a removal match what was scanned")
    func freedBytesMatchScan() throws {
        let home = try FakeHome()
        for index in 0..<20 {
            try home.write(".Trash/item\(index).bin", bytes: 8192)
        }

        let category = CleanCategory.all.first { $0.id == "trash" }!
        let group = try CleanScanner.scanCategory(category, home: home.path)
        #expect(group.removablePaths.count == 20)

        let outcome = try Trasher.remove(group.removalRequests, style: .permanentDelete, home: home.path)
        #expect(outcome.removed.count == 20)
        #expect(outcome.freedBytes == group.bytes, "history would otherwise record a short total")
    }
}
