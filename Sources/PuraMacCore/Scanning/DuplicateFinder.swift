import Foundation
import CryptoKit

public struct DuplicateGroup: Sendable, Identifiable, Hashable {
    public var digest: String
    public var files: [SizedEntry]

    public var id: String { digest }
    public var fileSize: Int64 { files.first?.bytes ?? 0 }
    /// What could be reclaimed by keeping one copy.
    public var reclaimableBytes: Int64 { fileSize * Int64(max(0, files.count - 1)) }

    /// The oldest copy is treated as the original and pre-selected to keep.
    public var suggestedKeep: SizedEntry? {
        files.min { $0.modified < $1.modified }
    }
}

/// Three-stage pipeline: group by size, then compare a cheap head+tail digest,
/// and only fully hash the candidates that survive both. Hashing every file
/// outright would read the entire home folder for no reason.
public enum DuplicateFinder {

    public static func scan(
        roots: [String],
        minimumBytes: Int64 = 1_000_000,
        onProgress: @escaping @Sendable (String) -> Void = { _ in }
    ) throws -> [DuplicateGroup] {
        var bySize: [Int64: [SizedEntry]] = [:]

        for root in roots {
            try Task.checkCancellation()
            onProgress("Indexing \((root as NSString).lastPathComponent)…")
            for entry in try FileWalker.files(under: root, minimumBytes: minimumBytes) {
                bySize[entry.bytes, default: []].append(entry)
            }
        }

        let candidates = bySize.values.filter { $0.count > 1 }
        guard !candidates.isEmpty else { return [] }

        var byPartial: [String: [SizedEntry]] = [:]
        var examined = 0
        for group in candidates {
            for entry in group {
                try Task.checkCancellation()
                examined += 1
                if examined % 50 == 0 { onProgress("Comparing \(examined) possible duplicates…") }
                guard let partial = partialDigest(of: entry.path, size: entry.bytes) else { continue }
                byPartial["\(entry.bytes):\(partial)", default: []].append(entry)
            }
        }

        var results: [DuplicateGroup] = []
        for (_, group) in byPartial where group.count > 1 {
            var byFull: [String: [SizedEntry]] = [:]
            for entry in group {
                try Task.checkCancellation()
                onProgress("Verifying \((entry.path as NSString).lastPathComponent)…")
                guard let full = fullDigest(of: entry.path) else { continue }
                byFull[full, default: []].append(entry)
            }
            for (digest, matched) in byFull where matched.count > 1 {
                results.append(DuplicateGroup(
                    digest: digest,
                    files: matched.sorted { $0.modified < $1.modified }))
            }
        }

        return results.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    /// 64 KB from the front and back, which separates same-size-but-different
    /// files at a fraction of the cost of a full read.
    static func partialDigest(of path: String, size: Int64) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let window = 65_536
        var hasher = SHA256()
        guard let head = try? handle.read(upToCount: window) else { return nil }
        hasher.update(data: head)
        if size > Int64(window) * 2 {
            let offset = UInt64(size) - UInt64(window)
            if (try? handle.seek(toOffset: offset)) != nil,
               let tail = try? handle.read(upToCount: window) {
                hasher.update(data: tail)
            }
        }
        return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
    }

    static func fullDigest(of path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
    }
}
