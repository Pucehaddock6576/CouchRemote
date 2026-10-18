// BigWidgets.swift — the customisable widget row on the Big Screen, and the full-screen detail
// view each widget opens (battery health, charger and USB‑C ports, forecast, performance…).
import AppKit
import SwiftUI

enum BigWidget: String, CaseIterable, Identifiable {
    case clock, weather, battery, power, ports, system, storage, network, calendar, remote, usage
    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: return "Clock"
        case .weather: return "Weather"
        case .battery: return "Battery"
        case .power: return "Power & Charger"
        case .ports: return "USB‑C & Ports"
        case .system: return "Performance"
        case .storage: return "Storage"
        case .network: return "Network"
        case .calendar: return "Next Event"
        case .remote: return "Siri Remote"
        case .usage: return "Usage"
        }
    }

    var symbol: String {
        switch self {
        case .clock: return "clock.fill"
        case .weather: return "cloud.sun.fill"
        case .battery: return "battery.100"
        case .power: return "bolt.fill"
        case .ports: return "cable.connector"
        case .system: return "cpu"
        case .storage: return "internaldrive.fill"
        case .network: return "arrow.up.arrow.down"
        case .calendar: return "calendar"
        case .remote: return "appletvremote.gen1.fill"
        case .usage: return "chart.bar.fill"
        }
    }

    var blurb: String {
        switch self {
        case .clock: return "Time and date"
        case .weather: return "Now, the next hours and the week"
        case .battery: return "Charge, true health, cycle count, temperature"
        case .power: return "Charger wattage, voltage and power flowing in"
        case .ports: return "Each port and device, with the speed it agreed on"
        case .system: return "CPU, memory, temperature and uptime"
        case .storage: return "Free space on your Mac"
        case .network: return "Download and upload speed right now"
        case .calendar: return "Your next event today or tomorrow"
        case .remote: return "Remote battery, connection and touch mode"
        case .usage: return "How much you’ve used the remote"
        }
    }

    var tint: Color {
        switch self {
        case .clock: return Color(red: 0.30, green: 0.33, blue: 0.95)
        case .weather: return Color(red: 0.13, green: 0.55, blue: 0.95)
        case .battery: return Color(red: 0.16, green: 0.70, blue: 0.40)
        case .power: return Color(red: 0.98, green: 0.62, blue: 0.10)
        case .ports: return Color(red: 0.55, green: 0.36, blue: 0.95)
        case .system: return Color(red: 0.93, green: 0.30, blue: 0.40)
        case .storage: return Color(red: 0.40, green: 0.45, blue: 0.55)
        case .network: return Color(red: 0.10, green: 0.68, blue: 0.75)
        case .calendar: return Color(red: 0.95, green: 0.27, blue: 0.27)
        case .remote: return Color(red: 0.35, green: 0.35, blue: 0.40)
        case .usage: return Color(red: 0.60, green: 0.45, blue: 0.95)
        }
    }

    static let defaults: [String] = ["clock", "weather", "battery", "power", "ports", "system"]

    /// The widgets turned on, in your order
    static var enabled: [BigWidget] { ConfigStore.shared.settings.bigWidgets.compactMap(BigWidget.init(rawValue:)) }
}

// MARK: - Small shared pieces

/// A ring that fills up, for percentages
struct RingGauge: View {
    var value: Double             // 0…1
    var color: Color
    var lineWidth: CGFloat = 10
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: lineWidth)
            Circle().trim(from: 0, to: CGFloat(max(0.001, min(1, value))))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.5), value: value)
        }
    }
}

/// A thin bar that fills up
struct BarGauge: View {
    var value: Double
    var color: Color = .white
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule().fill(color).frame(width: max(height, g.size.width * CGFloat(max(0, min(1, value)))))
                    .animation(.easeOut(duration: 0.5), value: value)
            }
        }
        .frame(height: height)
    }
}

/// A tiny line chart (CPU history)
struct Sparkline: View {
    var values: [Double]
    var color: Color = .white
    var body: some View {
        GeometryReader { g in
            Path { p in
                guard values.count > 1 else { return }
                let step = g.size.width / CGFloat(values.count - 1)
                for (i, v) in values.enumerated() {
                    let pt = CGPoint(x: CGFloat(i) * step, y: g.size.height * (1 - CGFloat(max(0, min(1, v)))))
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }
}

func batterySymbol(_ percent: Int, charging: Bool) -> String {
    if charging { return "battery.100.bolt" }
    switch percent {
    case ..<13: return "battery.0"
    case ..<38: return "battery.25"
    case ..<63: return "battery.50"
    case ..<88: return "battery.75"
    default: return "battery.100"
    }
}

// MARK: - The tile in the widget row

struct WidgetTileView: View {
    let kind: BigWidget
    @ObservedObject var sys = SystemInfo.shared
    @ObservedObject var w = Widgets.shared
    @ObservedObject var engine = Engine.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: kind.symbol).font(.system(size: 15, weight: .bold))
                Text(kind.title.uppercased()).font(.system(size: 13, weight: .heavy)).tracking(0.8).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.white.opacity(0.75))
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(18)
        .foregroundStyle(Color.white)
    }

    private func big(_ s: String) -> some View {
        Text(s).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
    }
    private func small(_ s: String) -> some View {
        Text(s).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.white.opacity(0.75)).lineLimit(2).minimumScaleFactor(0.8)
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .clock:
            TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                VStack(alignment: .leading, spacing: 2) {
                    Text(ctx.date, style: .time).font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text(ctx.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(Color.white.opacity(0.75))
                }
            }
        case .weather:
            if let f = w.forecast {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: f.symbol).renderingMode(.original).font(.system(size: 44))
                    VStack(alignment: .leading, spacing: 2) {
                        big("\(f.temp)°")
                        small("\(f.place) · H \(f.hi)° L \(f.lo)°")
                    }
                }
            } else {
                small(w.weatherStatus.isEmpty ? "Loading the forecast…" : w.weatherStatus)
            }
        case .battery:
            if let b = sys.battery {
                HStack(spacing: 16) {
                    ZStack {
                        RingGauge(value: Double(b.percent) / 100, color: b.percent < 20 ? .red : (b.charging ? .green : .white), lineWidth: 9)
                        Image(systemName: b.charging ? "bolt.fill" : "battery.100").font(.system(size: 18, weight: .bold))
                    }
                    .frame(width: 70, height: 70)
                    VStack(alignment: .leading, spacing: 2) {
                        big("\(b.percent)%")
                        small([b.health.map { "Health \($0)%" }, b.cycleCount.map { "\($0) cycles" }].compactMap { $0 }.joined(separator: " · "))
                    }
                }
            } else {
                small("No battery: this Mac runs on mains power")
            }
        case .power:
            if let b = sys.battery {
                VStack(alignment: .leading, spacing: 4) {
                    if b.pluggedIn {
                        big(b.systemPowerIn.map { String(format: "%.0f W", $0) } ?? (b.adapterWatts.map { "\($0) W" } ?? "Plugged in"))
                        small([b.adapterWatts.map { "\($0) W charger" }, b.charging ? "charging" : (b.fullyCharged ? "full" : "not charging")]
                                .compactMap { $0 }.joined(separator: " · "))
                    } else {
                        big(b.batteryPower.map { String(format: "%.1f W", abs($0)) } ?? "On battery")
                        small(b.minutesLeft.map { "On battery · \(SystemInfo.duration(TimeInterval($0 * 60))) left" } ?? "On battery")
                    }
                }
            } else {
                small("Mains power")
            }
        case .ports:
            let devices = sys.ports.filter { $0.connected && $0.kind != "Power in" }
            VStack(alignment: .leading, spacing: 4) {
                big("\(devices.count)")
                small(devices.isEmpty ? (sys.portsStatus.isEmpty ? "Nothing plugged in" : sys.portsStatus)
                                      : devices.prefix(2).map(\.title).joined(separator: ", "))
            }
        case .system:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    big("\(Int((sys.cpu * 100).rounded()))%")
                    Text("CPU").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.white.opacity(0.7))
                    Spacer(minLength: 0)
                    Sparkline(values: sys.cpuHistory, color: .white.opacity(0.9)).frame(width: 90, height: 34)
                }
                BarGauge(value: sys.memTotal > 0 ? Double(sys.memUsed) / Double(sys.memTotal) : 0, color: .white, height: 7)
                small("Memory \(SystemInfo.bytes(Double(sys.memUsed))) of \(SystemInfo.bytes(Double(sys.memTotal)))")
            }
        case .storage:
            VStack(alignment: .leading, spacing: 8) {
                big(SystemInfo.bytes(Double(sys.diskFree)))
                BarGauge(value: sys.diskTotal > 0 ? 1 - Double(sys.diskFree) / Double(sys.diskTotal) : 0, color: .white, height: 7)
                small("free of \(SystemInfo.bytes(Double(sys.diskTotal)))")
            }
        case .network:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) { Image(systemName: "arrow.down.circle.fill"); big(SystemInfo.bytes(sys.netDown) + "/s") }
                HStack(spacing: 8) { Image(systemName: "arrow.up.circle.fill"); small(SystemInfo.bytes(sys.netUp) + "/s up") }
            }
        case .calendar:
            if let e = w.nextEvent {
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.when).font(.system(size: 30, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                    small(e.title)
                }
            } else {
                small(w.calendarStatus.isEmpty ? "Nothing coming up" : w.calendarStatus)
            }
        case .remote:
            VStack(alignment: .leading, spacing: 4) {
                big(engine.battery.map { "\($0)%" } ?? (engine.connected ? "On" : "Off"))
                small((engine.connected ? "Connected" : "Not connected") + " · " + engine.mode.short)
            }
        case .usage:
            VStack(alignment: .leading, spacing: 4) {
                big("\(UsageStats.shared.presses)")
                small("presses · \(UsageStats.shared.daysUsed) day\(UsageStats.shared.daysUsed == 1 ? "" : "s")")
            }
        }
    }
}

// MARK: - Full-screen detail

/// A labelled number on the detail screen
struct StatCard: View {
    var label: String
    var value: String
    var symbol: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let s = symbol { Image(systemName: s).font(.system(size: 14, weight: .bold)) }
                Text(label.uppercased()).font(.system(size: 13, weight: .heavy)).tracking(0.6).lineLimit(1)
            }
            .foregroundStyle(Color.white.opacity(0.6))
            Text(value).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
        }
        .padding(20)
        .frame(width: 250, height: 118, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }
}

struct WidgetDetailView: View {
    let kind: BigWidget
    let scroll: Int
    @ObservedObject var sys = SystemInfo.shared
    @ObservedObject var w = Widgets.shared
    @ObservedObject var engine = Engine.shared

    let columns = [GridItem(.adaptive(minimum: 250, maximum: 250), spacing: 18, alignment: .topLeading)]

    var body: some View {
        ZStack {
            BigStyle.base                                   // fully opaque, so the home screen never shows through
            LinearGradient(colors: [kind.tint.opacity(0.35), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 18) {
                    Image(systemName: kind.symbol).font(.system(size: 30, weight: .bold))
                        .frame(width: 64, height: 64)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(kind.tint))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title).font(.system(size: 40, weight: .heavy, design: .rounded))
                        Text(kind.blurb).font(.system(size: 18)).foregroundStyle(Color.white.opacity(0.7))
                    }
                    Spacer()
                }
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 26) {
                            sections
                        }
                        .padding(.bottom, 40)
                    }
                    .onChange(of: scroll) { i in withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("s\(i)", anchor: .top) } }
                }
                HStack(spacing: 26) {
                    hint("arrow.left.and.right", "Swipe: other widgets")
                    hint("arrow.up.and.down", "Swipe: scroll")
                    hint("arrow.uturn.backward", "Menu: back")
                }
                .foregroundStyle(Color.white.opacity(0.6))
            }
            .padding(.horizontal, 70).padding(.top, 60).padding(.bottom, 40)
        }
        .foregroundStyle(Color.white)
        .ignoresSafeArea()
        .onAppear { if kind == .ports { sys.refreshPorts() } }
    }

    private func hint(_ s: String, _ t: String) -> some View { Label(t, systemImage: s).font(.system(size: 16, weight: .medium)) }

    private func section<C: View>(_ i: Int, _ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Color.white.opacity(0.85))
            c()
        }
        .id("s\(i)")
    }

    private func grid(_ cards: [StatCard]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            ForEach(Array(cards.enumerated()), id: \.offset) { _, c in c }
        }
    }

    @ViewBuilder private var sections: some View {
        switch kind {
        case .clock:
            TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                VStack(alignment: .leading, spacing: 6) {
                    Text(ctx.date, style: .time).font(.system(size: 120, weight: .heavy, design: .rounded)).monospacedDigit()
                    Text(ctx.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                        .font(.system(size: 28, weight: .semibold)).foregroundStyle(Color.white.opacity(0.75))
                }
            }
            section(1, "Today") {
                grid([StatCard(label: "Mac on for", value: SystemInfo.duration(sys.uptime), symbol: "power"),
                      StatCard(label: "Time zone", value: TimeZone.current.abbreviation() ?? TimeZone.current.identifier, symbol: "globe")])
            }
        case .weather:
            if let f = w.forecast {
                HStack(spacing: 30) {
                    Image(systemName: f.symbol).renderingMode(.original).font(.system(size: 110))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(f.temp)°").font(.system(size: 96, weight: .heavy, design: .rounded))
                        Text("\(f.summary) · \(f.place)").font(.system(size: 26, weight: .semibold)).foregroundStyle(Color.white.opacity(0.8))
                    }
                }
                section(1, "Next hours") {
                    HStack(spacing: 14) {
                        ForEach(f.hours) { h in
                            VStack(spacing: 10) {
                                Text(h.time).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.white.opacity(0.7))
                                Image(systemName: h.symbol).renderingMode(.original).font(.system(size: 26))
                                Text("\(h.temp)°").font(.system(size: 22, weight: .bold, design: .rounded))
                            }
                            .frame(width: 74, height: 120)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.07)))
                        }
                    }
                }
                section(2, "This week") {
                    VStack(spacing: 8) {
                        let lowest = f.days.map(\.lo).min() ?? 0, highest = f.days.map(\.hi).max() ?? 1
                        ForEach(f.days) { d in
                            HStack(spacing: 18) {
                                Text(d.day).font(.system(size: 20, weight: .semibold)).frame(width: 90, alignment: .leading)
                                Image(systemName: d.symbol).renderingMode(.original).font(.system(size: 22)).frame(width: 36)
                                Text(d.rain > 0 ? "\(d.rain)%" : "").font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.5, green: 0.8, blue: 1)).frame(width: 46)
                                Text("\(d.lo)°").font(.system(size: 20)).foregroundStyle(Color.white.opacity(0.6)).frame(width: 50)
                                // the bar shows this day's range against the whole week
                                GeometryReader { g in
                                    let span = CGFloat(max(1, highest - lowest))
                                    let x0 = CGFloat(d.lo - lowest) / span * g.size.width
                                    let x1 = CGFloat(d.hi - lowest) / span * g.size.width
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.white.opacity(0.12))
                                        Capsule().fill(LinearGradient(colors: [.cyan, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                                            .frame(width: max(10, x1 - x0)).offset(x: x0)
                                    }
                                }
                                .frame(width: 260, height: 8)
                                Text("\(d.hi)°").font(.system(size: 20, weight: .bold)).frame(width: 50)
                            }
                            .padding(.horizontal, 20).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
                        }
                    }
                    .frame(maxWidth: 760)
                }
                section(3, "Details") {
                    grid([StatCard(label: "Feels like", value: "\(f.feels)°", symbol: "thermometer.medium"),
                          StatCard(label: "High / low", value: "\(f.hi)° / \(f.lo)°", symbol: "arrow.up.arrow.down"),
                          StatCard(label: "Humidity", value: "\(f.humidity)%", symbol: "humidity.fill"),
                          StatCard(label: "Wind", value: "\(f.wind) \(f.windUnit)", symbol: "wind"),
                          StatCard(label: "UV index", value: f.uv.map { "\($0)" } ?? "—", symbol: "sun.max.fill"),
                          StatCard(label: "Sunrise", value: f.sunrise.isEmpty ? "—" : f.sunrise, symbol: "sunrise.fill"),
                          StatCard(label: "Sunset", value: f.sunset.isEmpty ? "—" : f.sunset, symbol: "sunset.fill")])
                }
            } else {
                Text(w.weatherStatus.isEmpty ? "Loading the forecast…" : w.weatherStatus).font(.system(size: 24))
            }
        case .battery:
            if let b = sys.battery {
                HStack(spacing: 34) {
                    ZStack {
                        RingGauge(value: Double(b.percent) / 100, color: b.percent < 20 ? .red : .green, lineWidth: 18)
                        VStack(spacing: 0) {
                            Text("\(b.percent)%").font(.system(size: 50, weight: .heavy, design: .rounded))
                            Text(b.charging ? "Charging" : (b.fullyCharged ? "Charged" : (b.pluggedIn ? "Not charging" : "On battery")))
                                .font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.white.opacity(0.7))
                        }
                    }
                    .frame(width: 200, height: 200)
                    VStack(alignment: .leading, spacing: 8) {
                        if let m = b.minutesLeft {
                            Text(SystemInfo.duration(TimeInterval(m * 60)) + (b.charging ? " until full" : " left"))
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                        }
                        Text("Health is what the battery really holds now compared with when it was new, measured from the battery itself.")
                            .font(.system(size: 18)).foregroundStyle(Color.white.opacity(0.7)).frame(maxWidth: 560, alignment: .leading)
                    }
                }
                section(1, "Health") {
                    grid([StatCard(label: "True health", value: b.health.map { "\($0)%" } ?? "—", symbol: "heart.fill"),
                          StatCard(label: "Cycle count", value: b.cycleCount.map { "\($0)" } ?? "—", symbol: "arrow.triangle.2.circlepath"),
                          StatCard(label: "Holds now", value: b.maxCapacity.map { "\($0) mAh" } ?? "—", symbol: "battery.100"),
                          StatCard(label: "When new", value: b.designCapacity.map { "\($0) mAh" } ?? "—", symbol: "sparkles"),
                          StatCard(label: "Condition", value: b.condition ?? "—", symbol: "checkmark.seal.fill")])
                }
                section(2, "Right now") {
                    grid([StatCard(label: "Temperature", value: b.temperature.map { String(format: "%.1f °C", $0) } ?? "—", symbol: "thermometer.medium"),
                          StatCard(label: "Voltage", value: b.voltage.map { String(format: "%.2f V", $0) } ?? "—", symbol: "bolt"),
                          StatCard(label: "Current", value: b.amperage.map { "\($0) mA" } ?? "—", symbol: "arrow.left.arrow.right"),
                          StatCard(label: b.charging ? "Into battery" : "Battery power",
                                   value: b.batteryPower.map { String(format: "%.1f W", abs($0)) } ?? "—", symbol: "bolt.circle.fill")])
                }
            } else {
                Text("This Mac doesn’t have a battery.").font(.system(size: 24))
            }
        case .power:
            if let b = sys.battery {
                section(0, b.pluggedIn ? "Charger" : "On battery") {
                    grid([StatCard(label: "Charger", value: b.adapterWatts.map { "\($0) W" } ?? (b.pluggedIn ? "Connected" : "None"), symbol: "powerplug.fill"),
                          StatCard(label: "Power in now", value: b.systemPowerIn.map { String(format: "%.1f W", $0) } ?? "—", symbol: "bolt.fill"),
                          StatCard(label: "Agreed voltage", value: b.adapterVoltage.map { String(format: "%.1f V", $0) } ?? "—", symbol: "bolt"),
                          StatCard(label: "Agreed current", value: b.adapterCurrent.map { String(format: "%.2f A", $0) } ?? "—", symbol: "arrow.left.arrow.right"),
                          StatCard(label: b.charging ? "Into battery" : "Battery power",
                                   value: b.batteryPower.map { String(format: "%.1f W", abs($0)) } ?? "—", symbol: "battery.100.bolt"),
                          StatCard(label: "Status", value: b.charging ? "Charging" : (b.fullyCharged ? "Full" : (b.pluggedIn ? "Holding" : "Discharging")),
                                   symbol: "info.circle.fill")])
                }
                if let n = b.adapterName, !n.isEmpty {
                    Text("Charger: \(n)").font(.system(size: 18)).foregroundStyle(Color.white.opacity(0.7))
                }
                Text("USB‑C chargers and your Mac agree on a voltage and current (USB Power Delivery). These are the figures they settled on.")
                    .font(.system(size: 16)).foregroundStyle(Color.white.opacity(0.55)).frame(maxWidth: 760, alignment: .leading)
            } else {
                Text("This Mac runs on mains power.").font(.system(size: 24))
            }
        case .ports:
            portsList
        case .system:
            section(0, "Processor") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(Int((sys.cpu * 100).rounded()))%").font(.system(size: 72, weight: .heavy, design: .rounded)).monospacedDigit()
                        Text("busy").font(.system(size: 22, weight: .semibold)).foregroundStyle(Color.white.opacity(0.7))
                    }
                    Sparkline(values: sys.cpuHistory, color: kind.tint).frame(width: 700, height: 90)
                }
            }
            section(1, "Mac") {
                grid([StatCard(label: "Memory used", value: SystemInfo.bytes(Double(sys.memUsed)), symbol: "memorychip.fill"),
                      StatCard(label: "Memory total", value: SystemInfo.bytes(Double(sys.memTotal)), symbol: "memorychip"),
                      StatCard(label: "Temperature", value: sys.thermal, symbol: "thermometer.medium"),
                      StatCard(label: "On for", value: SystemInfo.duration(sys.uptime), symbol: "power"),
                      StatCard(label: "Cores", value: "\(ProcessInfo.processInfo.activeProcessorCount)", symbol: "cpu"),
                      StatCard(label: "macOS", value: ProcessInfo.processInfo.operatingSystemVersionString.replacingOccurrences(of: "Version ", with: ""),
                               symbol: "apple.logo")])
            }
        case .storage:
            section(0, "Macintosh HD") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(SystemInfo.bytes(Double(sys.diskFree))) free").font(.system(size: 64, weight: .heavy, design: .rounded))
                    BarGauge(value: sys.diskTotal > 0 ? 1 - Double(sys.diskFree) / Double(sys.diskTotal) : 0, color: kind.tint, height: 16)
                        .frame(width: 700)
                    Text("\(SystemInfo.bytes(Double(sys.diskTotal - sys.diskFree))) used of \(SystemInfo.bytes(Double(sys.diskTotal)))")
                        .font(.system(size: 20)).foregroundStyle(Color.white.opacity(0.7))
                }
            }
        case .network:
            section(0, "Right now") {
                grid([StatCard(label: "Download", value: SystemInfo.bytes(sys.netDown) + "/s", symbol: "arrow.down.circle.fill"),
                      StatCard(label: "Upload", value: SystemInfo.bytes(sys.netUp) + "/s", symbol: "arrow.up.circle.fill")])
            }
        case .calendar:
            if let e = w.nextEvent {
                Text(e.when).font(.system(size: 80, weight: .heavy, design: .rounded))
                Text(e.title).font(.system(size: 32, weight: .semibold))
            } else {
                Text(w.calendarStatus.isEmpty ? "Nothing in your calendar for the next day and a half." : w.calendarStatus).font(.system(size: 24))
            }
        case .remote:
            section(0, "Siri Remote") {
                grid([StatCard(label: "Battery", value: engine.battery.map { "\($0)%" } ?? "—", symbol: "battery.75"),
                      StatCard(label: "Connection", value: engine.connected ? "Connected" : "Not connected", symbol: "dot.radiowaves.left.and.right"),
                      StatCard(label: "Touch mode", value: engine.mode.short, symbol: "hand.point.up.left.fill"),
                      StatCard(label: "Name", value: engine.deviceName.isEmpty ? "—" : engine.deviceName, symbol: "appletvremote.gen1.fill")])
            }
        case .usage:
            section(0, "Totals") {
                grid([StatCard(label: "Button presses", value: "\(UsageStats.shared.presses)", symbol: "hand.tap.fill"),
                      StatCard(label: "Days used", value: "\(UsageStats.shared.daysUsed)", symbol: "calendar"),
                      StatCard(label: "Since", value: DateFormatter.localizedString(from: UsageStats.shared.since, dateStyle: .medium, timeStyle: .none), symbol: "clock.arrow.circlepath")])
            }
            if !UsageStats.shared.topTriggers.isEmpty {
                section(1, "Most-used buttons") {
                    VStack(spacing: 8) {
                        ForEach(UsageStats.shared.topTriggers, id: \.0) { t in
                            HStack { Text(Trigger(rawValue: t.0)?.title ?? t.0).font(.system(size: 18, weight: .semibold))
                                Spacer(); Text("\(t.1)").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.7)) }
                                .padding(.horizontal, 18).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
                        }
                    }.frame(maxWidth: 620)
                }
            }
            if !UsageStats.shared.topApps.isEmpty {
                section(2, "Apps you control most") {
                    VStack(spacing: 8) {
                        ForEach(UsageStats.shared.topApps, id: \.0) { a in
                            HStack { Text(a.0).font(.system(size: 18, weight: .semibold))
                                Spacer(); Text("\(a.1)").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.7)) }
                                .padding(.horizontal, 18).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
                        }
                    }.frame(maxWidth: 620)
                }
            }
            Text("Kept only on this Mac. Clear it in Settings → Overview.").font(.system(size: 15)).foregroundStyle(.white.opacity(0.5))
        }
    }

    @ViewBuilder private var portsList: some View {
        if sys.ports.isEmpty {
            Text(sys.portsStatus.isEmpty ? "Reading ports…" : sys.portsStatus).font(.system(size: 24))
        }
        ForEach(Array(sys.ports.enumerated()), id: \.element.id) { i, p in
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: p.symbol).font(.system(size: 22, weight: .bold))
                        .frame(width: 46, height: 46)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.connected ? kind.tint : Color.white.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.title).font(.system(size: 24, weight: .bold, design: .rounded)).lineLimit(1)
                        Text(p.kind + (p.connected ? "" : " · nothing connected")).font(.system(size: 15)).foregroundStyle(Color.white.opacity(0.6))
                    }
                }
                if !p.details.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 360), spacing: 10, alignment: .topLeading)], alignment: .leading, spacing: 8) {
                        ForEach(Array(p.details.prefix(12).enumerated()), id: \.offset) { _, d in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.0).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
                                Text(d.1).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 1100, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.07)))
            .id("s\(i)")
        }
        Text("Speeds are the ones each port and device agreed on (for example 10 Gb/s or 40 Gb/s). Read from System Information about once a minute.")
            .font(.system(size: 15)).foregroundStyle(Color.white.opacity(0.5))
    }
}

// MARK: - Settings: pick and order the widgets

struct WidgetSettingsSection: View {
    @ObservedObject var store = ConfigStore.shared
    @ObservedObject var widgets = Widgets.shared

    private var list: [String] { store.config.settings.bigWidgets }

    private func toggle(_ k: BigWidget) -> Binding<Bool> {
        Binding(get: { list.contains(k.rawValue) }, set: { on in
            var l = store.config.settings.bigWidgets
            if on { if !l.contains(k.rawValue) { l.append(k.rawValue) } } else { l.removeAll { $0 == k.rawValue } }
            store.config.settings.bigWidgets = l
            if k == .weather || k == .calendar { widgets.refresh(force: true) }
        })
    }

    private func move(_ k: BigWidget, by d: Int) {
        var l = store.config.settings.bigWidgets
        guard let i = l.firstIndex(of: k.rawValue) else { return }
        let j = i + d
        guard l.indices.contains(j) else { return }
        l.swapAt(i, j)
        store.config.settings.bigWidgets = l
    }

    /// On ones first, in your order, then the rest
    private var ordered: [BigWidget] {
        list.compactMap(BigWidget.init(rawValue:)) + BigWidget.allCases.filter { !list.contains($0.rawValue) }
    }

    var body: some View {
        Section("Widgets (the “At a glance” row)") {
            ForEach(ordered) { k in
                let on = list.contains(k.rawValue)
                HStack(spacing: 12) {
                    Image(systemName: k.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(k.tint))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(k.title)
                        Text(k.blurb).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if on {
                        Button { move(k, by: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless).disabled(list.first == k.rawValue)
                        Button { move(k, by: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless).disabled(list.last == k.rawValue)
                    }
                    Toggle("", isOn: toggle(k)).labelsHidden().toggleStyle(.switch)
                }
            }
            HStack {
                Button("Restore defaults") { store.config.settings.bigWidgets = BigWidget.defaults }
                Spacer()
                Text("You can also rearrange them on the Big Screen: hold the click on a widget → Move.").font(.caption).foregroundStyle(.secondary)
            }
        }
        Section("Weather and calendar") {
            HStack {
                TextField("City (leave empty to work it out automatically)", text: $store.config.settings.weatherCity)
                Picker("", selection: $store.config.settings.weatherCelsius) {
                    Text("°C").tag(true)
                    Text("°F").tag(false)
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 90)
                Button("Update") { widgets.refresh(force: true) }
            }
            Text(widgets.weatherStatus.isEmpty ? "From Open‑Meteo: free, no account needed. Updates every 30 minutes." : widgets.weatherStatus)
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(widgets.calendarStatus.isEmpty ? "The Next Event widget shows your next event in the next 36 hours." : widgets.calendarStatus)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Allow calendar") { widgets.requestCalendar { _ in widgets.refresh(force: true) } }
            }
        }
    }
}
