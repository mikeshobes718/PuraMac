import Foundation

public struct InstalledApp: Sendable, Identifiable, Hashable {
    public var name: String
    public var bundlePath: String
    public var bundleID: String?
    public var version: String?
    public var bytes: Int64
    public var lastOpened: Date?
    public var isAppleApp: Bool

    public var id: String { bundlePath }
}

public struct AppLeftover: Sendable, Identifiable, Hashable {
    public var path: String
    public var bytes: Int64
    public var kind: String

    public var id: String { path }
}

public struct UninstallPlan: Sendable {
    public var app: InstalledApp
    public var leftovers: [AppLeftover]

    public var leftoverBytes: Int64 { leftovers.reduce(0) { $0 + $1.bytes } }
    public var totalBytes: Int64 { app.bytes + leftoverBytes }

    public var removalRequests: [RemovalRequest] {
        [RemovalRequest(path: app.bundlePath, knownBytes: app.bytes)]
            + leftovers.map { RemovalRequest(path: $0.path, knownBytes: $0.bytes) }
    }
}

/// Uninstalling has to reach into folders the bulk cleaner refuses outright —
/// an app's own preferences and container are exactly what should go with it.
/// This guard grants that reach as narrowly as possible: a leftover qualifies
/// only if its own filename identifies the app being removed, so the folders
/// themselves can never be selected.
public enum UninstallGuard {

    public enum Rejection: Equatable, Sendable {
        case notAnApp
        case appleApp
        case unrecognizedLocation
        case doesNotIdentifyApp

        public var reason: String {
            switch self {
            case .notAnApp: return "Not an application bundle"
            case .appleApp: return "Built into macOS — remove it in System Settings if at all"
            case .unrecognizedLocation: return "Not in a known applications folder"
            case .doesNotIdentifyApp: return "Does not belong to this app"
            }
        }
    }

    static func appFolders(home: String) -> [String] {
        ["/Applications", "/Applications/Utilities", home + "/Applications"]
    }

    public static func validateBundle(_ path: String, home: String = NSHomeDirectory()) -> Rejection? {
        guard path.hasSuffix(".app") else { return .notAnApp }
        let parent = (path as NSString).deletingLastPathComponent
        guard appFolders(home: home).contains(parent) else { return .unrecognizedLocation }
        if path.hasPrefix("/System/") { return .appleApp }
        return nil
    }

    /// Known folders an app may leave data in. A leftover must sit *inside* one
    /// of these, never be one of them — that structural rule is what keeps
    /// "~/Library/Preferences" itself off the table no matter what it is named.
    public static let leftoverRoots: [(relative: String, kind: String)] = [
        ("Library/Application Support", "Application support"),
        ("Library/Caches", "Cache"),
        ("Library/Preferences", "Preferences"),
        ("Library/Containers", "Container"),
        ("Library/Group Containers", "Shared container"),
        ("Library/Saved Application State", "Saved window state"),
        ("Library/Logs", "Logs"),
        ("Library/WebKit", "Web data"),
        ("Library/HTTPStorages", "Web storage"),
        ("Library/Cookies", "Cookies"),
        ("Library/LaunchAgents", "Login item"),
        ("Library/Application Scripts", "Automation scripts")
    ]

    /// A leftover must be a direct child of a known leftover folder and must
    /// name the app in its own last path component.
    public static func validateLeftover(
        _ path: String,
        identifiers: [String],
        home: String = NSHomeDirectory()
    ) -> Rejection? {
        let parent = (path as NSString).deletingLastPathComponent
        let allowedParents = leftoverRoots.map { home + "/" + $0.relative }
        guard allowedParents.contains(parent) else { return .unrecognizedLocation }

        // Both forms are checked because a container folder named like a bundle
        // identifier ("com.acme.Widget") would otherwise have its final segment
        // stripped as if it were a file extension.
        let component = (path as NSString).lastPathComponent.lowercased()
        let stem = (component as NSString).deletingPathExtension
        guard !component.isEmpty else { return .doesNotIdentifyApp }

        let matches = identifiers.contains { identifier in
            let needle = identifier.lowercased()
            guard !needle.isEmpty else { return false }
            let qualified = isQualified(identifier)
            return matchesOnComponentBoundary(stem: component, needle: needle, qualified: qualified)
                || matchesOnComponentBoundary(stem: stem, needle: needle, qualified: qualified)
        }
        return matches ? nil : .doesNotIdentifyApp
    }

    /// A reverse-DNS bundle identifier is globally namespaced, so finding it
    /// anywhere in a filename genuinely identifies the app. A bare app name is
    /// not — "Sync" appears inside plenty of identifiers belonging to other
    /// vendors — so it gets the stricter rule below.
    static func isQualified(_ identifier: String) -> Bool {
        identifier.contains(".")
    }

    /// For a qualified identifier, matching any whole dot-component is enough,
    /// so "com.acme.widget" still matches "group.com.acme.widget". A bare name
    /// must start the filename instead: "Sync" matches "Sync.plist" and
    /// "Sync-helper", but never "com.microsoft.onedrive.sync".
    static func matchesOnComponentBoundary(stem: String, needle: String, qualified: Bool) -> Bool {
        if stem == needle { return true }
        for separator in [".", "-", "_"] where stem.hasPrefix(needle + separator) { return true }
        guard qualified else { return false }
        if stem.hasSuffix("." + needle) { return true }
        if stem.contains("." + needle + ".") { return true }
        return false
    }
}

public enum AppUninstaller {

    public static func installedApps(
        home: String = NSHomeDirectory(),
        includeAppleApps: Bool = false,
        onProgress: @escaping @Sendable (String) -> Void = { _ in }
    ) throws -> [InstalledApp] {
        let fm = FileManager.default
        var apps: [InstalledApp] = []

        for folder in UninstallGuard.appFolders(home: home) {
            guard let names = try? fm.contentsOfDirectory(atPath: folder) else { continue }
            for name in names where name.hasSuffix(".app") {
                try Task.checkCancellation()
                let path = folder + "/" + name
                onProgress("Reading \(name)…")
                guard let app = describe(path: path) else { continue }
                if app.isAppleApp && !includeAppleApps { continue }
                apps.append(app)
            }
        }
        return apps.sorted { $0.bytes > $1.bytes }
    }

    static func describe(path: String) -> InstalledApp? {
        let url = URL(fileURLWithPath: path)
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        var bundleID: String?
        var version: String?
        var displayName: String?

        if let data = try? Data(contentsOf: plistURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            bundleID = plist["CFBundleIdentifier"] as? String
            version = (plist["CFBundleShortVersionString"] as? String) ?? (plist["CFBundleVersion"] as? String)
            displayName = (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String)
        }

        let values = try? url.resourceValues(forKeys: [.contentAccessDateKey])
        let name = displayName ?? (url.deletingPathExtension().lastPathComponent)

        return InstalledApp(
            name: name,
            bundlePath: path,
            bundleID: bundleID,
            version: version,
            bytes: DirectoryScanner.size(of: path),
            lastOpened: values?.contentAccessDate,
            isAppleApp: bundleID?.hasPrefix("com.apple.") ?? path.hasPrefix("/System/")
        )
    }

    /// Identifiers a leftover may legitimately be named after.
    static func identifiers(for app: InstalledApp) -> [String] {
        var result: [String] = []
        if let bundleID = app.bundleID, !bundleID.isEmpty { result.append(bundleID) }
        let folderName = (app.bundlePath as NSString).lastPathComponent
        result.append((folderName as NSString).deletingPathExtension)
        if !result.contains(app.name) { result.append(app.name) }
        // A bare word like "Notes" would match far too much to be safe.
        return result.filter { $0.count >= 4 }
    }

    public static func plan(for app: InstalledApp, home: String = NSHomeDirectory()) throws -> UninstallPlan {
        let identifiers = identifiers(for: app)
        var leftovers: [AppLeftover] = []
        let fm = FileManager.default

        for location in UninstallGuard.leftoverRoots {
            try Task.checkCancellation()
            let root = home + "/" + location.relative
            guard let names = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for name in names {
                let path = root + "/" + name
                guard UninstallGuard.validateLeftover(path, identifiers: identifiers, home: home) == nil else { continue }
                let bytes = DirectoryScanner.size(of: path)
                leftovers.append(AppLeftover(path: path, bytes: bytes, kind: location.kind))
            }
        }

        leftovers.sort { $0.bytes > $1.bytes }
        return UninstallPlan(app: app, leftovers: leftovers)
    }

    /// Uninstall is the one path that may trash an app bundle outside the home
    /// folder, so it validates the bundle and each leftover under its own rules
    /// rather than going through the general cleaner's guard.
    public static func uninstall(
        plan: UninstallPlan,
        home: String = NSHomeDirectory(),
        onProgress: @escaping @Sendable (String, Int, Int) -> Void = { _, _, _ in }
    ) throws -> RemovalOutcome {
        var outcome = RemovalOutcome()

        if let rejection = UninstallGuard.validateBundle(plan.app.bundlePath, home: home) {
            outcome.refused.append(RemovalFailure(path: plan.app.bundlePath, reason: rejection.reason))
            return outcome
        }

        let identifiers = identifiers(for: plan.app)
        let fm = FileManager.default
        var targets: [RemovalRequest] = [
            RemovalRequest(path: plan.app.bundlePath, knownBytes: plan.app.bytes)
        ]
        for leftover in plan.leftovers {
            if let rejection = UninstallGuard.validateLeftover(leftover.path, identifiers: identifiers, home: home) {
                outcome.refused.append(RemovalFailure(path: leftover.path, reason: rejection.reason))
                continue
            }
            targets.append(RemovalRequest(path: leftover.path, knownBytes: leftover.bytes))
        }

        for (index, target) in targets.enumerated() {
            try Task.checkCancellation()
            onProgress((target.path as NSString).lastPathComponent, index, targets.count)
            guard fm.fileExists(atPath: target.path) else { continue }
            do {
                var resulting: NSURL?
                try fm.trashItem(at: URL(fileURLWithPath: target.path), resultingItemURL: &resulting)
                outcome.removed.append(RemovedItem(
                    originalPath: target.path,
                    trashPath: (resulting as URL?)?.path,
                    bytes: target.knownBytes))
            } catch {
                outcome.failures.append(RemovalFailure(
                    path: target.path,
                    reason: (error as NSError).localizedDescription))
            }
        }
        onProgress("", targets.count, targets.count)
        return outcome
    }
}
