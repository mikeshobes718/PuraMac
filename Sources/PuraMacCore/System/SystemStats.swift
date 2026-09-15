import Foundation
import Darwin
import IOKit.ps

public struct DiskInfo: Sendable, Equatable {
    public var name: String = ""
    public var totalBytes: Int64 = 0
    public var freeBytes: Int64 = 0
    public var isValid = false

    public init() {}

    public var usedBytes: Int64 { max(0, totalBytes - freeBytes) }
    public var usedFraction: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0 }
    public var freeFraction: Double { totalBytes > 0 ? Double(freeBytes) / Double(totalBytes) : 0 }
}

public enum MemoryPressure: String, Sendable {
    case normal, warning, critical, unknown

    public var label: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Elevated"
        case .critical: return "Critical"
        case .unknown: return "Unknown"
        }
    }
}

public struct MemoryInfo: Sendable, Equatable {
    public var totalBytes: Int64 = 0
    public var usedBytes: Int64 = 0
    public var appBytes: Int64 = 0
    public var wiredBytes: Int64 = 0
    public var compressedBytes: Int64 = 0
    public var cachedBytes: Int64 = 0
    public var swapUsedBytes: Int64 = 0
    public var pressure: MemoryPressure = .unknown

    public init() {}

    public var usedFraction: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0 }
}

public struct CPUInfo: Sendable, Equatable {
    public var usageFraction: Double = 0
    public var userFraction: Double = 0
    public var systemFraction: Double = 0
    public var coreCount: Int = 0
    public var thermalState: String = "Nominal"

    public init() {}
}

public struct BatteryInfo: Sendable, Equatable {
    public var isPresent = false
    public var percent = 0
    public var isCharging = false
    public var isOnAC = false
    public var healthLabel: String?
    public var timeRemainingMinutes: Int?

    public init() {}

    public var summary: String {
        guard isPresent else { return "No battery" }
        if isCharging { return "Charging" }
        if isOnAC { return "On power adapter" }
        if let minutes = timeRemainingMinutes, minutes > 0 {
            return "\(minutes / 60)h \(minutes % 60)m remaining"
        }
        return "On battery"
    }
}

public enum SystemStats {

    // MARK: Disk

    public static func bootDisk() -> DiskInfo {
        var info = DiskInfo()
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeNameKey
        ]) else { return info }

        info.name = values.volumeName ?? "Macintosh HD"
        info.totalBytes = Int64(values.volumeTotalCapacity ?? 0)
        // "Important usage" is what Finder reports: it counts purgeable space the
        // system would reclaim under pressure, so it matches what users see.
        info.freeBytes = values.volumeAvailableCapacityForImportantUsage
            ?? Int64(values.volumeAvailableCapacity ?? 0)
        info.isValid = info.totalBytes > 0
        return info
    }

    // MARK: Memory

    public static func memory() -> MemoryInfo {
        var info = MemoryInfo()
        info.totalBytes = Int64(ProcessInfo.processInfo.physicalMemory)

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return info }

        var pageSize: vm_size_t = 0
        host_page_size(host, &pageSize)
        let page = Int64(pageSize)

        info.wiredBytes = Int64(stats.wire_count) * page
        info.compressedBytes = Int64(stats.compressor_page_count) * page
        info.appBytes = Int64(stats.internal_page_count - stats.purgeable_count) * page
        info.cachedBytes = Int64(stats.external_page_count + stats.purgeable_count) * page
        info.usedBytes = info.appBytes + info.wiredBytes + info.compressedBytes
        info.swapUsedBytes = swapUsed()
        info.pressure = pressureLevel(fallbackFraction: info.usedFraction)
        return info
    }

    /// The kernel's own pressure signal, which is what Activity Monitor shows —
    /// a used-percentage heuristic disagrees with it often enough to mislead.
    private static func pressureLevel(fallbackFraction: Double) -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            switch level {
            case 1: return .normal
            case 2: return .warning
            case 4: return .critical
            default: break
            }
        }
        switch fallbackFraction {
        case ..<0.70: return .normal
        case ..<0.88: return .warning
        default: return .critical
        }
    }

    private static func swapUsed() -> Int64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return Int64(usage.xsu_used)
    }

    // MARK: CPU

    private struct CPUTicks {
        var user: UInt64 = 0
        var nice: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var cores: Int = 0
        var busy: UInt64 { user &+ nice &+ system }
        var total: UInt64 { busy &+ idle }
    }

    /// Sampled over a real interval — a single reading only yields uptime averages.
    public static func cpu(sampleInterval: Duration = .milliseconds(400)) async -> CPUInfo {
        var info = CPUInfo()
        info.thermalState = thermalStateLabel()
        let first = cpuTicks()
        guard first.cores > 0 else { return info }
        try? await Task.sleep(for: sampleInterval)
        let second = cpuTicks()
        guard second.cores > 0 else { return info }

        let deltaTotal = second.total &- first.total
        info.coreCount = second.cores
        guard deltaTotal > 0 else { return info }

        info.userFraction = Double((second.user &+ second.nice) &- (first.user &+ first.nice)) / Double(deltaTotal)
        info.systemFraction = Double(second.system &- first.system) / Double(deltaTotal)
        info.usageFraction = Double(second.busy &- first.busy) / Double(deltaTotal)
        return info
    }

    private static func cpuTicks() -> CPUTicks {
        var processorCount: natural_t = 0
        var loads: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &processorCount, &loads, &infoCount) == KERN_SUCCESS,
              let pointer = loads else { return CPUTicks() }

        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: pointer),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }
        var ticks = CPUTicks()
        ticks.cores = Int(processorCount)
        for index in 0..<Int(processorCount) {
            let base = index * Int(CPU_STATE_MAX)
            ticks.user &+= UInt64(pointer[base + Int(CPU_STATE_USER)])
            ticks.nice &+= UInt64(pointer[base + Int(CPU_STATE_NICE)])
            ticks.system &+= UInt64(pointer[base + Int(CPU_STATE_SYSTEM)])
            ticks.idle &+= UInt64(pointer[base + Int(CPU_STATE_IDLE)])
        }
        return ticks
    }

    private static func thermalStateLabel() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    // MARK: Battery

    public static func battery() -> BatteryInfo {
        var info = BatteryInfo()
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return info
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int else { continue }

            info.isPresent = true
            info.percent = current
            let state = description[kIOPSPowerSourceStateKey] as? String ?? ""
            info.isOnAC = state == kIOPSACPowerValue
            info.isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            info.healthLabel = description[kIOPSBatteryHealthKey] as? String
            let key = info.isOnAC ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            if let minutes = description[key] as? Int, minutes > 0 {
                info.timeRemainingMinutes = minutes
            }
            break
        }
        return info
    }

    // MARK: Host

    public static func osVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var text = "macOS \(version.majorVersion).\(version.minorVersion)"
        if version.patchVersion > 0 { text += ".\(version.patchVersion)" }
        return text
    }

    public static func uptime() -> String {
        Format.duration(ProcessInfo.processInfo.systemUptime)
    }

    public static func modelIdentifier() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "Mac" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "Mac" }
        let raw = bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: raw, as: UTF8.self)
    }
}
