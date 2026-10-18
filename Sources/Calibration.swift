// Calibration.swift — a 30-second wizard that measures how you tap, swipe and long-press,
// then sets the tap, swipe and hold timings to suit your thumb.
import AppKit
import SwiftUI

/// One finished touch on the glass, as measured by the touch surface.
struct TouchSample {
    var distance: Double      // start to end
    var travelled: Double     // total path length
    var duration: Double      // seconds
    var fingers: Int
    var dx: Double
    var dy: Double
    var gapBefore: Double = 99   // seconds the finger was off the glass before this touch
}

final class Calibration: ObservableObject {
    static let shared = Calibration()

    enum Step: Int { case intro, taps, swipes, tapDrags, holds, done }
    struct Result {
        var tapMaxTime: Double
        var tapMaxTravel: Double
        var swipeDistance: Double
        var holdTime: Double
        var tapDragWindow: Double
    }

    @Published private(set) var step: Step = .intro
    @Published private(set) var count = 0
    @Published private(set) var message = ""
    @Published private(set) var result: Result?

    /// While measuring, touches and clicks are reported here instead of doing anything.
    var active: Bool { step == .taps || step == .swipes || step == .tapDrags || step == .holds }
    var needed: Int { (step == .holds || step == .tapDrags) ? 3 : 5 }

    private var taps: [TouchSample] = []
    private var swipes: [TouchSample] = []
    private var holds: [Double] = []
    private var dragGaps: [Double] = []
    private var lastWasTap = false
    private var pressAt: Date?

    func begin() {
        taps = []; swipes = []; holds = []; dragGaps = []; lastWasTap = false; result = nil
        go(.taps)
    }

    func cancel() { go(.intro); result = nil }

    private func go(_ s: Step) {
        step = s; count = 0; message = ""
    }

    private func tick() { NSSound(named: "Tink")?.play() }

    func touch(_ t: TouchSample) {
        switch step {
        case .taps:
            guard t.fingers == 1 else { message = "Use one finger."; return }
            guard t.distance < 0.12 && t.duration < 0.6 else { message = "That was a slide. Try a quick, light tap."; return }
            taps.append(t); count += 1; message = ""; tick()
            if count >= needed { go(.swipes) }
        case .swipes:
            guard t.distance >= 0.05 else { message = "A little longer: swipe across the glass."; return }
            swipes.append(t); count += 1; message = ""; tick()
            if count >= needed { go(.tapDrags) }
        case .tapDrags:
            // A quick tap first, then a touch that slides: measure the pause in between
            let isTap = t.fingers == 1 && t.distance < 0.06 && t.duration < 0.5
            if isTap { lastWasTap = true; message = "Now put your finger back down and slide."; return }
            guard lastWasTap, t.distance >= 0.04 else { lastWasTap = false; message = "Start with a quick tap, then touch again and slide."; return }
            lastWasTap = false
            guard t.gapBefore < 2 else { message = "A bit quicker: touch again within a second or so of the tap."; return }
            dragGaps.append(t.gapBefore); count += 1; message = ""; tick()
            if count >= needed { go(.holds) }
        default:
            break
        }
    }

    func press(_ down: Bool) {
        guard step == .holds else { return }
        if down { pressAt = Date(); return }
        guard let at = pressAt else { return }
        pressAt = nil
        let d = Date().timeIntervalSince(at)
        guard d > 0.25 else { message = "Hold it a bit longer, like a long press."; return }
        holds.append(d); count += 1; message = ""; tick()
        if count >= needed { finish() }
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }

    private func finish() {
        let tapTime = taps.map(\.duration).max() ?? 0.15
        let tapTravel = taps.map(\.travelled).max() ?? 0.02
        let shortestSwipe = swipes.map(\.distance).min() ?? 0.25
        let sortedHolds = holds.sorted()
        let medianHold = sortedHolds.isEmpty ? 0.7 : sortedHolds[sortedHolds.count / 2]
        result = Result(tapMaxTime: clamp(tapTime * 1.35 + 0.02, 0.12, 0.4),
                        tapMaxTravel: clamp(tapTravel * 1.5 + 0.005, 0.02, 0.07),
                        swipeDistance: clamp(shortestSwipe * 0.75, 0.08, 0.35),
                        holdTime: clamp(medianHold * 0.7, 0.3, 1.2),
                        // your slowest tap-then-touch-again, with room to spare
                        tapDragWindow: clamp((dragGaps.max() ?? 0.35) * 1.4 + 0.1, 0.3, 1.5))
        go(.done)
    }

    func apply() {
        guard let r = result else { return }
        let store = ConfigStore.shared
        store.config.settings.tapMaxTime = r.tapMaxTime
        store.config.settings.tapMaxTravel = r.tapMaxTravel
        store.config.settings.swipeDistance = r.swipeDistance
        store.config.settings.holdTime = r.holdTime
        store.config.settings.tapDragWindow = r.tapDragWindow
    }
}

struct CalibrationView: View {
    @ObservedObject var cal = Calibration.shared
    @ObservedObject var ui = UIState.shared

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbol).font(.system(size: 54)).foregroundStyle(Color.accentColor)
                .frame(height: 70)
            Text(title).font(.title2.bold())
            Text(detail).multilineTextAlignment(.center).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if cal.active {
                HStack(spacing: 8) {
                    ForEach(0..<cal.needed, id: \.self) { i in
                        Circle().fill(i < cal.count ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 14, height: 14)
                    }
                }
                Text(cal.message.isEmpty ? " " : cal.message).foregroundStyle(.orange)
            }
            if cal.step == .done, let r = cal.result {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    row("Longest tap", String(format: "%.2f s", r.tapMaxTime))
                    row("Tap wiggle room", String(format: "%.0f%% of the glass", r.tapMaxTravel * 100))
                    row("Swipe distance", String(format: "%.0f%% of the glass", r.swipeDistance * 100))
                    row("Long press", String(format: "%.2f s", r.holdTime))
                    row("Double‑tap to drag", String(format: "%.2f s to touch again", r.tapDragWindow))
                }
                .padding().background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))
            }
            HStack {
                Button("Cancel") { close() }
                Spacer()
                switch cal.step {
                case .intro: Button("Start") { cal.begin() }.keyboardShortcut(.defaultAction)
                case .done:
                    Button("Try again") { cal.begin() }
                    Button("Use these settings") { cal.apply(); close() }.keyboardShortcut(.defaultAction)
                default: EmptyView()
                }
            }
        }
        .padding(28)
        .frame(width: 460)
        .onDisappear { cal.cancel() }
    }

    private func row(_ a: String, _ b: String) -> some View {
        GridRow { Text(a); Text(b).monospacedDigit().bold() }
    }

    private func close() { cal.cancel(); ui.calibrating = false }

    private var symbol: String {
        switch cal.step {
        case .intro: return "hand.raised.fingers.spread.fill"
        case .taps: return "hand.tap.fill"
        case .swipes: return "hand.draw.fill"
        case .tapDrags: return "hand.draw"
        case .holds: return "hand.point.down.fill"
        case .done: return "checkmark.circle.fill"
        }
    }
    private var title: String {
        switch cal.step {
        case .intro: return "Fit the remote to your thumb"
        case .taps: return "Tap the glass 5 times"
        case .swipes: return "Swipe across the glass 5 times"
        case .tapDrags: return "Tap, then touch again and slide, 3 times"
        case .holds: return "Long‑press the glass 3 times"
        case .done: return "All done"
        }
    }
    private var detail: String {
        switch cal.step {
        case .intro: return "Hold the remote the way you normally do on the couch. You'll tap, swipe, tap‑and‑drag and long‑press a few times, and Couch Remote will set tap, swipe, drag and hold timings that suit you. Nothing on your Mac reacts while it measures."
        case .taps: return "Light, quick taps, the way you'd tap to click."
        case .swipes: return "Any direction, at your normal speed, the way you'd swipe to the next tile or song."
        case .tapDrags: return "Tap once, then put your finger back down and slide, the way you'd start dragging a window. Go at your natural speed; the app measures how long you take to touch again."
        case .holds: return "Press down until it clicks and hold for as long as feels like a long press, then let go."
        case .done: return "These settings are based on how you just used the remote. You can still fine‑tune them on the Touchpad screen."
        }
    }
}
