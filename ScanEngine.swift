import Foundation

struct CleanGroup {
    let id: String
    let title: String
    let detail: String
    let defaultChecked: Bool
    var paths: [String] = []
    var totalBytes: Int64 = 0
    var fileCount = 0
    var checked: Bool
    var skippedNote: String?

    init(id: String, title: String, detail: String, defaultChecked: Bool) {
        self.id = id
        self.title = title
        self.detail = detail
        self.defaultChecked = defaultChecked
        self.checked = defaultChecked
        self.skippedNote = nil
    }
}

struct LargeFileItem {
    var path: String
    var sizeBytes: Int64
    var modified: Date
}

enum CleanTargets {
    static let rootPaths: [String: String] = [
        "caches": "~/Library/Caches",
        "logs": "~/Library/Logs",
        "deriveddata": "~/Library/Developer/Xcode/DerivedData",
        "devicesupport": "~/Library/Developer/Xcode/iOS DeviceSupport",
        "npmcache": "~/.npm/_cacache",
        "dotcache": "~/.cache",
        "trash": "~/.Trash"
    ]

    static func expandedRoot(for id: String) -> String {
        if let tilde = rootPaths[id] {
            return (tilde as NSString).expandingTildeInPath
        }
        if id == "brewcache" {
            return BrewCacheLocator.cachedPath() ?? ""
        }
        return ""
    }
}

final class ScanEngine {
    static let shared = ScanEngine()

    private let fm = FileManager.default

    func scanCleanGroups(progress: @escaping (String) -> Void) -> [CleanGroup] {
        var groups: [CleanGroup] = []
        groups.append(scanDirectoryGroup(id: "caches", title: "User caches",
            detail: "Per-app caches in ~/Library/Caches", defaultChecked: true, progress: progress))
        groups.append(scanDirectoryGroup(id: "logs", title: "User logs",
            detail: "Log files in ~/Library/Logs", defaultChecked: true, progress: progress))
        groups.append(scanTrash(progress: progress))
        groups.append(scanDirectoryGroup(id: "deriveddata", title: "Xcode DerivedData",
            detail: "Build products and indexes, safe to rebuild", defaultChecked: true, progress: progress))
        groups.append(scanDirectoryGroup(id: "devicesupport", title: "iOS DeviceSupport",
            detail: "Device symbol files, safe to rebuild", defaultChecked: false, progress: progress))
        groups.append(scanDirectoryGroup(id: "npmcache", title: "npm cache",
            detail: "Package download cache in ~/.npm/_cacache", defaultChecked: true, progress: progress))
        groups.append(scanDirectoryGroup(id: "dotcache", title: "Hidden user cache",
            detail: "Misc tooling caches in ~/.cache", defaultChecked: true, progress: progress))
        groups.append(scanBrewCache(progress: progress))
        groups.append(scanOldDownloads(progress: progress))
        return groups
    }

    private func scanDirectoryGroup(id: String, title: String, detail: String, defaultChecked: Bool, progress: @escaping (String) -> Void) -> CleanGroup {
        var group = CleanGroup(id: id, title: title, detail: detail, defaultChecked: defaultChecked)
        let root = CleanTargets.expandedRoot(for: id)
        guard !root.isEmpty, fm.fileExists(atPath: root) else {
            group.skippedNote = "Not present on this Mac"
            return group
        }
        progress("Scanning \(title)...")
        let measured = measureRoot(root: root, progress: progress)
        group.totalBytes = measured.bytes
        group.fileCount = measured.count
        group.paths = measured.samples
        return group
    }

    private func measureRoot(root: String, progress: @escaping (String) -> Void) -> (bytes: Int64, count: Int, samples: [String]) {
        var total: Int64 = 0
        var count = 0
        var samples: [String] = []
        guard let enumerator = fm.enumerator(atPath: root) else { return (0, 0, []) }
        let label = (root as NSString).lastPathComponent
        while let rel = enumerator.nextObject() as? String {
            if count % 500 == 0 {
                progress("Scanning \(label): \(count) items")
            }
            let full = root + "/" + rel
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue else { continue }
            guard let attrs = try? fm.attributesOfItem(atPath: full),
                  let raw = attrs[.size] as? NSNumber else { continue }
            total += raw.int64Value
            count += 1
            if samples.count < 6 && raw.int64Value > 8_000_000 {
                samples.append(full)
            }
        }
        if samples.isEmpty {
            for entry in topLevelEntries(root: root) {
                let sized = quickSize(path: entry.path)
                if sized.bytes > 50_000_000 {
                    samples.append(entry.path)
                    if samples.count >= 6 { break }
                }
            }
        }
        return (total, count, samples)
    }

    private func scanTrash(progress: @escaping (String) -> Void) -> CleanGroup {
        var group = CleanGroup(id: "trash", title: "Trash",
            detail: "Everything currently sitting in the Trash", defaultChecked: false)
        let trash = CleanTargets.expandedRoot(for: "trash")
        guard fm.fileExists(atPath: trash) else {
            group.skippedNote = "Not present on this Mac"
            return group
        }
        progress("Scanning Trash...")
        var total: Int64 = 0
        var count = 0
        var samples: [String] = []
        for entry in topLevelEntries(root: trash) {
            let sized = quickSize(path: entry.path)
            total += sized.bytes
            count += max(1, sized.count)
            if samples.count < 6 {
                samples.append(entry.path)
            }
        }
        group.totalBytes = total
        group.fileCount = count
        group.paths = samples
        return group
    }

    private func scanBrewCache(progress: @escaping (String) -> Void) -> CleanGroup {
        var group = CleanGroup(id: "brewcache", title: "Homebrew cache",
            detail: "Downloaded installers and sources kept by brew", defaultChecked: true)
        guard let root = BrewCacheLocator.locate(), fm.fileExists(atPath: root) else {
            group.skippedNote = "Homebrew not installed"
            return group
        }
        progress("Scanning Homebrew cache...")
        let measured = measureRoot(root: root, progress: progress)
        group.totalBytes = measured.bytes
        group.fileCount = measured.count
        group.paths = measured.samples
        return group
    }

    private func scanOldDownloads(progress: @escaping (String) -> Void) -> CleanGroup {
        var group = CleanGroup(id: "downloads", title: "Downloads older than 30 days",
            detail: "Files in Downloads untouched for a month, listed individually", defaultChecked: false)
        let downloads = ("~/Downloads" as NSString).expandingTildeInPath
        guard fm.fileExists(atPath: downloads) else {
            group.skippedNote = "Not present on this Mac"
            return group
        }
        progress("Scanning Downloads...")
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        let entries = topLevelEntries(root: downloads).sorted { $0.modified > $1.modified }
        for entry in entries {
            guard entry.modified < cutoff else { continue }
            let sized = quickSize(path: entry.path)
            group.totalBytes += sized.bytes
            group.fileCount += 1
            group.paths.append(entry.path)
        }
        return group
    }

    private func topLevelEntries(root: String) -> [(path: String, modified: Date)] {
        guard let contents = try? fm.contentsOfDirectory(atPath: root) else { return [] }
        var out: [(String, Date)] = []
        for name in contents {
            let full = root + "/" + name
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }
            let mod = (try? fm.attributesOfItem(atPath: full)[.modificationDate] as? Date) ?? nil
            out.append((full, mod ?? .distantPast))
        }
        return out
    }

    private func quickSize(path: String) -> (bytes: Int64, count: Int) {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return (0, 0) }
        if !isDir.boolValue {
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let raw = attrs[.size] as? NSNumber else { return (0, 0) }
            return (raw.int64Value, 1)
        }
        var total: Int64 = 0
        var count = 0
        guard let enumerator = fm.enumerator(atPath: path) else { return (0, 0) }
        while let rel = enumerator.nextObject() as? String {
            let full = path + "/" + rel
            var inner: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &inner), !inner.boolValue else { continue }
            guard let attrs = try? fm.attributesOfItem(atPath: full),
                  let raw = attrs[.size] as? NSNumber else { continue }
            total += raw.int64Value
            count += 1
        }
        return (total, count)
    }

    func clean(groups: [CleanGroup], progress: @escaping (String) -> Void) -> (freedBytes: Int64, failedCount: Int) {
        var freed: Int64 = 0
        var failed = 0
        for group in groups where group.checked {
            let targets: [String]
            switch group.id {
            case "downloads":
                targets = group.paths
            case "brewcache":
                targets = topLevelEntries(root: CleanTargets.expandedRoot(for: "brewcache")).map { $0.path }
            default:
                targets = topLevelEntries(root: CleanTargets.expandedRoot(for: group.id)).map { $0.path }
            }
            for target in targets {
                progress("Moving \((target as NSString).lastPathComponent) to Trash...")
                let sized = quickSize(path: target)
                do {
                    var resultingURL: NSURL?
                    try fm.trashItem(at: URL(fileURLWithPath: target), resultingItemURL: &resultingURL)
                    freed += sized.bytes
                } catch {
                    failed += 1
                }
            }
        }
        return (freed, failed)
    }
}

enum BrewCacheLocator {
    private static var cached: String?

    static func cachedPath() -> String? {
        if let c = cached { return c }
        let p = locate()
        cached = p
        return p
    }

    static func locate() -> String? {
        let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        for exe in candidates {
            guard FileManager.default.isExecutableFile(atPath: exe) else { continue }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: exe)
            task.arguments = ["--cache"]
            var env = ProcessInfo.processInfo.environment
            env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            task.environment = env
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
            } catch {
                continue
            }
            let deadline = Date().addingTimeInterval(15)
            while task.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if task.isRunning {
                task.terminate()
                continue
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard task.terminationStatus == 0 else { continue }
            let trimmed = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}

final class LargeFileScanner {
    private let fm = FileManager.default

    func scan(minimumBytes: Int64, progress: @escaping (String) -> Void) -> [LargeFileItem] {
        var results: [LargeFileItem] = []
        let home = NSHomeDirectory()
        for dir in topScanDirs(home: home) {
            progress("Searching \(dir.lastPathComponent)...")
            guard let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .contentModificationDateKey, .isSymbolicLinkKey],
                options: [],
                errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in enumerator {
                let name = url.lastPathComponent
                if name.hasPrefix(".") {
                    if url.deletingLastPathComponent().path == home || name == ".git" {
                        enumerator.skipDescendants()
                        continue
                    }
                }
                if name == "node_modules" {
                    enumerator.skipDescendants()
                    continue
                }
                guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey]) else { continue }
                if values.isSymbolicLink == true { continue }
                if values.isRegularFile != true { continue }
                let size = Int64(values.fileSize ?? 0)
                if size < minimumBytes { continue }
                results.append(LargeFileItem(path: url.path, sizeBytes: size, modified: values.contentModificationDate ?? .distantPast))
            }
        }
        results.sort { $0.sizeBytes > $1.sizeBytes }
        if results.count > 50 {
            results = Array(results.prefix(50))
        }
        return results
    }

    private func topScanDirs(home: String) -> [URL] {
        var dirs: [URL] = []
        for name in ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public"] {
            let full = home + "/" + name
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue {
                dirs.append(URL(fileURLWithPath: full))
            }
        }
        for sub in ["Library/Caches", "Library/Logs", "Library/Developer"] {
            let full = home + "/" + sub
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue {
                dirs.append(URL(fileURLWithPath: full))
            }
        }
        return dirs
    }
}
