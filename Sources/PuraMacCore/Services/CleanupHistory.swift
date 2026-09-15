import Foundation

public struct CleanupRecord: Sendable, Codable, Identifiable, Equatable {
    public var id: UUID
    public var date: Date
    public var summary: String
    public var freedBytes: Int64
    public var items: [RemovedItem]

    public var canUndo: Bool { items.contains { $0.trashPath != nil } }

    public init(id: UUID = UUID(), date: Date = Date(), summary: String, freedBytes: Int64, items: [RemovedItem]) {
        self.id = id
        self.date = date
        self.summary = summary
        self.freedBytes = freedBytes
        self.items = items
    }
}

/// Append-only log of everything PuraMac has removed, so a cleanup is auditable
/// after the fact and recent ones can be reversed.
public actor CleanupHistory {
    public static let shared = CleanupHistory()

    private let limit = 50
    private let fileURL: URL
    private var cached: [CleanupRecord]?

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PuraMac", isDirectory: true)
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            self.fileURL = support.appendingPathComponent("cleanup-history.json")
        }
    }

    public func records() -> [CleanupRecord] {
        if let cached { return cached }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder.puraMac.decode([CleanupRecord].self, from: data) else {
            cached = []
            return []
        }
        cached = decoded
        return decoded
    }

    public func append(_ record: CleanupRecord) {
        var all = records()
        all.insert(record, at: 0)
        if all.count > limit { all = Array(all.prefix(limit)) }
        persist(all)
    }

    public func remove(id: UUID) {
        persist(records().filter { $0.id != id })
    }

    public func clear() {
        persist([])
    }

    private func persist(_ all: [CleanupRecord]) {
        cached = all
        guard let data = try? JSONEncoder.puraMac.encode(all) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension JSONEncoder {
    static let puraMac: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

extension JSONDecoder {
    static let puraMac: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
