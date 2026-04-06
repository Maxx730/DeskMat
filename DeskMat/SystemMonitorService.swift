import Foundation
import Darwin

@Observable class SystemMonitorService {
    var cpuPercent: Double = 0
    var ramUsedGB: Double = 0
    let ramTotalGB: Double = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    var netInKBs: Double = 0
    var netOutKBs: Double = 0

    private var timer: Timer?
    private var lastCPUTicks: CPUTicks?
    private var lastNetSample: NetworkSample?

    func start() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        updateCPU()
        updateRAM()
        updateNetwork()
    }

    // MARK: - CPU

    private struct CPUTicks {
        var user: UInt32
        var system: UInt32
        var idle: UInt32
        var nice: UInt32
        var total: UInt32 { user + system + idle + nice }
    }

    private func updateCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let current = CPUTicks(
            user:   info.cpu_ticks.0,
            system: info.cpu_ticks.1,
            idle:   info.cpu_ticks.2,
            nice:   info.cpu_ticks.3
        )

        if let last = lastCPUTicks {
            let deltaUser   = current.user   &- last.user
            let deltaSystem = current.system &- last.system
            let deltaIdle   = current.idle   &- last.idle
            let deltaNice   = current.nice   &- last.nice
            let deltaTotal  = deltaUser + deltaSystem + deltaIdle + deltaNice
            if deltaTotal > 0 {
                cpuPercent = Double(deltaUser + deltaSystem) / Double(deltaTotal)
            }
        }
        lastCPUTicks = current
    }

    // MARK: - RAM

    private func updateRAM() {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let pageSize = UInt64(vm_kernel_page_size)
        let usedPages = UInt64(info.active_count) + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
        ramUsedGB = Double(usedPages * pageSize) / 1_073_741_824
    }

    // MARK: - Network

    private struct NetworkSample {
        var bytesIn: UInt64
        var bytesOut: UInt64
        var timestamp: Date
    }

    private func updateNetwork() {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0 else { return }
        defer { freeifaddrs(ifap) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var ptr = ifap

        while let ifa = ptr?.pointee {
            defer { ptr = ifa.ifa_next }

            // Only link-layer entries carry if_data byte counters
            guard ifa.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) else { continue }
            // Skip loopback
            guard Int32(ifa.ifa_flags) & IFF_LOOPBACK == 0 else { continue }
            // Skip interfaces that are down
            guard Int32(ifa.ifa_flags) & IFF_UP != 0 else { continue }

            guard let data = ifa.ifa_data else { continue }
            let ifdata = data.assumingMemoryBound(to: if_data.self).pointee
            totalIn  += UInt64(ifdata.ifi_ibytes)
            totalOut += UInt64(ifdata.ifi_obytes)
        }

        let now = Date()
        if let last = lastNetSample {
            let elapsed = now.timeIntervalSince(last.timestamp)
            guard elapsed > 0 else { return }
            // Clamp deltas to 0 in case an interface disappeared and counters dropped
            let deltaIn  = totalIn  >= last.bytesIn  ? totalIn  - last.bytesIn  : 0
            let deltaOut = totalOut >= last.bytesOut ? totalOut - last.bytesOut : 0
            netInKBs  = Double(deltaIn)  / elapsed / 1024
            netOutKBs = Double(deltaOut) / elapsed / 1024
        }
        lastNetSample = NetworkSample(bytesIn: totalIn, bytesOut: totalOut, timestamp: now)
    }
}
