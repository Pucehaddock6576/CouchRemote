// SystemInfo.swift — live facts about this Mac for the Big Screen widgets:
// battery (with real health and cycle count), charger and power, USB‑C / Thunderbolt ports and devices,
// CPU and memory, storage and network. Everything is read locally; nothing leaves the Mac.
import AppKit
import Combine
import IOKit
import IOKit.ps
import Darwin

struct BatteryDetails {
    var percent = 0
    var charging = false
    var pluggedIn = false
    var fullyCharged = false
    var minutesLeft: Int?                 // to empty, or to full while charging
    var cycleCount: Int?
    var designCapacity: Int?              // mAh when new
    var maxCapacity: Int?                 // mAh it holds now
    var health: Int?                      // maxCapacity ÷ designCapacity, the real number (not rounded up like System Settings)
    var condition: String?                // “Good”, “Check Battery”…
    var temperature: Double?              // °C
    var voltage: Double?                  // V
    var amperage: Int?                    // mA, negative while discharging
    var adapterWatts: Int?
    var adapterName: String?
    var adapterVoltage: Double?           // V the charger agreed on (USB‑C Power Delivery)
    var adapterCurrent: Double?           // A
    var systemPowerIn: Double?            // W flowing in from the charger right now
    var batteryPower: Double? {           // W into (+) or out of (−) the battery
        guard let v = voltage, let a = amperage else { return nil }
        return v * Double(a) / 1000
    }
}

struct PortEntry: Identifiable {
    let id = UUID()
    var title: String
    var kind: String                      // “USB”, “Thunderbolt / USB4”, “Charger”
    var symbol: String
    var details: [(String, String)]
    var connected: Bool
}

final class SystemInfo: ObservableObject {
    static let shared = SystemInfo()

    @Published private(set) var battery: BatteryDetails?
    @Published private(set) var cpu: Double = 0                 // 0…1
    @Published private(set) var memUsed: UInt64 = 0
    @Published private(set) var memTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    @Published private(set) var diskFree: Int64 = 0
    @Published private(set) var diskTotal: Int64 = 0
    @Published private(set) var netDown: Double = 0             // bytes a second
    @Published private(set) var netUp: Double = 0
    @Published private(set) var ports: [PortEntry] = []
    @Published private(set) var portsStatus = "Reading ports…"
    @Published private(set) var cpuHistory: [Double] = []

    var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }
    var thermal: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Cool"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Very hot"
        @unknown default: return "—"
        }
    }

    private var timer: Timer?
    private var lastTicks: (busy: UInt64, total: UInt64)?
    private var lastNet: (down: UInt64, up: UInt64, at: Date)?
    private var lastPorts = Date.distantPast
    private var tick = 0
    private var readingPorts = false

    /// Refresh while the Big Screen is open (every 2 seconds; ports every minute)
    func start() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.common(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func refresh() {
        tick += 1
        readCPU(); readMemory(); readNetwork()
        if tick % 5 == 1 { battery = Self.readBattery(); readDisk() }
        if Date().timeIntervalSince(lastPorts) > 60 { refreshPorts() }
    }

    // MARK: battery and power

    private static func int(_ v: Any?) -> Int? {
        (v as? NSNumber).map { Int(truncatingIfNeeded: $0.int64Value) }   // some values are stored unsigned
    }

    static func readBattery() -> BatteryDetails? {
        var b = BatteryDetails()
        var found = false
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for ps in list {
                guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                      (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
                found = true
                if let cur = int(d[kIOPSCurrentCapacityKey]), let mx = int(d[kIOPSMaxCapacityKey]), mx > 0 {
                    b.percent = Int((Double(cur) / Double(mx) * 100).rounded())
                }
                b.charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
                b.pluggedIn = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
                b.fullyCharged = (d[kIOPSIsChargedKey] as? Bool) ?? false
                let t = b.charging ? int(d[kIOPSTimeToFullChargeKey]) : int(d[kIOPSTimeToEmptyKey])
                if let t = t, t > 0 { b.minutesLeft = t }
                b.condition = d[kIOPSBatteryHealthKey] as? String
            }
        }
        guard found else { return nil }        // desktop Macs have no battery

        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if svc != 0 {
            defer { IOObjectRelease(svc) }
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let p = props?.takeRetainedValue() as? [String: Any] {
                b.cycleCount = int(p["CycleCount"])
                b.designCapacity = int(p["DesignCapacity"])
                // On Apple silicon “MaxCapacity” is a percentage; the raw figure is the real one
                b.maxCapacity = int(p["AppleRawMaxCapacity"]) ?? int(p["NominalChargeCapacity"]) ?? int(p["MaxCapacity"])
                if let m = b.maxCapacity, let dc = b.designCapacity, dc > 0, m > 100 {
                    b.health = Int((Double(m) / Double(dc) * 100).rounded())
                }
                if let t = int(p["Temperature"]) { b.temperature = Double(t) / 100 }
                if let v = int(p["Voltage"]) { b.voltage = Double(v) / 1000 }
                b.amperage = int(p["InstantAmperage"]) ?? int(p["Amperage"])
                if let ad = p["AdapterDetails"] as? [String: Any], b.pluggedIn {
                    b.adapterWatts = int(ad["Watts"])
                    b.adapterName = (ad["Name"] as? String) ?? (ad["Description"] as? String)
                    if let v = int(ad["AdapterVoltage"]) { b.adapterVoltage = Double(v) / 1000 }
                    if let c = int(ad["Current"]) { b.adapterCurrent = Double(c) / 1000 }
                }
                if let tel = p["PowerTelemetryData"] as? [String: Any], let w = int(tel["SystemPowerIn"]), b.pluggedIn {
                    b.systemPowerIn = Double(w) / 1000
                }
            }
        }
        if b.pluggedIn, b.adapterWatts == nil,
           let ad = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            b.adapterWatts = int(ad[kIOPSPowerAdapterWattsKey])
        }
        return b
    }

    // MARK: CPU, memory, storage, network

    private func readCPU() {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard r == KERN_SUCCESS else { return }
        let user = UInt64(load.cpu_ticks.0), system = UInt64(load.cpu_ticks.1), idle = UInt64(load.cpu_ticks.2), nice = UInt64(load.cpu_ticks.3)
        let busy = user + system + nice, total = busy + idle
        if let last = lastTicks, total > last.total {
            cpu = Double(busy - last.busy) / Double(total - last.total)
            cpuHistory.append(cpu)
            if cpuHistory.count > 40 { cpuHistory.removeFirst(cpuHistory.count - 40) }
        }
        lastTicks = (busy, total)
    }

    private func readMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard r == KERN_SUCCESS else { return }
        let page = Int64(getpagesize())
        // What Activity Monitor calls “Memory Used”: app memory + wired + compressed
        let app = max(0, Int64(stats.internal_page_count) - Int64(stats.purgeable_count))
        let used = UInt64(max(0, (app + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * page))
        memUsed = min(used, memTotal)
    }

    private func readDisk() {
        let url = URL(fileURLWithPath: "/")
        if let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            diskFree = v.volumeAvailableCapacityForImportantUsage ?? 0
            diskTotal = Int64(v.volumeTotalCapacity ?? 0)
        }
    }

    private func readNetwork() {
        var down: UInt64 = 0, up: UInt64 = 0
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let start = first else { return }
        defer { freeifaddrs(first) }
        var p: UnsafeMutablePointer<ifaddrs>? = start
        while let cur = p {
            let a = cur.pointee
            let name = String(cString: a.ifa_name)
            if let addr = a.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), name.hasPrefix("en"), let data = a.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                down += UInt64(d.ifi_ibytes); up += UInt64(d.ifi_obytes)
            }
            p = a.ifa_next
        }
        let now = Date()
        if let last = lastNet {
            let dt = now.timeIntervalSince(last.at)
            if dt > 0.2 {
                // the counters are 32-bit and wrap around; a jump backwards means it wrapped
                netDown = down >= last.down ? Double(down - last.down) / dt : netDown
                netUp = up >= last.up ? Double(up - last.up) / dt : netUp
            }
        }
        lastNet = (down, up, now)
    }

    // MARK: USB‑C, Thunderbolt and USB ports (from System Information)

    func refreshPorts() {
        guard !readingPorts else { return }
        readingPorts = true
        lastPorts = Date()
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            p.arguments = ["-json", "SPUSBHostDataType", "SPUSBDataType", "SPThunderboltDataType", "SPPowerDataType"]
            let out = Pipe()
            p.standardOutput = out; p.standardError = Pipe()
            var entries: [PortEntry] = []
            var status = ""
            do {
                try p.run()
                let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: killer)
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                killer.cancel()
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    entries = Self.parsePorts(json)
                } else { status = "Couldn’t read System Information" }
            } catch { status = "Couldn’t read System Information" }
            DispatchQueue.main.async {
                self.readingPorts = false
                self.ports = entries
                self.portsStatus = status.isEmpty ? (entries.isEmpty ? "Nothing plugged in" : "") : status
            }
        }
    }

    /// Turns System Information's keys (“USBDeviceKeyLinkSpeed”, “current_speed_key”…) into plain labels
    static func pretty(_ key: String) -> String {
        var k = key
        for pre in ["spusb_", "sppower_", "spthunderbolt_", "USBDeviceKey", "USBKey", "receptacle_", "device_"] where k.hasPrefix(pre) {
            k = String(k.dropFirst(pre.count))
        }
        if k.hasSuffix("_key") { k = String(k.dropLast(4)) }
        k = k.replacingOccurrences(of: "_", with: " ")
        // split CamelCase
        var out = ""
        for (i, ch) in k.enumerated() {
            if i > 0, ch.isUppercase, let prev = out.last, prev.isLowercase { out.append(" ") }
            out.append(ch)
        }
        let s = out.trimmingCharacters(in: .whitespaces)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    private static func prettyValue(_ v: Any) -> String? {
        if let s = v as? String {
            var t = s
            for pre in ["attrib_", "spusb_", "sppower_", "spthunderbolt_"] where t.hasPrefix(pre) { t = String(t.dropFirst(pre.count)) }
            return t.replacingOccurrences(of: "_", with: " ")
        }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    /// Pairs worth showing: speeds, power, link state, vendor and so on
    private static func details(_ d: [String: Any]) -> [(String, String)] {
        let skip = ["_name", "_items", "serial_num", "USBDeviceKeySerialNumber", "bsd_name", "_properties"]
        var out: [(String, String)] = []
        for (k, v) in d.sorted(by: { $0.key < $1.key }) where !skip.contains(k) {
            if let sub = v as? [String: Any] {
                for (k2, v2) in sub.sorted(by: { $0.key < $1.key }) { if let s = prettyValue(v2) { out.append((pretty(k2), s)) } }
            } else if let s = prettyValue(v) {
                out.append((pretty(k), s))
            }
        }
        // Speeds and power first, they're what you usually want
        func rank(_ label: String) -> Int {
            let l = label.lowercased()
            if l.contains("speed") { return 0 }
            if l.contains("watt") || l.contains("power") || l.contains("current") || l.contains("volt") { return 1 }
            if l.contains("link") || l.contains("status") { return 2 }
            return 3
        }
        return out.sorted { rank($0.0) < rank($1.0) }
    }

    static func parsePorts(_ json: [String: Any]) -> [PortEntry] {
        var entries: [PortEntry] = []
        // Charger (power coming in)
        for item in (json["SPPowerDataType"] as? [[String: Any]]) ?? [] {
            let name = (item["_name"] as? String) ?? ""
            if name.contains("charger") || item.keys.contains(where: { $0.contains("ac_charger") }) {
                let d = details(item)
                let connected = d.contains { $0.0.lowercased().contains("connected") && $0.1.lowercased().contains("yes") }
                entries.append(PortEntry(title: "Charger", kind: "Power in", symbol: "bolt.fill", details: d, connected: connected))
            }
        }
        // Thunderbolt / USB4 ports: one entry per port (receptacle), with what's plugged into it
        for bus in (json["SPThunderboltDataType"] as? [[String: Any]]) ?? [] {
            let rec = bus.first(where: { $0.key.hasPrefix("receptacle") })?.value as? [String: Any]
            let id = (rec?["receptacle_id_key"] as? String).map { "Port \($0)" } ?? pretty((bus["_name"] as? String) ?? "Port")
            var d = details(bus)
            let kids = ((bus["_items"] as? [[String: Any]]) ?? []).compactMap { ($0["device_name_key"] as? String) ?? ($0["_name"] as? String) }
            if !kids.isEmpty { d.insert(("Connected", kids.joined(separator: ", ")), at: 0) }
            let status = (rec?["link_status_key"] as? String) ?? ""
            let connected = !kids.isEmpty || (!status.isEmpty && !status.lowercased().contains("no device"))
            entries.append(PortEntry(title: id, kind: "Thunderbolt / USB4", symbol: "bolt.horizontal.fill", details: d, connected: connected))
        }
        // USB devices (anything plugged in, through any port or hub), with the speed it agreed on
        func walk(_ items: [[String: Any]], depth: Int) {
            for it in items {
                let name = (it["_name"] as? String) ?? "USB device"
                let kids = (it["_items"] as? [[String: Any]]) ?? []
                let isDevice = it.keys.contains { k in
                    let l = k.lowercased()
                    return l.contains("vendor") || l.contains("product_id") || l.contains("productid") || l.contains("manufacturer")
                }
                if isDevice {
                    entries.append(PortEntry(title: pretty(name), kind: depth > 1 ? "USB (through a hub)" : "USB",
                                             symbol: "cable.connector", details: details(it), connected: true))
                }
                walk(kids, depth: depth + 1)
            }
        }
        for key in ["SPUSBHostDataType", "SPUSBDataType"] {
            walk((json[key] as? [[String: Any]]) ?? [], depth: 0)
        }
        // The same device can appear under both USB lists; keep the first
        var seen = Set<String>()
        return entries.filter { e in
            let k = e.kind + "|" + e.title
            if e.kind.hasPrefix("USB") && seen.contains(e.title) { return false }
            seen.insert(e.kind.hasPrefix("USB") ? e.title : k)
            return true
        }
    }

    // MARK: formatting

    static func bytes(_ b: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = b, i = 0
        while v >= 1000 && i < units.count - 1 { v /= 1000; i += 1 }
        return (v >= 100 || i == 0 ? String(format: "%.0f", v) : String(format: "%.1f", v)) + " " + units[i]
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let d = m / 1440, h = (m % 1440) / 60, mm = m % 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(mm)m" }
        return "\(mm)m"
    }
}
