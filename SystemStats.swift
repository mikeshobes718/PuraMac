import AppKit
import IOKit
import IOKit.ps
import Darwin

struct DiskInfo {
    var totalBytes: Int64 = 0
    var freeBytes: Int64 = 0
    var usedBytes: Int64 = 0
    var valid = false
}

struct MemoryInfo {
    var totalBytes: Int64 = 0
    var usedBytes: Int64 = 0
    var freeBytes: Int64 = 0
    var usedPercent: Double = 0
    var pressureLabel = "Unknown"
}

struct CPUInfo {
    var usagePercent: Double = 0
    var coreCount = 0
}

struct BatteryInfo {
    var present = false
    var percent = 0
    var charging = false
    var onAC = false
    var text = "No battery detected"
}

enum SystemStats {
    static func diskInfo() -> DiskInfo {
        var info = DiskInfo()
        let home = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? home.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) else {
            return info
        }
        info.totalBytes = Int64(values.volumeTotalCapacity ?? 0)
        info.freeBytes = values.volumeAvailableCapacityForImportantUsage ?? 0
        info.usedBytes = max(0, info.totalBytes - info.freeBytes)
        info.valid = info.totalBytes > 0
        return info
    }

    static func memoryInfo() -> MemoryInfo {
        var info = MemoryInfo()
        info.totalBytes = Int64(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(UInt32(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size))
        let host = mach_host_self()
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return info }
        var pageSize: vm_size_t = 0
        host_page_size(host, &pageSize)
        let page = UInt64(pageSize)
        let usedPages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        let freePages = UInt64(stats.free_count) + UInt64(stats.inactive_count) + UInt64(stats.purgeable_count) + UInt64(stats.speculative_count)
        info.usedBytes = Int64(usedPages * page)
        info.freeBytes = Int64(freePages * page)
        if info.totalBytes > 0 {
            info.usedPercent = Double(info.usedBytes) / Double(info.totalBytes)
        }
        switch info.usedPercent {
        case ..<0.55: info.pressureLabel = "Normal"
        case ..<0.80: info.pressureLabel = "Elevated"
        default: info.pressureLabel = "High"
        }
        return info
    }

    static func cpuUsage(completion: @escaping (CPUInfo) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let first = cpuSample() else {
                DispatchQueue.main.async { completion(CPUInfo()) }
                return
            }
            usleep(350_000)
            guard let second = cpuSample() else {
                DispatchQueue.main.async { completion(CPUInfo()) }
                return
            }
            let dUser = second.user >= first.user ? second.user - first.user : 0
            let dNice = second.nice >= first.nice ? second.nice - first.nice : 0
            let dSystem = second.system >= first.system ? second.system - first.system : 0
            let dIdle = second.idle >= first.idle ? second.idle - first.idle : 0
            let total = dUser + dNice + dSystem + dIdle
            var info = CPUInfo()
            info.coreCount = second.cores
            if total > 0 {
                info.usagePercent = Double(dUser + dNice + dSystem) / Double(total) * 100
            }
            DispatchQueue.main.async { completion(info) }
        }
    }

    private static func cpuSample() -> (user: UInt64, nice: UInt64, system: UInt64, idle: UInt64, cores: Int)? {
        var processorCount: natural_t = 0
        var loads: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        let host = mach_host_self()
        let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &processorCount, &loads, &count)
        guard result == KERN_SUCCESS, let ptr = loads else { return nil }
        defer {
            let size = vm_size_t(processorCount) * vm_size_t(CPU_STATE_MAX) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: ptr), size)
        }
        var user: UInt64 = 0
        var nice: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        for i in 0..<Int(processorCount) {
            let base = i * Int(CPU_STATE_MAX)
            user += UInt64(ptr[base + Int(CPU_STATE_USER)])
            nice += UInt64(ptr[base + Int(CPU_STATE_NICE)])
            system += UInt64(ptr[base + Int(CPU_STATE_SYSTEM)])
            idle += UInt64(ptr[base + Int(CPU_STATE_IDLE)])
        }
        return (user, nice, system, idle, Int(processorCount))
    }

    static func batteryInfo() -> BatteryInfo {
        var info = BatteryInfo()
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return info
        }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let capacity = desc[kIOPSCurrentCapacityKey] as? Int else { continue }
            info.present = true
            info.percent = capacity
            let state = desc[kIOPSPowerSourceStateKey] as? String ?? ""
            info.onAC = state == kIOPSACPowerValue
            info.charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            break
        }
        if info.present {
            var detail = "\(info.percent)%"
            if info.charging {
                detail += ", charging"
            } else if info.onAC {
                detail += ", on power"
            } else {
                detail += ", on battery"
            }
            info.text = detail
        }
        return info
    }

    static func uptimeText() -> String {
        let interval = ProcessInfo.processInfo.systemUptime
        let days = Int(interval) / 86400
        let hours = (Int(interval) % 86400) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }
        return "\(hours)h \(minutes)m"
    }

    static func osVersionText() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let base = "macOS \(v.majorVersion).\(v.minorVersion)"
        return v.patchVersion > 0 ? base + ".\(v.patchVersion)" : base
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: max(0, bytes))
    }
}
