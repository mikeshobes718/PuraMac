import Foundation
import OSLog

public enum Log {
    public static let scan = Logger(subsystem: subsystem, category: "scan")
    public static let clean = Logger(subsystem: subsystem, category: "clean")
    public static let system = Logger(subsystem: subsystem, category: "system")
    public static let ai = Logger(subsystem: subsystem, category: "ai")
    public static let app = Logger(subsystem: subsystem, category: "app")

    private static let subsystem = "com.mikeshobes.PuraMac"
}
