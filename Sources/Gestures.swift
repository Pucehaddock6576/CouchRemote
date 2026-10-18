// Gestures.swift — custom Trackpad-mode gestures that start at an edge or corner of the glass
import AppKit
import SwiftUI

/// Where on the glass a gesture starts. y grows upwards (top of the remote = 1).
enum TouchZone: String, Codable, CaseIterable, Identifiable {
    case rightEdge, leftEdge, topEdge, bottomEdge, topRight, topLeft, bottomRight, bottomLeft
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rightEdge: return "Right edge"
        case .leftEdge: return "Left edge"
        case .topEdge: return "Top edge"
        case .bottomEdge: return "Bottom edge"
        case .topRight: return "Top‑right corner"
        case .topLeft: return "Top‑left corner"
        case .bottomRight: return "Bottom‑right corner"
        case .bottomLeft: return "Bottom‑left corner"
        }
    }
    var isCorner: Bool { ![.rightEdge, .leftEdge, .topEdge, .bottomEdge].contains(self) }

    func contains(_ p: CGPoint, size: CGFloat) -> Bool {
        let l = p.x < size, r = p.x > 1 - size, b = p.y < size, t = p.y > 1 - size
        switch self {
        case .rightEdge: return r
        case .leftEdge: return l
        case .topEdge: return t
        case .bottomEdge: return b
        case .topRight: return t && r
        case .topLeft: return t && l
        case .bottomRight: return b && r
        case .bottomLeft: return b && l
        }
    }

    /// The zone's area in 0…1 coordinates (y upwards), for drawing the preview.
    func rect(size s: CGFloat) -> CGRect {
        switch self {
        case .rightEdge: return CGRect(x: 1 - s, y: 0, width: s, height: 1)
        case .leftEdge: return CGRect(x: 0, y: 0, width: s, height: 1)
        case .topEdge: return CGRect(x: 0, y: 1 - s, width: 1, height: s)
        case .bottomEdge: return CGRect(x: 0, y: 0, width: 1, height: s)
        case .topRight: return CGRect(x: 1 - s, y: 1 - s, width: s, height: s)
        case .topLeft: return CGRect(x: 0, y: 1 - s, width: s, height: s)
        case .bottomRight: return CGRect(x: 1 - s, y: 0, width: s, height: s)
        case .bottomLeft: return CGRect(x: 0, y: 0, width: s, height: s)
        }
    }
}

/// What you do after putting your finger in the zone.
enum GestureMotion: String, Codable, CaseIterable, Identifiable {
    case scrollVertical, scrollHorizontal, volumeSlider, spaceSwipe, swipeUp, swipeDown, swipeLeft, swipeRight, tap, hold
    var id: String { rawValue }
    var title: String {
        switch self {
        case .scrollVertical: return "Slide up/down: scroll"
        case .scrollHorizontal: return "Slide left/right: scroll sideways"
        case .volumeSlider: return "Slide up/down: volume"
        case .spaceSwipe: return "Slide left/right: switch Spaces"
        case .swipeUp: return "Swipe up"
        case .swipeDown: return "Swipe down"
        case .swipeLeft: return "Swipe left"
        case .swipeRight: return "Swipe right"
        case .tap: return "Tap"
        case .hold: return "Rest your finger"
        }
    }
    /// Sliders keep working for as long as your finger stays down; the rest run an action once.
    var isSlider: Bool { [.scrollVertical, .scrollHorizontal, .volumeSlider, .spaceSwipe].contains(self) }

    /// Does the finger's first movement (from where it landed) start this gesture?
    func matches(_ v: CGPoint) -> Bool {
        let vertical = abs(v.y) > abs(v.x) * 1.2, horizontal = abs(v.x) > abs(v.y) * 1.2
        switch self {
        case .scrollVertical, .volumeSlider: return vertical
        case .scrollHorizontal, .spaceSwipe: return horizontal
        case .swipeUp: return vertical && v.y > 0
        case .swipeDown: return vertical && v.y < 0
        case .swipeLeft: return horizontal && v.x < 0
        case .swipeRight: return horizontal && v.x > 0
        case .tap, .hold: return false
        }
    }
}

struct EdgeGesture: Codable, Identifiable, Hashable {
    var id = UUID()
    var enabled = true
    var zone: TouchZone
    var motion: GestureMotion
    var action: Action = .k(.none)
    /// This gesture's own edge width (fraction of the glass); nil = use the shared "Edge width"
    var width: Double? = nil
    /// Slide the other way (scroll, volume or Spaces go the opposite direction); nil/false = normal
    var reversed: Bool? = nil

    /// How deep this gesture's area reaches into the glass
    func zoneSize(_ shared: CGFloat) -> CGFloat {
        if let w = width { return CGFloat(w) }
        return zone == .topEdge ? max(shared, 0.16) : shared   // thumbs rarely land right at the top, so it's a bit more forgiving
    }

    var title: String { "\(zone.title): \(motion.title.lowercased())" }

    static let defaults: [EdgeGesture] = [
        EdgeGesture(zone: .rightEdge, motion: .scrollVertical),
        // Top edge: slide sideways to change Spaces. The Spaces follow your finger, like a three-finger swipe on a Mac trackpad
        EdgeGesture(zone: .topEdge, motion: .spaceSwipe),
        EdgeGesture(enabled: false, zone: .bottomEdge, motion: .scrollHorizontal),
        EdgeGesture(enabled: false, zone: .leftEdge, motion: .volumeSlider),
        EdgeGesture(enabled: false, zone: .topLeft, motion: .hold, action: .k(.missionControl)),
        EdgeGesture(enabled: false, zone: .bottomLeft, motion: .swipeRight, action: .k(.nextTrack)),
    ]
}

// MARK: - Settings screen

struct GesturesTab: View {
    @ObservedObject var store = ConfigStore.shared
    @ObservedObject var engine = Engine.shared

    var body: some View {
        Form {
            Section {
                Toggle("Use edge and corner gestures in Trackpad mode", isOn: $store.config.settings.edgeGesturesOn)
                Text("Put your finger down at an edge or corner of the glass, then move it. A slide that starts on the right edge scrolls with one finger, for example. If you move some other way, the pointer moves as normal, so you can still start pointing from the edges.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 20) {
                    ZonePreview(gestures: store.config.settings.edgeGestures.filter(\.enabled),
                                size: CGFloat(store.config.settings.edgeZoneSize), finger: engine.touchPoint)
                        .frame(width: 150, height: 230)
                    VStack(alignment: .leading, spacing: 10) {
                        slider("Shared edge width", $store.config.settings.edgeZoneSize, 0.04...0.3)
                        slider("Edge scroll speed", $store.config.settings.edgeScrollSpeed, 0.3...3)
                        Toggle("Keep scrolling a little after you let go", isOn: $store.config.settings.edgeScrollMomentum)
                        slider("Spaces swipe speed", $store.config.settings.spacesSpeed, 0.4...3)
                        Toggle("Flip the Spaces swipe direction", isOn: $store.config.settings.spacesInvert)
                        Toggle("Follow my finger as it slides (experimental — macOS 27 may ignore it)",
                               isOn: Binding(get: { !store.config.settings.spacesShortcutOnly },
                                             set: { store.config.settings.spacesShortcutOnly = !$0 }))
                        HStack {
                            Text("Test:").foregroundStyle(.secondary)
                            Button("◀︎ Previous Space") { DockSwipe.test(right: false) }
                            Button("Next Space ▶︎") { DockSwipe.test(right: true) }
                        }
                        if !DockSwipe.spaceShortcutsEnabled() {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Space switching is turned off in macOS", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption.bold()).foregroundStyle(.orange)
                                Text("Turn on \u{201C}Move left/right a space\u{201D} under Mission Control, then the top-edge swipe (and ⌃← / ⌃→) will work.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Button("Open Keyboard Shortcuts\u{2026}") {
                                    openSettings("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
                                }
                            }
                            .padding(10).background(Color.orange.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Text("The Spaces swipe works in every touch mode: start at the very top of the glass and slide sideways. By default it switches when you let go, which shows the same slide macOS does. You need more than one Space, and \u{201C}Move left/right a space\u{201D} must be on in System Settings \u{2192} Keyboard \u{2192} Keyboard Shortcuts \u{2192} Mission Control.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("The drawing shows the remote's glass. Your gesture areas are shaded, and the white dot is your finger, so you can practise here.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Your gestures") {
                ForEach(store.config.settings.edgeGestures) { g in
                    GestureRow(id: g.id)
                }
                HStack {
                    Button("Add gesture") {
                        store.config.settings.edgeGestures.append(EdgeGesture(zone: .topRight, motion: .swipeDown, action: .k(.missionControl)))
                    }
                    Button("Restore examples") { store.config.settings.edgeGestures = EdgeGesture.defaults }
                }
                Text("If two gestures share a spot, corners win over edges, and the one higher in this list wins over the ones below it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Scroll direction") {
                Toggle("Natural scrolling (content follows your finger)", isOn: $store.config.settings.naturalScroll)
                Text("This one setting sets which way scrolling goes everywhere: Scroll touch mode, two‑finger scrolling in Trackpad mode, and edge‑scroll gestures. Flip it here and Scroll mode flips with it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            PerModeGesturesSection()
        }
        .formStyle(.grouped)
    }
}

// MARK: - Per‑touch‑mode gestures

struct PerModeGesturesSection: View {
    @ObservedObject var store = ConfigStore.shared
    @ObservedObject var ui = UIState.shared

    /// Only the gestures a mode can actually produce through the engine, so no row here is a dead control.
    /// Remote mode is the rich one; in Trackpad and Scroll the glass is busy pointing/scrolling.
    static func triggers(_ mode: TouchMode) -> [Trigger] {
        switch mode {
        case .remote:   return [.swipeUp, .swipeDown, .swipeLeft, .swipeRight, .clickUp, .clickDown, .clickLeft, .clickRight, .select, .selectHold]
        case .trackpad: return [.twoFingerTap]
        case .scroll:   return [.select, .selectHold]
        }
    }

    private var note: String {
        switch ui.gestureMode {
        case .remote:   return "In Remote mode every swipe and edge click is free to re‑map here."
        case .trackpad: return "In Trackpad mode a one‑finger slide moves the pointer, so only the two‑finger tap is free here. For edge and corner slides, use the gestures list above."
        case .scroll:   return "In Scroll mode a slide scrolls the page, so the click and long‑click are what's free to re‑map here."
        }
    }

    var body: some View {
        Section("Gestures for each touch mode") {
            Picker("Touch mode", selection: $ui.gestureMode) {
                ForEach(TouchMode.allCases) { m in Text(m.short).tag(m) }
            }
            .pickerStyle(.segmented)
            Text(note).font(.caption).foregroundStyle(.secondary)
            ForEach(Self.triggers(ui.gestureMode)) { t in
                HStack(alignment: .center) {
                    Text(t.gestureName).frame(width: 180, alignment: .leading)
                    ActionEditor(action: binding(ui.gestureMode, t), allowInherit: true,
                                 id: "mode.\(ui.gestureMode.rawValue).\(t.rawValue)")
                }
            }
            Text("“Same as Global” keeps this gesture's normal behaviour for the mode. Anything else overrides it just for that mode.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func binding(_ mode: TouchMode, _ t: Trigger) -> Binding<Action> {
        Binding(
            get: { store.config.settings.modeGestures[mode.rawValue]?[t.rawValue] ?? .k(.inherit) },
            set: { new in
                var map = store.config.settings.modeGestures[mode.rawValue] ?? [:]
                if new.kind == .inherit { map[t.rawValue] = nil } else { map[t.rawValue] = new }
                if map.isEmpty { store.config.settings.modeGestures[mode.rawValue] = nil }
                else { store.config.settings.modeGestures[mode.rawValue] = map }
            })
    }
}

private struct GestureRow: View {
    @ObservedObject var store = ConfigStore.shared
    let id: UUID

    private var index: Int? { store.config.settings.edgeGestures.firstIndex { $0.id == id } }

    var body: some View {
        if let i = index {
            let g = store.config.settings.edgeGestures[i]
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Toggle("", isOn: $store.config.settings.edgeGestures[i].enabled).labelsHidden()
                    Picker("", selection: $store.config.settings.edgeGestures[i].zone) {
                        ForEach(TouchZone.allCases) { z in Text(z.title).tag(z) }
                    }
                    .labelsHidden().frame(width: 170)
                    Picker("", selection: $store.config.settings.edgeGestures[i].motion) {
                        ForEach(GestureMotion.allCases) { m in Text(m.title).tag(m) }
                    }
                    .labelsHidden().frame(width: 220)
                    Spacer()
                    Button { move(i, -1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.borderless).disabled(i == 0)
                    Button { move(i, 1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.borderless)
                        .disabled(i == store.config.settings.edgeGestures.count - 1)
                    Button { store.config.settings.edgeGestures.removeAll { $0.id == id } } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
                if !g.motion.isSlider {
                    HStack {
                        Text("Then").foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                        ActionEditor(action: $store.config.settings.edgeGestures[i].action, allowInherit: false, id: "gesture.\(id)")
                    }
                }
                widthRow(i, g)
                if g.motion.isSlider { reverseRow(i, g) }
            }
            .opacity(g.enabled ? 1 : 0.55)
        }
    }

    /// "Direction": flip which way this slider goes
    private func reverseRow(_ i: Int, _ g: EdgeGesture) -> some View {
        let on = Binding<Bool>(
            get: { store.config.settings.edgeGestures.indices.contains(i) && store.config.settings.edgeGestures[i].reversed == true },
            set: { v in
                guard store.config.settings.edgeGestures.indices.contains(i) else { return }
                store.config.settings.edgeGestures[i].reversed = v ? true : nil
            })
        return HStack {
            Text("Way").foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
            Toggle(g.motion == .scrollHorizontal || g.motion == .spaceSwipe ? "Reverse direction (swap left and right)" : "Reverse direction (swap up and down)", isOn: on)
        }
        .font(.callout)
    }

    /// "Width": use the shared edge width, or give this gesture its own
    private func widthRow(_ i: Int, _ g: EdgeGesture) -> some View {
        let shared = CGFloat(store.config.settings.edgeZoneSize)
        let own = Binding<Bool>(
            get: { store.config.settings.edgeGestures.indices.contains(i) && store.config.settings.edgeGestures[i].width != nil },
            set: { on in
                guard store.config.settings.edgeGestures.indices.contains(i) else { return }
                store.config.settings.edgeGestures[i].width = on ? Double(g.zoneSize(shared)) : nil
            })
        let value = Binding<Double>(
            get: { store.config.settings.edgeGestures.indices.contains(i) ? (store.config.settings.edgeGestures[i].width ?? Double(g.zoneSize(shared))) : 0.1 },
            set: { v in
                guard store.config.settings.edgeGestures.indices.contains(i) else { return }
                store.config.settings.edgeGestures[i].width = v
            })
        return HStack {
            Text("Width").foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
            Toggle("Own width", isOn: own)
            if g.width != nil {
                Slider(value: value, in: 0.03...0.45).frame(width: 200)
                Text("\(Int((value.wrappedValue * 100).rounded()))% of the glass").monospacedDigit().foregroundStyle(.secondary)
            } else {
                Text("uses the shared edge width (\(Int((g.zoneSize(shared) * 100).rounded()))%)").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    private func move(_ i: Int, _ d: Int) {
        let j = i + d
        guard store.config.settings.edgeGestures.indices.contains(j) else { return }
        store.config.settings.edgeGestures.swapAt(i, j)
    }
}

/// A little drawing of the glass with the gesture areas shaded.
struct ZonePreview: View {
    let gestures: [EdgeGesture]
    let size: CGFloat
    let finger: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.85))
                ForEach(gestures) { g in
                    let z = g.zone, r = z.rect(size: g.zoneSize(size))
                    Rectangle()
                        .fill((z.isCorner ? Color.orange : Color.accentColor).opacity(0.45))
                        .frame(width: r.width * w, height: r.height * h)
                        .offset(x: r.minX * w, y: (1 - r.maxY) * h)
                }
                if let p = finger {
                    Circle().fill(Color.white).frame(width: 14, height: 14)
                        .offset(x: p.x * w - 7, y: (1 - p.y) * h - 7)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }
}

// MARK: - Switching Spaces with a real swipe

/// Sends the same "dock swipe" events macOS gets from a three-finger trackpad swipe, so the Spaces
/// slide along with your finger and settle when you let go.
///
/// Since macOS 27 the window server only accepts these when each one carries the raw trackpad
/// (IOHID) data a real swipe has, comes with a companion gesture event, and arrives at least
/// ~10 ms after the previous one. This follows the approach InstantSpaceSwitcher uses on macOS 27.
/// None of this is documented, so if a swipe is still ignored we fall back to ⌃← / ⌃→.
enum DockSwipe {
    private enum Phase: Int64 { case began = 1, changed = 2, ended = 4, cancelled = 8 }
    private enum Item { case began, changed, ended(Double), cancelled }

    private static var active = false
    private static var offset: Double = 0          // how far through the swipe; ±1 is one whole Space
    private static var samples: [(t: TimeInterval, o: Double)] = []
    private static var outbox: [Item] = []
    private static var lastPost: TimeInterval = 0
    private static var pumping = false
    private static var spaceChangedAt: TimeInterval = 0
    private static var beganAt: TimeInterval = 0
    private static var natural = true
    private static var live = true                 // false: just switch with the shortcut when you let go
    private static var observer: NSObjectProtocol?
    private static let gap: TimeInterval = 0.011

    private static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
    private static func field(_ n: UInt32) -> CGEventField { unsafeBitCast(n, to: CGEventField.self) }

    private static let needsPayload: Bool = {
        var size = 0
        guard sysctlbyname("kern.osproductversion", nil, &size, nil, 0) == 0, size > 0 else { return false }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osproductversion", &buf, &size, nil, 0) == 0 else { return false }
        let major = Int(String(cString: buf).split(separator: ".").first ?? "") ?? 0
        return major >= 27
    }()

    /// macOS 27 reads the swipe direction through the "Natural scrolling" setting.
    private static func naturalScrolling() -> Bool {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        var valid: DarwinBoolean = false
        let on = CFPreferencesGetAppBooleanValue("com.apple.swipescrolldirection" as CFString,
                                                 kCFPreferencesAnyApplication, &valid)
        return !valid.boolValue || on
    }

    // MARK: Public

    static func begin() {
        if active { end() }
        watchSpaces()
        active = true; offset = 0; beganAt = now(); samples = [(beganAt, 0)]
        natural = naturalScrolling()
        live = !ConfigStore.shared.settings.spacesShortcutOnly
        if live { enqueue(.began) }
    }

    /// dx: how far the finger moved sideways on the glass (the full width is 1)
    static func move(_ dx: CGFloat) {
        guard active else { return }
        let s = ConfigStore.shared.settings
        // Finger left → the Space on the right, like a trackpad. On macOS 27 (with natural scrolling)
        // "right" is negative progress; older systems use the opposite sign.
        var sign: Double = needsPayload ? (natural ? 1 : -1) : -1
        if s.spacesInvert { sign = -sign }
        offset = max(-1, min(1, offset + Double(dx) * 1.6 * s.spacesSpeed * sign))
        samples.append((now(), offset))
        if samples.count > 8 { samples.removeFirst(samples.count - 8) }
        guard live else { return }
        if case .changed? = outbox.last {} else { enqueue(.changed) }   // coalesce while waiting
    }

    static func end() {
        guard active else { return }
        active = false
        // Speed over the last ~0.1 s, in Spaces per second
        let t = now()
        let recent = samples.filter { t - $0.t < 0.12 }
        var speed: Double = 0
        if let a = recent.first, let b = recent.last, b.t - a.t > 0.005 { speed = (b.o - a.o) / (b.t - a.t) }
        let flick = abs(speed) > 1.0 && (speed > 0) == (offset > 0) && abs(offset) > 0.03
        let commit = abs(offset) > 0.22 || flick
        let goingRight = needsPayload ? ((offset < 0) == natural) : (offset > 0)
        if !live {
            if commit { shortcut(goingRight: goingRight) }
            return
        }
        if commit {
            enqueue(.ended(offset > 0 ? 9999 : -9999))
            announce(goingRight: goingRight, how: "swipe")
            fallback(goingRight: goingRight)
        } else {
            enqueue(.ended(0))
        }
    }

    /// For the test buttons in Settings: a pretend finger slide of a third of the glass.
    static func test(right: Bool) {
        begin()
        let s = ConfigStore.shared.settings
        var sign: CGFloat = right ? -1 : 1                       // finger left = Space on the right
        if s.spacesInvert { sign = -sign }
        for i in 1...12 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02 * Double(i)) { DockSwipe.move(sign * 0.035 / CGFloat(max(0.4, s.spacesSpeed))) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { DockSwipe.end() }
    }

    /// Switch straight away with ⌃→ / ⌃←.
    static func shortcut(goingRight: Bool) {
        Input.key(goingRight ? KeyCode.right : KeyCode.left, .maskControl)
        announce(goingRight: goingRight, how: "shortcut")
    }

    /// The ⌃← / ⌃→ shortcut only switches Spaces when "Move left/right a space" is on in
    /// System Settings → Keyboard → Keyboard Shortcuts → Mission Control. These are IDs 79 and 81.
    /// macOS leaves the keys out of the plist while they're at their (enabled) default, so a missing
    /// entry counts as on.
    static func spaceShortcutsEnabled() -> Bool {
        guard let keys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,
                                                   "com.apple.symbolichotkeys" as CFString) as? [String: Any]
        else { return true }
        func on(_ id: String) -> Bool {
            guard let e = keys[id] as? [String: Any] else { return true }
            if let b = e["enabled"] as? Bool { return b }
            if let n = e["enabled"] as? Int { return n == 1 }
            return true
        }
        return on("79") && on("81")
    }

    private static func announce(goingRight: Bool, how: String) {
        Engine.shared.lastEvent = "Top edge → " + (goingRight ? "next Space" : "previous Space") + " (\(how))"
        if ConfigStore.shared.settings.showHUD {
            HUD.shared.show(goingRight ? "Next Space" : "Previous Space", symbol: goingRight ? "arrow.right.square" : "arrow.left.square")
        }
    }

    // MARK: Pacing

    private static func enqueue(_ item: Item) {
        outbox.append(item)
        pump()
    }

    private static func pump() {
        guard !pumping, !outbox.isEmpty else { return }
        let wait = lastPost + gap - now()
        if wait > 0 {
            pumping = true
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { DockSwipe.pumping = false; DockSwipe.pump() }
            return
        }
        let item = outbox.removeFirst()
        switch item {
        case .began: post(.began, progress: tiny(offset), velocity: 0)
        case .changed: post(.changed, progress: tiny(offset), velocity: 0)
        case .ended(let v): post(.ended, progress: tiny(offset), velocity: v)
        case .cancelled: post(.cancelled, progress: tiny(offset), velocity: 0)
        }
        lastPost = now()
        if !outbox.isEmpty { pump() }
    }

    /// The payload stores progress as 16.16 fixed point, so exact zero must be nudged to stay signed.
    private static func tiny(_ p: Double) -> Double {
        if abs(p) >= 0.000016 { return p }
        return p < 0 ? -0.000016 : 0.000016
    }

    // MARK: Events

    private static func post(_ phase: Phase, progress: Double, velocity: Double) {
        guard let swipe = CGEvent(source: nil) else { return }
        swipe.setIntegerValueField(field(55), value: 30)              // dock control
        swipe.setIntegerValueField(field(110), value: 23)             // kind: dock swipe
        swipe.setIntegerValueField(field(132), value: phase.rawValue)
        swipe.setIntegerValueField(field(123), value: 1)              // sideways
        swipe.setDoubleValueField(field(124), value: progress)
        if needsPayload {
            // Extra fields a real trackpad swipe carries
            swipe.setIntegerValueField(field(134), value: phase.rawValue)
            swipe.setDoubleValueField(field(138), value: 3.0)
            swipe.setDoubleValueField(field(169), value: Double(mach_absolute_time()))
            swipe.setDoubleValueField(field(125), value: 0.1)
            if phase == .ended { swipe.setDoubleValueField(field(129), value: velocity) }
        } else if phase == .ended {
            swipe.setDoubleValueField(field(129), value: velocity)
            swipe.setDoubleValueField(field(130), value: velocity)
        }

        var toPost: CGEvent = swipe
        if needsPayload {
            guard let augmented = attachPayload(swipe) else { return }
            toPost = augmented
        }
        toPost.post(tap: .cgSessionEventTap)
        if needsPayload, let companion = CGEvent(source: nil) {
            companion.setIntegerValueField(field(55), value: 29)      // the gesture event that goes with it
            companion.post(tap: .cgSessionEventTap)
        }
    }

    private static func fixed(_ v: Double) -> Int32 {
        let f = Int32(clamping: Int64((v * 65536).rounded(.towardZero)))
        if f == 0 && v != 0 { return v > 0 ? 1 : -1 }
        return f
    }

    /// Re-serialises the event with the raw trackpad (IOHID) data appended, which macOS 27 requires.
    private static func attachPayload(_ event: CGEvent) -> CGEvent? {
        guard let cf = event.data else { return nil }
        let original = cf as Data
        guard original.count >= 4, original[original.startIndex + 3] == 2 else { return nil }   // format v2

        let phase = event.getIntegerValueField(field(132))
        let motion = event.getIntegerValueField(field(123))
        let progress = event.getDoubleValueField(field(124))
        let posX = event.getDoubleValueField(field(125)), posY = event.getDoubleValueField(field(126))
        let velX = event.getDoubleValueField(field(129)), velY = event.getDoubleValueField(field(130))
        let mask = event.getIntegerValueField(field(115))
        let withVelocity = velX != 0 || velY != 0 || phase == 4

        var p = Data()
        func u8(_ v: UInt8) { p.append(v) }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { p.append(contentsOf: $0) } }
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { p.append(contentsOf: $0) } }
        func i32(_ v: Int32) { u32(UInt32(bitPattern: v)) }
        func u64(_ v: UInt64) { var x = v.littleEndian; withUnsafeBytes(of: &x) { p.append(contentsOf: $0) } }

        let stamp = event.timestamp != 0 ? event.timestamp : mach_absolute_time()
        // Queue element header (28 bytes)
        u64(stamp); u64(0); u32(0); u32(0); u32(withVelocity ? 2 : 1)
        // Fluid-touch gesture event (40 bytes)
        u32(40); u32(23); u32(UInt32(phase & 0xFF) << 24); u8(0); u8(0); u8(0); u8(0)
        i32(fixed(posX)); i32(fixed(posY)); i32(0)
        u32(UInt32(truncatingIfNeeded: mask)); u16(UInt16(truncatingIfNeeded: motion)); u16(3)   // dock-primary flavour
        i32(fixed(progress))
        if withVelocity {
            // Child velocity event (28 bytes)
            u32(28); u32(9); u32(0); u8(1); u8(0); u8(0); u8(0)
            i32(fixed(velX)); i32(fixed(velY)); i32(0)
        }

        var out = original
        let len = UInt16(p.count)
        out.append(contentsOf: [UInt8(len >> 8), UInt8(len & 0xFF), UInt8(4205 >> 8), UInt8(4205 & 0xFF)])
        out.append(p)
        return CGEvent(withDataAllocator: nil, data: out as CFData)
    }

    // MARK: Backup plan

    private static func watchSpaces() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            DockSwipe.spaceChangedAt = DockSwipe.now()
        }
    }

    /// If macOS ignored the swipe, switch with the Mission Control shortcut instead.
    private static func fallback(goingRight: Bool) {
        let started = beganAt
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard DockSwipe.spaceChangedAt < started else { return }   // the swipe worked
            Engine.shared.lastEvent = "Top edge → the swipe was ignored, used ⌃ arrow instead"
            Input.key(goingRight ? KeyCode.right : KeyCode.left, .maskControl)
        }
    }
}
