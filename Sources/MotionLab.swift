// MotionLab.swift — EXPERIMENTAL air mouse.
// The 2015–2020 Siri Remote has motion sensors, but it isn't known whether macOS passes their
// readings through. This listens to every non-button signal the remote sends, shows them live
// in Settings so you can see what (if anything) changes when you tilt the remote, and lets you
// pick two of them to move the pointer.
import AppKit
import Combine
import IOKit.hid

struct MotionSignal: Identifiable {
    var id: String           // "page:usage"
    var page: UInt32
    var usage: UInt32
    var value: Int
    var minSeen: Int
    var maxSeen: Int
    var changes: Int
    var name: String {
        let p = String(format: "0x%02X", page), u = String(format: "0x%02X", usage)
        switch (page, usage) {
        case (0x01, 0x30): return "X (\(p)/\(u))"
        case (0x01, 0x31): return "Y (\(p)/\(u))"
        case (0x01, 0x32): return "Z (\(p)/\(u))"
        case (0x01, 0x33): return "Rotate X (\(p)/\(u))"
        case (0x01, 0x34): return "Rotate Y (\(p)/\(u))"
        case (0x01, 0x35): return "Rotate Z (\(p)/\(u))"
        case (0x20, _): return "Sensor (\(p)/\(u))"
        case (0x0D, _): return "Digitiser (\(p)/\(u))"
        default: return page >= 0xFF00 ? "Vendor (\(p)/\(u))" : "Signal (\(p)/\(u))"
        }
    }
}

final class MotionLab: ObservableObject {
    static let shared = MotionLab()

    @Published private(set) var signals: [MotionSignal] = []
    private var live: [String: MotionSignal] = [:]
    private var rest: [String: Int] = [:]            // the "still" value of each signal
    private var publishTimer: Timer?
    private var moveTimer: Timer?

    init() {
        publishTimer = Timer.common(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.publish() }
        moveTimer = Timer.common(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
    }

    /// Called by the remote reader for every value that isn't a button
    func record(_ value: IOHIDValue) {
        let el = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(el), usage = IOHIDElementGetUsage(el)
        guard page != 0x09, page != 0x07 else { return }          // buttons and keyboard keys aren't motion
        let v = IOHIDValueGetIntegerValue(value)
        let key = "\(page):\(usage)"
        if var s = live[key] {
            if s.value != v { s.changes += 1 }
            s.value = v; s.minSeen = min(s.minSeen, v); s.maxSeen = max(s.maxSeen, v)
            live[key] = s
        } else {
            live[key] = MotionSignal(id: key, page: page, usage: usage, value: v, minSeen: v, maxSeen: v, changes: 0)
            rest[key] = v
        }
    }

    private func publish() {
        guard !live.isEmpty else { return }
        let sorted = live.values.sorted { $0.changes == $1.changes ? $0.id < $1.id : $0.changes > $1.changes }
        if sorted.map(\.value) != signals.map(\.value) || sorted.count != signals.count { signals = sorted }
    }

    /// Remember how the signals read right now as "holding still"
    func setStill() { for (k, s) in live { rest[k] = s.value } }

    func reset() { live = [:]; rest = [:]; signals = [] }

    private func tick() {
        let s = ConfigStore.shared.settings
        guard s.airMouse, !anyPanelOpen, Engine.shared.mode == .trackpad else { return }
        if s.airNeedsTouch && !TouchSurface.shared.isTouching { return }
        func rate(_ key: String, invert: Bool) -> CGFloat {
            guard !key.isEmpty, let sig = live[key] else { return 0 }
            let span = max(1, sig.maxSeen - sig.minSeen)
            var d = CGFloat(sig.value - (rest[key] ?? sig.value)) / CGFloat(span)
            if abs(d) < 0.02 { d = 0 }                         // dead zone, so a still hand stays still
            return invert ? -d : d
        }
        let dx = rate(s.airX, invert: s.airInvertX), dy = rate(s.airY, invert: s.airInvertY)
        guard dx != 0 || dy != 0 else { return }
        let k = 22 * CGFloat(s.airSpeed)
        Input.move(dx: dx * k, dy: dy * k)
    }
}
