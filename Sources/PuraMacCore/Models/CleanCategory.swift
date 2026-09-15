import Foundation

public enum CleanSafety: String, Sendable, Comparable, CaseIterable {
    case safe
    case review
    case caution

    public var label: String {
        switch self {
        case .safe: return "Safe"
        case .review: return "Worth a look"
        case .caution: return "Be careful"
        }
    }

    public static func < (lhs: CleanSafety, rhs: CleanSafety) -> Bool {
        let order: [CleanSafety] = [.safe, .review, .caution]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

public enum RemovalStyle: Sendable, Equatable {
    /// Moved to the Trash, so the user can put it back.
    case trash
    /// Genuinely deleted. Only ever used for emptying the Trash, which is
    /// already the undo buffer — there is nowhere further to move it to.
    case permanentDelete
    /// Reported so the user can see where the space went, never removed by PuraMac.
    case measureOnly
}

public enum CategorySource: Sendable, Equatable {
    /// Each immediate child of this folder is an independently removable unit.
    case directoryChildren(tildePath: String, excluding: Set<String> = [])
    /// Immediate children last modified more than `days` ago.
    case childrenOlderThan(tildePath: String, days: Int)
    /// Measured whole, never removed.
    case wholeDirectory(tildePath: String)

    var tildePath: String {
        switch self {
        case .directoryChildren(let path, _): return path
        case .childrenOlderThan(let path, _): return path
        case .wholeDirectory(let path): return path
        }
    }

    /// Home is injectable so scans can be exercised against a synthetic tree in tests.
    func expandedPath(home: String = NSHomeDirectory()) -> String {
        guard tildePath.hasPrefix("~") else { return tildePath }
        return home + tildePath.dropFirst()
    }
}

public struct CleanCategory: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let safety: CleanSafety
    public let removal: RemovalStyle
    public let defaultSelected: Bool
    public let source: CategorySource

    public static func == (lhs: CleanCategory, rhs: CleanCategory) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public extension CleanCategory {

    /// Homebrew keeps its downloads inside ~/Library/Caches, so it is broken out
    /// as its own category and excluded from the general cache sweep to stop the
    /// same bytes being counted twice.
    static let homebrewChildName = "Homebrew"

    static let all: [CleanCategory] = [
        CleanCategory(
            id: "caches",
            title: "Application caches",
            detail: "Temporary files apps rebuild on demand. Nothing you created lives here.",
            safety: .safe,
            removal: .trash,
            defaultSelected: true,
            source: .directoryChildren(tildePath: "~/Library/Caches", excluding: [homebrewChildName])
        ),
        CleanCategory(
            id: "logs",
            title: "Application logs",
            detail: "Diagnostic text apps write as they run. Useful only while debugging a problem.",
            safety: .safe,
            removal: .trash,
            defaultSelected: true,
            source: .directoryChildren(tildePath: "~/Library/Logs")
        ),
        CleanCategory(
            id: "dotcache",
            title: "Hidden tool caches",
            detail: "The ~/.cache folder used by command line tools. Same idea as app caches.",
            safety: .safe,
            removal: .trash,
            defaultSelected: true,
            source: .directoryChildren(tildePath: "~/.cache")
        ),
        CleanCategory(
            id: "npmcache",
            title: "npm package cache",
            detail: "Packages npm downloaded before. It re-fetches anything it needs.",
            safety: .safe,
            removal: .trash,
            defaultSelected: true,
            source: .directoryChildren(tildePath: "~/.npm/_cacache")
        ),
        CleanCategory(
            id: "brewcache",
            title: "Homebrew downloads",
            detail: "Installer archives Homebrew already used. It re-downloads them if a reinstall needs them.",
            safety: .safe,
            removal: .trash,
            defaultSelected: true,
            source: .directoryChildren(tildePath: "~/Library/Caches/Homebrew")
        ),
        CleanCategory(
            id: "deriveddata",
            title: "Xcode DerivedData",
            detail: "Build output Xcode regenerates. Clearing it means one slower build, nothing more.",
            safety: .safe,
            removal: .trash,
            defaultSelected: true,
            source: .directoryChildren(tildePath: "~/Library/Developer/Xcode/DerivedData")
        ),
        CleanCategory(
            id: "simulatorcaches",
            title: "Simulator caches",
            detail: "Cached simulator runtime data. Regenerated the next time a simulator boots.",
            safety: .safe,
            removal: .trash,
            defaultSelected: true,
            source: .directoryChildren(tildePath: "~/Library/Developer/CoreSimulator/Caches")
        ),
        CleanCategory(
            id: "devicesupport",
            title: "iOS device support",
            detail: "Debug symbols for iPhones you plugged in. Rebuilt on the next connect, which takes a few minutes.",
            safety: .review,
            removal: .trash,
            defaultSelected: false,
            source: .directoryChildren(tildePath: "~/Library/Developer/Xcode/iOS DeviceSupport")
        ),
        CleanCategory(
            id: "archives",
            title: "Xcode archives",
            detail: "Builds you archived for distribution. Keep any you may still need to symbolicate a crash report against.",
            safety: .caution,
            removal: .trash,
            defaultSelected: false,
            source: .directoryChildren(tildePath: "~/Library/Developer/Xcode/Archives")
        ),
        CleanCategory(
            id: "downloads",
            title: "Downloads over 30 days old",
            detail: "Old files in your Downloads folder. Expand the row and check before selecting this one.",
            safety: .caution,
            removal: .trash,
            defaultSelected: false,
            source: .childrenOlderThan(tildePath: "~/Downloads", days: 30)
        ),
        CleanCategory(
            id: "trash",
            title: "Trash",
            detail: "Files you already deleted. Emptying is permanent — the Trash is the undo step.",
            safety: .caution,
            removal: .permanentDelete,
            defaultSelected: false,
            source: .directoryChildren(tildePath: "~/.Trash")
        ),
        CleanCategory(
            id: "iosbackups",
            title: "iPhone and iPad backups",
            detail: "Device backups, often tens of gigabytes. PuraMac never touches these — remove them in Finder if you are sure.",
            safety: .caution,
            removal: .measureOnly,
            defaultSelected: false,
            source: .wholeDirectory(tildePath: "~/Library/Application Support/MobileSync/Backup")
        ),
        CleanCategory(
            id: "containers",
            title: "App containers",
            detail: "Sandboxed app data, including Docker disk images and Mail. Shown so you can see the size — manage these in each app.",
            safety: .caution,
            removal: .measureOnly,
            defaultSelected: false,
            source: .wholeDirectory(tildePath: "~/Library/Containers")
        )
    ]
}
