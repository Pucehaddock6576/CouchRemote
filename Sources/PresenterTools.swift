// PresenterTools.swift — the four presenter/quality-of-life features:
//   • PresenterOverlay — a floating clock + elapsed timer for talks
//   • ConfirmOverlay   — “hold Select to confirm” before risky actions
//   • UsageStats       — counts how you use the remote (kept on this Mac only)
//   • Tutorial         — an interactive walkthrough, shown once on first launch
import AppKit
import SwiftUI

// MARK: - Presenter overlay

final class PresenterModel: ObservableObject {
    @Published var started = Date()
    @Published var slideStarted = Date()
}

final class PresenterOverlay {
    static let shared = PresenterOverlay()
    private(set) var active = false
    private let model = PresenterModel()
    private lazy var panel: FloatingPanel = {
        let p = FloatingPanel(size: NSSize(width: 540, height: 110))
        p.contentView = NSHostingView(rootView: PresenterView(model: model))
        return p
    }()

    @discardableResult
    func toggle() -> Bool { active ? hide() : show(); return active }

    private func show() {
        active = true
        model.started = Date(); model.slideStarted = Date()
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let f = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.maxY - panel.frame.height - 20))
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    private func hide() { active = false; panel.orderOut(nil) }
    func reset() { model.started = Date(); model.slideStarted = Date() }
    /// Called when you move to the next slide (any advance press), so the per-slide pacing cue restarts
    func advancedSlide() { model.slideStarted = Date() }
}

struct PresenterView: View {
    @ObservedObject var model: PresenterModel
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 0.5)) { ctx in
            let elapsed = Int(ctx.date.timeIntervalSince(model.started))
            let perSlide = ConfigStore.shared.settings.presenterSlideSeconds
            let onSlide = ctx.date.timeIntervalSince(model.slideStarted)
            let overdue = perSlide > 0 && onSlide > perSlide
            VStack(spacing: 8) {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ELAPSED").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white.opacity(0.5))
                        Text(String(format: "%d:%02d:%02d", elapsed / 3600, (elapsed % 3600) / 60, elapsed % 60))
                            .font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                    }
                    if perSlide > 0 {
                        Spacer()
                        // Pulses "Next slide" in amber once you've spent longer than your per‑slide time
                        Label("Next slide ›", systemImage: "arrow.right.circle.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(overdue ? .orange : .white.opacity(0.35))
                            .opacity(overdue ? (Int(ctx.date.timeIntervalSince1970 * 2) % 2 == 0 ? 1 : 0.4) : 1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("TIME").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white.opacity(0.5))
                        Text(ctx.date, style: .time).font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                    }
                }
                if perSlide > 0 {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.15))
                            Capsule().fill(overdue ? Color.orange : Color.green)
                                .frame(width: g.size.width * CGFloat(min(1, onSlide / perSlide)))
                        }
                    }
                    .frame(height: 5)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .background(Capsule(style: .continuous).fill(Color(white: 0.08).opacity(0.9)))
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
            .environment(\.colorScheme, .dark)
        }
    }
}

// MARK: - Hold-to-confirm overlay

final class ConfirmModel: ObservableObject {
    @Published var progress: Double = 0
    @Published var label = ""
}

final class ConfirmOverlay {
    static let shared = ConfirmOverlay()
    private(set) var active = false
    private(set) var confirming = false      // true only while the confirmed action actually runs
    private var lastCompleted = Date.distantPast
    /// Briefly after confirming, ignore a re-trigger (e.g. the same button releasing)
    var justConfirmed: Bool { Date().timeIntervalSince(lastCompleted) < 0.6 }
    private let model = ConfirmModel()
    private var pending: Action?
    private var timer: Timer?
    private var holding = false
    private lazy var panel: FloatingPanel = {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let p = FloatingPanel(size: screen.frame.size)
        p.contentView = NSHostingView(rootView: ConfirmView(model: model))
        return p
    }()

    /// Show the confirmation for a risky action. The user holds Select to go ahead, or Menu to cancel.
    func ask(_ a: Action) {
        pending = a
        model.progress = 0
        model.label = a.kind.title
        active = true; holding = false
        let screen = NSScreen.main ?? NSScreen.screens[0]
        panel.setFrame(screen.frame, display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        if ConfigStore.shared.settings.clickSound { NSSound(named: "Funk")?.play() }
    }

    /// From Engine while a menu/other trigger arrives
    func handle(_ t: Trigger) { if t == .menuTap || t == .homeTap { cancel() } }

    func beginHold() {
        guard active, !holding else { return }
        holding = true
        timer?.invalidate()
        timer = Timer.common(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
    }

    func endHold() {
        holding = false
        timer?.invalidate(); timer = nil
        if active && model.progress < 1 { cancel() }     // let go before it filled = cancel
    }

    private func tick() {
        guard holding else { return }
        model.progress = min(1, model.progress + (1.0 / 60) / 1.1)   // ~1.1s to fill
        if model.progress >= 1 { complete() }
    }

    private func complete() {
        timer?.invalidate(); timer = nil
        holding = false
        lastCompleted = Date()
        let a = pending
        dismiss()
        if let a = a {
            confirming = true
            _ = Runner.run(a)          // runs for real this time (the gate sees confirming == true)
            confirming = false
            Engine.shared.lastEvent = "Confirmed → \(a.kind.title)"
        }
    }

    private func cancel() {
        dismiss()
        Engine.shared.lastEvent = "Cancelled"
        HUD.shared.show("Cancelled", symbol: "xmark.circle.fill")
    }

    private func dismiss() {
        timer?.invalidate(); timer = nil
        active = false; holding = false; pending = nil; model.progress = 0
        panel.orderOut(nil)
    }
}

struct ConfirmView: View {
    @ObservedObject var model: ConfirmModel
    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 24) {
                ZStack {
                    RingGauge(value: model.progress, color: .red, lineWidth: 14).frame(width: 150, height: 150)
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 48, weight: .bold)).foregroundStyle(.yellow)
                }
                Text(model.label).font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text("Hold Select to confirm · Menu to cancel")
                    .font(.system(size: 18, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Usage stats (kept on this Mac only, in app preferences)

final class UsageStats: ObservableObject {
    static let shared = UsageStats()
    private let d = UserDefaults.standard
    private let kPresses = "usage.presses", kTriggers = "usage.triggers", kApps = "usage.apps"
    private let kSince = "usage.since", kDays = "usage.days"

    @Published private(set) var presses = 0
    private(set) var triggers: [String: Int] = [:]
    private(set) var apps: [String: Int] = [:]
    private(set) var days: Set<String> = []
    private(set) var since = Date()

    init() {
        presses = d.integer(forKey: kPresses)
        triggers = (d.dictionary(forKey: kTriggers) as? [String: Int]) ?? [:]
        apps = (d.dictionary(forKey: kApps) as? [String: Int]) ?? [:]
        days = Set((d.array(forKey: kDays) as? [String]) ?? [])
        since = (d.object(forKey: kSince) as? Date) ?? Date()
        if d.object(forKey: kSince) == nil { d.set(since, forKey: kSince) }
    }

    func record(trigger: String, app: String) {
        presses += 1
        triggers[trigger, default: 0] += 1
        if !app.isEmpty { apps[app, default: 0] += 1 }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        days.insert(fmt.string(from: Date()))
        // write back occasionally (every press is fine; it's tiny)
        d.set(presses, forKey: kPresses)
        d.set(triggers, forKey: kTriggers)
        d.set(apps, forKey: kApps)
        d.set(Array(days), forKey: kDays)
    }

    func reset() {
        presses = 0; triggers = [:]; apps = [:]; days = []; since = Date()
        [kPresses, kTriggers, kApps, kDays].forEach { d.removeObject(forKey: $0) }
        d.set(since, forKey: kSince)
    }

    var daysUsed: Int { days.count }
    var topTriggers: [(String, Int)] { triggers.sorted { $0.value > $1.value }.prefix(8).map { ($0.key, $0.value) } }
    var topApps: [(String, Int)] { apps.sorted { $0.value > $1.value }.prefix(8).map { ($0.key, $0.value) } }
}

// MARK: - Interactive tutorial

struct TutorialStep: Identifiable {
    let id = UUID()
    var symbol: String
    var title: String
    var body: String
}

final class Tutorial: ObservableObject {
    static let shared = Tutorial()
    @Published var index = 0
    private(set) var active = false
    private var window: NSWindow?

    let steps: [TutorialStep] = [
        .init(symbol: "appletvremote.gen1.fill", title: "Welcome to Couch Remote",
              body: "Your Siri Remote now controls your whole Mac. This quick tour shows the basics. Click Next, or press the remote’s clickpad to move on, and Menu to go back."),
        .init(symbol: "hand.point.up.left.fill", title: "The glass is a trackpad",
              body: "In Trackpad mode, slide your thumb to move the pointer and press to click. Switch modes any time — there’s also Remote mode (arrows and media) and Scroll mode."),
        .init(symbol: "arrow.left.arrow.right", title: "Swipes and edges",
              body: "Swipe for quick actions, and use the edges and corners of the glass for shortcuts like volume and Mission Control. You set what each one does in Settings → Gestures."),
        .init(symbol: "tv.inset.filled", title: "The Big Screen",
              body: "Press the TV button for a full‑screen, couch‑friendly home: what’s playing, your music and shows, and live widgets. Swipe to move, click to open, Menu to go back."),
        .init(symbol: "square.grid.2x2.fill", title: "Widgets at a glance",
              body: "Battery health, charger and USB‑C details, weather, performance and more. Click one to open it full screen. Pick and reorder them in Settings → Big Screen."),
        .init(symbol: "scope", title: "Presenter tools",
              body: "Map buttons to a laser pointer, Draw on screen, and a Presenter overlay with a clock and timer — great for talks. All in Settings → Pop‑ups and Buttons."),
        .init(symbol: "checkmark.seal.fill", title: "You’re all set",
              body: "Open Settings any time from the menu bar icon to change what every button and swipe does. Enjoy! You can reopen this tour from Settings → Overview."),
    ]

    func show() {
        index = 0
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Couch Remote Tour"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.center()
            w.contentView = NSHostingView(rootView: TutorialView(tutorial: self))
            window = w
        }
        active = true
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Remote input while the tour is open. Returns true if handled.
    func handle(_ t: Trigger) -> Bool {
        guard active else { return false }
        switch t {
        case .select, .swipeRight, .clickRight: next()
        case .menuTap, .swipeLeft, .clickLeft: back()
        case .homeTap: close()
        default: break
        }
        return true
    }

    func next() { if index >= steps.count - 1 { close() } else { withAnimation { index += 1 } } }
    func back() { if index > 0 { withAnimation { index -= 1 } } }
    func close() {
        active = false
        window?.orderOut(nil)
        ConfigStore.shared.config.settings.tutorialDone = true
    }
}

struct TutorialView: View {
    @ObservedObject var tutorial: Tutorial
    private var step: TutorialStep { tutorial.steps[min(tutorial.index, tutorial.steps.count - 1)] }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(colors: [Color(red: 0.45, green: 0.25, blue: 0.95), Color(red: 0.9, green: 0.3, blue: 0.5)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: step.symbol).font(.system(size: 92, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(height: 240)
            VStack(spacing: 16) {
                Text(step.title).font(.system(size: 28, weight: .heavy, design: .rounded)).multilineTextAlignment(.center)
                Text(step.body).font(.system(size: 16)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Spacer()
                HStack(spacing: 7) {
                    ForEach(0..<tutorial.steps.count, id: \.self) { i in
                        Circle().fill(i == tutorial.index ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 8, height: 8)
                    }
                }
                HStack {
                    Button("Back") { tutorial.back() }.disabled(tutorial.index == 0)
                    Spacer()
                    Button(tutorial.index == tutorial.steps.count - 1 ? "Done" : "Next") { tutorial.next() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(28)
        }
        .frame(width: 640, height: 520)
    }
}
