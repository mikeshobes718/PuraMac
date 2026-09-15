import Foundation

public struct LoginItem: Sendable, Identifiable, Hashable {
    public var label: String
    public var plistPath: String
    public var program: String?
    public var runAtLoad: Bool
    public var isAppleProvided: Bool

    public var id: String { plistPath }
    public var displayName: String {
        program.map { ($0 as NSString).lastPathComponent } ?? label
    }
}

public enum LoginItems {

    public static func scan(home: String = NSHomeDirectory()) -> [LoginItem] {
        let root = home + "/Library/LaunchAgents"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root) else { return [] }

        var items: [LoginItem] = []
        for name in names where name.hasSuffix(".plist") {
            let path = root + "/" + name
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                items.append(LoginItem(
                    label: (name as NSString).deletingPathExtension,
                    plistPath: path, program: nil, runAtLoad: false, isAppleProvided: false))
                continue
            }
            let label = plist["Label"] as? String ?? (name as NSString).deletingPathExtension
            let program = (plist["Program"] as? String)
                ?? (plist["ProgramArguments"] as? [String])?.first
            items.append(LoginItem(
                label: label,
                plistPath: path,
                program: program,
                runAtLoad: (plist["RunAtLoad"] as? Bool) ?? false,
                isAppleProvided: label.hasPrefix("com.apple.")))
        }
        return items.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Disabling moves the job definition to the Trash rather than deleting it,
    /// so a login item removed by mistake can be put straight back.
    public static func disable(_ items: [LoginItem], home: String = NSHomeDirectory()) throws -> RemovalOutcome {
        try Trasher.remove(
            items.map { RemovalRequest(path: $0.plistPath, knownBytes: DirectoryScanner.size(of: $0.plistPath)) },
            style: .trash,
            home: home)
    }
}
