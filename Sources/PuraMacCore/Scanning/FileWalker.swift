import Foundation

public enum FileWalker {

    /// Folders that are never worth walking: rebuildable, enormous, or opaque
    /// bundles whose internals are not separately actionable.
    public static let skippedNames: Set<String> = [
        "node_modules", ".git", ".svn", ".build", "DerivedData",
        "Library", ".Trash", "Photos Library.photoslibrary"
    ]

    public static let skippedExtensions: Set<String> = [
        "photoslibrary", "musiclibrary", "tvlibrary", "aplibrary", "fcpbundle", "logicx"
    ]

    public static func defaultRoots(home: String = NSHomeDirectory()) -> [String] {
        ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"]
            .map { home + "/" + $0 }
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    public static func files(
        under root: String,
        minimumBytes: Int64 = 0,
        limit: Int? = nil,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) throws -> [SizedEntry] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: DirectoryScanner.sizeKeys,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var results: [SizedEntry] = []
        var seen = 0

        for case let url as URL in enumerator {
            seen += 1
            if seen & 0x1FF == 0 {
                try Task.checkCancellation()
                onProgress?(seen)
            }

            let name = url.lastPathComponent
            if skippedNames.contains(name) || skippedExtensions.contains(url.pathExtension.lowercased()) {
                enumerator.skipDescendants()
                continue
            }

            guard let values = try? url.resourceValues(forKeys: Set(DirectoryScanner.sizeKeys)) else { continue }
            if values.isSymbolicLink == true { continue }
            guard values.isRegularFile == true else { continue }

            let size = DirectoryScanner.allocatedSize(values)
            guard size >= minimumBytes else { continue }

            results.append(SizedEntry(
                path: url.path,
                bytes: size,
                modified: values.contentModificationDate ?? .distantPast))

            if let limit, results.count >= limit * 4 { break }
        }

        results.sort { $0.bytes > $1.bytes }
        if let limit, results.count > limit {
            results = Array(results.prefix(limit))
        }
        return results
    }
}

public struct LargeFileQuery: Sendable {
    public var minimumBytes: Int64
    public var roots: [String]
    public var limit: Int
    public var olderThanDays: Int?

    public init(
        minimumBytes: Int64 = 100_000_000,
        roots: [String] = FileWalker.defaultRoots(),
        limit: Int = 300,
        olderThanDays: Int? = nil
    ) {
        self.minimumBytes = minimumBytes
        self.roots = roots
        self.limit = limit
        self.olderThanDays = olderThanDays
    }
}

public enum LargeFileScanner {
    public static func scan(
        _ query: LargeFileQuery,
        onProgress: @escaping @Sendable (String) -> Void = { _ in }
    ) throws -> [SizedEntry] {
        var all: [SizedEntry] = []
        for root in query.roots {
            try Task.checkCancellation()
            onProgress("Searching \((root as NSString).lastPathComponent)…")
            all += try FileWalker.files(under: root, minimumBytes: query.minimumBytes)
        }
        if let days = query.olderThanDays {
            let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
            all = all.filter { $0.modified < cutoff }
        }
        all.sort { $0.bytes > $1.bytes }
        return Array(all.prefix(query.limit))
    }
}
