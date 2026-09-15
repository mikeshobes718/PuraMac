import Foundation

public enum Format {
    public static func bytes(_ value: Int64) -> String {
        max(0, value).formatted(.byteCount(style: .file))
    }

    public static func count(_ value: Int, singular: String, plural: String? = nil) -> String {
        let word = value == 1 ? singular : (plural ?? singular + "s")
        return "\(value.formatted(.number.grouping(.automatic))) \(word)"
    }

    public static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    /// Replaces the home prefix with `~` so paths stay readable and screenshots
    /// don't leak the account name.
    public static func abbreviate(_ path: String, home: String = NSHomeDirectory()) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
