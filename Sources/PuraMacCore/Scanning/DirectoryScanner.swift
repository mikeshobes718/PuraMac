import Foundation

public struct SizedEntry: Sendable, Hashable, Identifiable {
    public var path: String
    public var bytes: Int64
    public var modified: Date
    public var isDirectory: Bool

    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }

    public init(path: String, bytes: Int64, modified: Date = .distantPast, isDirectory: Bool = false) {
        self.path = path
        self.bytes = bytes
        self.modified = modified
        self.isDirectory = isDirectory
    }
}

public struct DirectoryMeasurement: Sendable {
    public var bytes: Int64 = 0
    public var fileCount: Int = 0
    /// Largest immediate children of the scanned root, biggest first.
    public var breakdown: [SizedEntry] = []

    public init() {}
}

/// One-pass directory measurement.
///
/// The prefetched resource keys let Foundation batch the `getattrlistbulk`
/// calls, so this costs roughly one syscall per directory rather than the three
/// per file that `attributesOfItem` would need.
public enum DirectoryScanner {

    static let sizeKeys: [URLResourceKey] = [
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .isDirectoryKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .fileSizeKey,
        .contentModificationDateKey
    ]

    /// Physical bytes the file occupies, which is what actually comes back when
    /// it is removed. Falls back to logical size for volumes that do not report
    /// allocation.
    static func allocatedSize(_ values: URLResourceValues) -> Int64 {
        if let total = values.totalFileAllocatedSize { return Int64(total) }
        if let allocated = values.fileAllocatedSize { return Int64(allocated) }
        if let logical = values.fileSize { return Int64(logical) }
        return 0
    }

    public static func measure(
        root: String,
        breakdownLimit: Int = 8,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) throws -> DirectoryMeasurement {
        var result = DirectoryMeasurement()
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root, isDirectory: &isDir) else { return result }

        let rootURL = URL(fileURLWithPath: root)
        guard isDir.boolValue else {
            if let values = try? rootURL.resourceValues(forKeys: Set(sizeKeys)) {
                result.bytes = allocatedSize(values)
                result.fileCount = 1
            }
            return result
        }

        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: sizeKeys,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return result }

        try Task.checkCancellation()
        var perChild: [String: Int64] = [:]
        var childDates: [String: Date] = [:]
        var childIsDir: [String: Bool] = [:]
        var childPaths: [String: String] = [:]
        // Attribution uses the enumerator's depth rather than a path-string prefix,
        // because a root under a symlinked parent (/var vs /private/var) yields
        // URLs that do not literally begin with the path we passed in.
        var currentBucket: String?
        var seen = 0

        for case let url as URL in enumerator {
            seen += 1
            if seen & 0x3FF == 0 {
                try Task.checkCancellation()
                onProgress?(seen)
            }
            guard let values = try? url.resourceValues(forKeys: Set(sizeKeys)) else { continue }

            if enumerator.level == 1 {
                let name = url.lastPathComponent
                currentBucket = name
                childPaths[name] = url.path
                childIsDir[name] = values.isDirectory == true
            }

            if values.isSymbolicLink == true { continue }
            guard values.isRegularFile == true else { continue }

            let size = allocatedSize(values)
            result.bytes += size
            result.fileCount += 1

            guard let bucket = currentBucket else { continue }
            perChild[bucket, default: 0] += size
            if let modified = values.contentModificationDate {
                let existing = childDates[bucket] ?? .distantPast
                if modified > existing { childDates[bucket] = modified }
            }
        }

        try Task.checkCancellation()
        onProgress?(seen)

        result.breakdown = perChild
            .map { name, bytes in
                SizedEntry(
                    path: childPaths[name] ?? (rootURL.path + "/" + name),
                    bytes: bytes,
                    modified: childDates[name] ?? .distantPast,
                    isDirectory: childIsDir[name] ?? false
                )
            }
            .sorted { $0.bytes > $1.bytes }
            .prefix(breakdownLimit)
            .map { $0 }

        return result
    }

    /// Immediate children of a directory with their own recursive sizes.
    public static func children(of root: String) throws -> [SizedEntry] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root) else { return [] }
        var out: [SizedEntry] = []
        out.reserveCapacity(names.count)
        for name in names {
            try Task.checkCancellation()
            let full = root + "/" + name
            let url = URL(fileURLWithPath: full)
            guard let values = try? url.resourceValues(forKeys: Set(sizeKeys)) else { continue }
            let isDirectory = values.isDirectory == true
            let bytes = isDirectory ? (try measure(root: full, breakdownLimit: 0).bytes) : allocatedSize(values)
            out.append(SizedEntry(
                path: full,
                bytes: bytes,
                modified: values.contentModificationDate ?? .distantPast,
                isDirectory: isDirectory
            ))
        }
        return out.sorted { $0.bytes > $1.bytes }
    }

    /// Size of a single item, used to report how much a removal actually freed.
    public static func size(of path: String) -> Int64 {
        (try? measure(root: path, breakdownLimit: 0).bytes) ?? 0
    }
}
