import Foundation

public struct RemovalRequest: Sendable, Equatable {
    public var path: String
    /// Size measured during the scan, reused so removal does not re-walk the tree.
    public var knownBytes: Int64

    public init(path: String, knownBytes: Int64) {
        self.path = path
        self.knownBytes = knownBytes
    }
}

public struct RemovedItem: Sendable, Codable, Equatable {
    public var originalPath: String
    /// Where it landed in the Trash, which is what makes Put Back possible.
    public var trashPath: String?
    public var bytes: Int64

    public init(originalPath: String, trashPath: String?, bytes: Int64) {
        self.originalPath = originalPath
        self.trashPath = trashPath
        self.bytes = bytes
    }
}

public struct RemovalFailure: Sendable, Equatable {
    public var path: String
    public var reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}

public struct RemovalOutcome: Sendable {
    public var removed: [RemovedItem] = []
    public var failures: [RemovalFailure] = []
    public var refused: [RemovalFailure] = []

    public init() {}

    public var freedBytes: Int64 { removed.reduce(0) { $0 + $1.bytes } }
    public var isFullySuccessful: Bool { failures.isEmpty && refused.isEmpty }
    public var canUndo: Bool { removed.contains { $0.trashPath != nil } }
}

public enum TrasherError: Error, LocalizedError {
    case permanentDeleteOutsideTrash(String)

    public var errorDescription: String? {
        switch self {
        case .permanentDeleteOutsideTrash(let path):
            return "Refused to permanently delete \(path): only the Trash may be emptied."
        }
    }
}

public enum Trasher {

    public static func remove(
        _ requests: [RemovalRequest],
        style: RemovalStyle,
        home: String = NSHomeDirectory(),
        onProgress: @escaping @Sendable (String, Int, Int) -> Void = { _, _, _ in }
    ) throws -> RemovalOutcome {
        var outcome = RemovalOutcome()
        guard style != .measureOnly else { return outcome }

        let fm = FileManager.default
        let trashRoot = (home as NSString).appendingPathComponent(".Trash")
        let total = requests.count

        for (index, request) in requests.enumerated() {
            try Task.checkCancellation()
            onProgress((request.path as NSString).lastPathComponent, index, total)

            // Re-validated here rather than trusting the scan: the guard is the
            // last thing that runs before anything is actually destroyed.
            if let rejection = PathGuard.validate(request.path, home: home) {
                outcome.refused.append(RemovalFailure(path: request.path, reason: rejection.reason))
                continue
            }

            guard fm.fileExists(atPath: request.path) else { continue }

            do {
                switch style {
                case .trash:
                    var resulting: NSURL?
                    try fm.trashItem(at: URL(fileURLWithPath: request.path), resultingItemURL: &resulting)
                    outcome.removed.append(RemovedItem(
                        originalPath: request.path,
                        trashPath: (resulting as URL?)?.path,
                        bytes: request.knownBytes
                    ))

                case .permanentDelete:
                    guard request.path.hasPrefix(trashRoot + "/") else {
                        throw TrasherError.permanentDeleteOutsideTrash(request.path)
                    }
                    try fm.removeItem(atPath: request.path)
                    outcome.removed.append(RemovedItem(
                        originalPath: request.path,
                        trashPath: nil,
                        bytes: request.knownBytes
                    ))

                case .measureOnly:
                    break
                }
            } catch {
                outcome.failures.append(RemovalFailure(
                    path: request.path,
                    reason: (error as NSError).localizedDescription
                ))
            }
        }

        onProgress("", total, total)
        Log.clean.info("Removed \(outcome.removed.count) items, freed \(outcome.freedBytes) bytes, \(outcome.failures.count) failures")
        return outcome
    }

    /// Moves items from the Trash back where they came from.
    public static func putBack(_ items: [RemovedItem]) -> RemovalOutcome {
        var outcome = RemovalOutcome()
        let fm = FileManager.default
        for item in items {
            guard let trashPath = item.trashPath, fm.fileExists(atPath: trashPath) else {
                outcome.failures.append(RemovalFailure(path: item.originalPath, reason: "No longer in the Trash"))
                continue
            }
            if fm.fileExists(atPath: item.originalPath) {
                outcome.failures.append(RemovalFailure(path: item.originalPath, reason: "Something already exists there"))
                continue
            }
            do {
                let parent = (item.originalPath as NSString).deletingLastPathComponent
                try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
                try fm.moveItem(atPath: trashPath, toPath: item.originalPath)
                outcome.removed.append(item)
            } catch {
                outcome.failures.append(RemovalFailure(
                    path: item.originalPath,
                    reason: (error as NSError).localizedDescription
                ))
            }
        }
        return outcome
    }
}
