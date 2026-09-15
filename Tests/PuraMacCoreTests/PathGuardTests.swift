import Testing
import Foundation
@testable import PuraMacCore

@Suite("PathGuard")
struct PathGuardTests {
    let home = "/Users/testuser"

    @Test("Accepts ordinary removable paths")
    func acceptsSafePaths() {
        let allowed = [
            "/Users/testuser/Library/Caches/com.example.app",
            "/Users/testuser/Library/Logs/SomeApp.log",
            "/Users/testuser/.Trash/old-file.zip",
            "/Users/testuser/Downloads/installer.dmg",
            "/Users/testuser/.cache/pip",
            "/Users/testuser/Library/Developer/Xcode/DerivedData/App-abc123"
        ]
        for path in allowed {
            #expect(PathGuard.validate(path, home: home) == nil, "expected \(path) to be allowed")
        }
    }

    @Test("Refuses the home folder itself")
    func refusesHome() {
        #expect(PathGuard.validate(home, home: home) == .isHomeItself)
        #expect(PathGuard.validate(home + "/", home: home) == .isHomeItself)
    }

    @Test("Refuses protected top-level folders but not their contents")
    func refusesProtectedChildren() {
        #expect(PathGuard.validate("/Users/testuser/Documents", home: home) == .protectedDirectory("Documents"))
        #expect(PathGuard.validate("/Users/testuser/Library", home: home) == .protectedDirectory("Library"))
        #expect(PathGuard.validate("/Users/testuser/Desktop", home: home) == .protectedDirectory("Desktop"))
        #expect(PathGuard.validate("/Users/testuser/.Trash", home: home) == .protectedDirectory(".Trash"))
        // Contents remain removable.
        #expect(PathGuard.validate("/Users/testuser/Documents/notes.txt", home: home) == nil)
    }

    @Test("Refuses irreplaceable Library locations")
    func refusesPreciousLibraryData() {
        let refused = [
            "/Users/testuser/Library/Keychains",
            "/Users/testuser/Library/Keychains/login.keychain-db",
            "/Users/testuser/Library/Mobile Documents/com~apple~CloudDocs",
            "/Users/testuser/Library/Containers/com.apple.mail",
            "/Users/testuser/Library/Preferences/com.apple.finder.plist",
            "/Users/testuser/Library/Application Support/MobileSync/Backup",
            "/Users/testuser/Library/Messages/chat.db"
        ]
        for path in refused {
            let rejection = PathGuard.validate(path, home: home)
            #expect(rejection != nil, "expected \(path) to be refused")
            if case .protectedDirectory = rejection {} else {
                Issue.record("expected \(path) to be refused as protected, got \(String(describing: rejection))")
            }
        }
    }

    @Test("Refuses anything outside the home folder")
    func refusesOutsideHome() {
        #expect(PathGuard.validate("/System/Library", home: home) == .systemPath)
        #expect(PathGuard.validate("/usr/bin/swift", home: home) == .systemPath)
        #expect(PathGuard.validate("/Applications/Safari.app", home: home) == .systemPath)
        #expect(PathGuard.validate("/Users/someoneelse/Documents", home: home) != nil)
    }

    @Test("Refuses malformed and traversing paths")
    func refusesMalformed() {
        #expect(PathGuard.validate("", home: home) == .empty)
        #expect(PathGuard.validate("   ", home: home) == .empty)
        #expect(PathGuard.validate("Library/Caches/thing", home: home) == .notAbsolute)
        #expect(PathGuard.validate("/Users/testuser/Library/Caches/../../../etc", home: home) == .traversal)
    }

    @Test("A symlink cannot be used to escape the home folder")
    func refusesSymlinkEscape() throws {
        let fm = FileManager.default
        let fakeHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("puramac-guard-\(UUID().uuidString)")
        let caches = fakeHome.appendingPathComponent("Library/Caches")
        try fm.createDirectory(at: caches, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: fakeHome) }

        let escape = caches.appendingPathComponent("escape-hatch")
        try fm.createSymbolicLink(atPath: escape.path, withDestinationPath: "/usr/local")

        let rejection = PathGuard.validate(escape.path, home: fakeHome.path)
        #expect(rejection != nil, "a symlink pointing outside home must be refused")
    }

    @Test("Partitioning reports what was refused and why")
    func partitionSeparatesInputs() {
        let (allowed, refused) = PathGuard.partition([
            "/Users/testuser/Library/Caches/a",
            "/Users/testuser/Library/Keychains",
            "/System/Library"
        ], home: home)
        #expect(allowed == ["/Users/testuser/Library/Caches/a"])
        #expect(refused.count == 2)
        #expect(refused.allSatisfy { !$0.rejection.reason.isEmpty })
    }
}
