import AppKit
import CCCore
import Darwin
import Foundation
import IOKit
import IOKit.ps

/// CPU (per core, E/P split), memory & pressure, GPU, thermals, battery,
/// network throughput, disk and the top processes — every 2 s while watched.
@MainActor
final class SystemProvider: PollingProvider {
    override var channels: Set<Channel> { [.system] }
    override var interval: TimeInterval { 2 }

    private let sampler = SystemSampler()

    override func tick() async {
        let sampler = sampler
        let stats = await Task.detached(priority: .utility) { sampler.sample() }.value
        Hub.shared.publish(.system(stats))
    }
}

/// Stateful sampler (keeps previous counters to compute rates). Only ever used
/// sequentially from one task at a time.
final class SystemSampler: @unchecked Sendable {
    private var previousCores: [(busy: UInt64, total: UInt64)] = []
    private var previousNet: (inBytes: UInt64, outBytes: UInt64, at: Date)?
    private var previousProcessTimes: [Int32: UInt64] = [:]
    private var previousProcessSample: Date?
    private let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(max(1, info.denom)))
    }()
    private let efficiencyCores: Int = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.perflevel1.logicalcpu", &value, &size, nil, 0) == 0 ? Int(value) : 0
    }()
    private let memTotal: UInt64 = ProcessInfo.processInfo.physicalMemory

    func sample() -> SystemStats {
        let cores = cpuCores()
        let cpu = cores.isEmpty ? 0 : cores.reduce(0, +) / Double(cores.count)
        let (used, pressure, swap) = memory()
        let (netIn, netOut) = network()
        let disk = diskSpace()
        return SystemStats(
            model: MacInfo.model,
            cpu: (cpu * 1000).rounded() / 1000,
            cpuCores: cores.map { ($0 * 100).rounded() / 100 },
            efficiencyCores: efficiencyCores,
            memUsed: used / 10_000_000 * 10_000_000,
            memTotal: memTotal,
            memPressure: pressure,
            swapUsed: swap,
            gpu: gpuUtilization(),
            thermal: thermal(),
            battery: battery(),
            netIn: (netIn / 1024).rounded() * 1024,
            netOut: (netOut / 1024).rounded() * 1024,
            diskFree: disk.free / 1_000_000_000 * 1_000_000_000,
            diskTotal: disk.total,
            uptime: ProcessInfo.processInfo.systemUptime.rounded(),
            topProcesses: topProcesses(),
            sampledAt: .now
        )
    }

    // MARK: CPU

    private func cpuCores() -> [Double] {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS, let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        var current: [(busy: UInt64, total: UInt64)] = []
        for core in 0..<Int(cpuCount) {
            let base = Int(CPU_STATE_MAX) * core
            let user = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            let system = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            let nice = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            let idle = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            current.append((user + system + nice, user + system + nice + idle))
        }
        defer { previousCores = current }
        guard previousCores.count == current.count else { return current.map { _ in 0 } }
        return zip(current, previousCores).map { now, before in
            let total = now.total &- before.total
            guard total > 0 else { return 0 }
            return min(1, Double(now.busy &- before.busy) / Double(total))
        }
    }

    // MARK: Memory

    private func memory() -> (used: UInt64, pressure: MemoryPressure, swap: UInt64) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var used: UInt64 = 0
        if result == KERN_SUCCESS {
            var pageSize: vm_size_t = 0
            host_page_size(mach_host_self(), &pageSize)
            let page = UInt64(pageSize)
            let app = UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count)
            used = (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        }
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        let pressure: MemoryPressure = level >= 4 ? .critical : (level == 2 ? .warning : .normal)
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)
        return (used, pressure, swap.xsu_used)
    }

    // MARK: GPU

    private func gpuUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] else { continue }
            if let utilization = stats["Device Utilization %"] as? Int {
                best = max(best ?? 0, Double(utilization) / 100)
            }
        }
        return best
    }

    // MARK: Thermal & battery

    private func thermal() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }

    private func battery() -> BatteryInfo? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let onAC = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let minutes = description[kIOPSTimeToEmptyKey] as? Int
            return BatteryInfo(level: Double(current) / Double(max(1, maximum)), isCharging: charging, onAC: onAC, minutesRemaining: (minutes ?? -1) > 0 ? minutes : nil)
        }
        return nil
    }

    // MARK: Network (64-bit counters via NET_RT_IFLIST2)

    private func network() -> (Double, Double) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return (0, 0) }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return (0, 0) }
        var inBytes: UInt64 = 0
        var outBytes: UInt64 = 0
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.load(fromByteOffset: offset, as: if_msghdr.self)
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let message = raw.load(fromByteOffset: offset, as: if_msghdr2.self)
                    if message.ifm_flags & IFF_LOOPBACK == 0 {
                        inBytes &+= message.ifm_data.ifi_ibytes
                        outBytes &+= message.ifm_data.ifi_obytes
                    }
                }
                offset += max(Int(header.ifm_msglen), 1)
            }
        }
        let now = Date()
        defer { previousNet = (inBytes, outBytes, now) }
        guard let previous = previousNet, inBytes >= previous.inBytes, outBytes >= previous.outBytes else { return (0, 0) }
        let elapsed = max(0.5, now.timeIntervalSince(previous.at))
        return (Double(inBytes - previous.inBytes) / elapsed, Double(outBytes - previous.outBytes) / elapsed)
    }

    private func diskSpace() -> (free: UInt64, total: UInt64) {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        return (UInt64(values?.volumeAvailableCapacityForImportantUsage ?? 0), UInt64(values?.volumeTotalCapacity ?? 0))
    }

    // MARK: Processes

    private func topProcesses() -> [ProcessUsage] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        var pids = [Int32](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<Int32>.size)))
        guard count > 0 else { return [] }
        let now = Date()
        let elapsedNs = previousProcessSample.map { UInt64(now.timeIntervalSince($0) * 1_000_000_000) } ?? 0
        var times: [Int32: UInt64] = [:]
        var usage: [(pid: Int32, cpu: Double, memory: UInt64)] = []
        for pid in pids.prefix(count) where pid > 0 {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { continue }
            let ticks = info.pti_total_user &+ info.pti_total_system
            let ns = ticks &* timebase.numer / timebase.denom
            times[pid] = ns
            if elapsedNs > 0, let before = previousProcessTimes[pid], ns >= before {
                let cpu = Double(ns - before) / Double(elapsedNs)
                if cpu > 0.005 { usage.append((pid, cpu, info.pti_resident_size)) }
            }
        }
        previousProcessTimes = times
        previousProcessSample = now
        return usage.sorted { $0.cpu > $1.cpu }.prefix(6).map { entry in
            let app = NSRunningApplication(processIdentifier: entry.pid)
            var nameBuffer = [CChar](repeating: 0, count: 256)
            proc_name(entry.pid, &nameBuffer, 256)
            let name = app?.localizedName ?? String(cString: nameBuffer)
            return ProcessUsage(pid: entry.pid, name: name.isEmpty ? "pid \(entry.pid)" : name, cpu: (entry.cpu * 1000).rounded() / 1000, memory: entry.memory / 1_000_000 * 1_000_000, bundleID: app?.bundleIdentifier)
        }
    }
}
