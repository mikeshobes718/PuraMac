import Foundation

/// The single chokepoint every destructive operation must pass through.
///
/// PuraMac never deletes outright and never operates outside the user's home
/// directory. `PathGuard` is what makes that a guarantee rather than a habit:
/// every path handed to `Trasher` is validated here first, and a rejection is
/// a hard failure rather than a warning.
public enum PathGuard {

    public enum Rejection: Equatable, Sendable {
        case empty
        case notAbsolute
        case outsideHome(resolved: String)
        case isHomeItself
        case protectedDirectory(String)
        case systemPath
        case traversal

        public var reason: String {
            switch self {
            case .empty: return "Empty path"
            case .notAbsolute: return "Not an absolute path"
            case .outsideHome(let resolved): return "Outside your home folder (resolves to \(resolved))"
            case .isHomeItself: return "This is your home folder"
            case .protectedDirectory(let name): return "\(name) is protected — PuraMac only removes items inside it"
            case .systemPath: return "System location"
            case .traversal: return "Path contains a traversal component"
            }
        }
    }

    /// Top-level folders inside ~ that may have their *contents* cleaned but must
    /// never themselves be moved to the Trash.
    public static let protectedHomeChildren: Set<String> = [
        "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures",
        "Public", "Library", "Applications", "Sites", "Developer", ".Trash"
    ]

    /// Locations inside ~/Library that hold irreplaceable user data. Anything at
    /// or under these prefixes is refused even though it lives in the home folder.
    public static let protectedLibrarySubpaths: [String] = [
        "Library/Keychains",
        "Library/Mobile Documents",          // iCloud Drive
        "Library/Application Support/AddressBook",
        "Library/Application Support/MobileSync",   // iOS device backups
        "Library/Messages",
        "Library/Mail",
        "Library/Calendars",
        "Library/Safari",
        "Library/Preferences",
        "Library/Containers",
        "Library/Group Containers",
        "Library/CloudStorage",
        "Library/PersonalizationPortrait",
        "Library/Photos",
        "Library/Sharing"
    ]

    private static let systemPrefixes: [String] = [
        "/System", "/Library", "/usr", "/bin", "/sbin", "/etc", "/var", "/private/var",
        "/Applications", "/opt", "/cores", "/Volumes/Macintosh HD"
    ]

    public static func validate(_ path: String, home: String = NSHomeDirectory()) -> Rejection? {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .empty }
        guard path.hasPrefix("/") else { return .notAbsolute }
        if path.contains("/../") || path.hasSuffix("/..") { return .traversal }

        let normalizedHome = standardize(home)
        let literal = standardize(path)

        // Both the literal path and the symlink-resolved path must sit inside home,
        // so a symlinked cache folder cannot be used to reach outside it.
        let resolved = standardize(URL(fileURLWithPath: path).resolvingSymlinksInPath().path)

        for candidate in [literal, resolved] {
            if candidate == normalizedHome { return .isHomeItself }
            guard isInside(candidate, parent: normalizedHome) else {
                if systemPrefixes.contains(where: { isInside(candidate, parent: $0) || candidate == $0 }) {
                    return .systemPath
                }
                return .outsideHome(resolved: candidate)
            }
        }

        let relative = String(literal.dropFirst(normalizedHome.count + 1))
        let components = relative.split(separator: "/").map(String.init)
        guard let first = components.first else { return .isHomeItself }

        if components.count == 1, protectedHomeChildren.contains(first) {
            return .protectedDirectory(first)
        }

        for prefix in protectedLibrarySubpaths {
            if relative == prefix || relative.hasPrefix(prefix + "/") {
                return .protectedDirectory(prefix)
            }
        }

        return nil
    }

    public static func isSafe(_ path: String, home: String = NSHomeDirectory()) -> Bool {
        validate(path, home: home) == nil
    }

    /// Partitions a batch, so callers can report exactly what was refused and why
    /// instead of silently dropping paths.
    public static func partition(
        _ paths: [String],
        home: String = NSHomeDirectory()
    ) -> (allowed: [String], refused: [(path: String, rejection: Rejection)]) {
        var allowed: [String] = []
        var refused: [(String, Rejection)] = []
        for path in paths {
            if let rejection = validate(path, home: home) {
                refused.append((path, rejection))
            } else {
                allowed.append(path)
            }
        }
        return (allowed, refused)
    }

    private static func standardize(_ path: String) -> String {
        var value = (path as NSString).standardizingPath
        while value.count > 1 && value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    private static func isInside(_ path: String, parent: String) -> Bool {
        path.hasPrefix(parent + "/")
    }
}
