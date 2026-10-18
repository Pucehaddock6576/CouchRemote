// Seek.swift — Remote mode: swipe and keep your finger down to keep going
//   • sideways: fast-forward / rewind, faster the further you slide
//   • up/down: keep moving through a list (songs, menus) at a steady, adjustable pace
import AppKit

/// Turns how far the finger is from where it started into -1…1. Inside the dead zone it's 0 (paused).
/// Sliding about `reach` of the glass past the dead zone gives full strength.
func holdPush(_ offset: CGFloat, deadZone: CGFloat, reach: CGFloat = 0.4) -> CGFloat {
    let mag = max(0, abs(offset) - deadZone) / reach
    return mag == 0 ? 0 : (offset > 0 ? 1 : -1) * min(1, max(0.05, mag))
}

/// Started by the touch surface when a sideways swipe is held. It keeps seeking until you lift.
/// Slide further out to go faster, back towards the middle to slow down and pause, past it to reverse.
final class Scrubber {
    static let shared = Scrubber()

    private enum Target { case web, music(String), keys, unsupported }

    private(set) var active = false
    /// -1…1: which way and how hard. 0 = paused (finger slid back to the middle)
    var push: CGFloat = 0 {
        didSet {
            if (push > 0) != (oldValue > 0) || push == 0 { heldSince = Date(); lastLabel = "" }
            if oldValue == 0 && push != 0 { tick() }
        }
    }

    private var target: Target = .keys
    private var timer: Timer?
    private var heldSince = Date()
    private var busy = false
    private var lastLabel = ""
    private var nextKeyAt = Date.distantPast

    func start(push p: CGFloat) {
        stop()
        target = chooseTarget()
        active = true
        nextKeyAt = .distantPast
        push = p
        timer = Timer.common(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        if ConfigStore.shared.settings.clickSound { NSSound(named: "Tink")?.play() }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        guard active else { return }
        active = false; push = 0; busy = false
        Engine.shared.lastEvent = "Hold swipe → stopped seeking"
    }

    private func chooseTarget() -> Target {
        let s = ConfigStore.shared.settings
        let bid = Runner.frontApp?.bundleIdentifier ?? ""
        let music = MusicWatcher.shared
        // In Big Screen, Couch Remote itself is in front, so seek whatever is playing instead of pressing keys
        if BigScreen.shared.seeksOnSwipe {
            if let other = music.otherBundleID { return Runner.isBrowser(other) ? .web : .unsupported }
            if let app = music.app, app == "Music" || app == "Spotify" { return .music(app) }
            return .unsupported
        }
        if bid == "com.spotify.client" { return .music("Spotify") }
        if bid == "com.apple.Music" { return .music("Music") }
        if Runner.isBrowser(bid) { return .web }
        if music.musicPlaying && !s.musicSwipeExceptions.contains(bid) {
            let spotifyOn = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
            return .music((music.app ?? "").contains("Spotify") && spotifyOn ? "Spotify" : "Music")
        }
        return .keys
    }

    /// How many times normal speed. By distance: from the slowest to the fastest setting as you slide out.
    /// Otherwise it speeds up the longer you hold (2×, 4×, then double-steps up to the fastest).
    private var speed: Double {
        let s = ConfigStore.shared.settings
        let lo = min(s.seekMinSpeed, s.seekMaxSpeed), hi = max(s.seekMinSpeed, s.seekMaxSpeed)
        if s.seekByDistance {
            let k = Double(abs(push))
            return lo + (hi - lo) * pow(k, 1.4)
        }
        let held = Date().timeIntervalSince(heldSince)
        return min(hi, lo * pow(2, floor(held / 1.5)))
    }

    private func tick() {
        guard active, push != 0 else { return }
        let forward = push > 0
        let now = Date()
        let sp = speed
        switch target {
        case .unsupported:
            // Only Music, Spotify and browser videos can be seeked from Big Screen
            if lastLabel != "unsupported" { lastLabel = "unsupported"; HUD.shared.show("Can’t fast‑forward this app from here", symbol: "forward.fill") }
        case .keys:
            // Arrow keys usually skip 5–10 s per press, so faster means pressing more often
            let gap = max(0.05, min(0.6, 2.4 / sp))
            guard now >= nextKeyAt else { return }
            nextKeyAt = now.addingTimeInterval(gap)
            Input.key(forward ? KeyCode.right : KeyCode.left)
            show(forward, "\(Int(sp.rounded()))×")
        case .web, .music:
            // Every quarter second, jump by the speed × a quarter second
            guard now >= nextKeyAt, !busy else { return }
            nextKeyAt = now.addingTimeInterval(0.25)
            let step = sp * 0.25 * (forward ? 1 : -1)
            busy = true
            let src: String
            if case .music(let app) = target {
                src = "tell application \"\(app)\" to set player position to (player position) + \(step)"
            } else {
                guard let s = Runner.webScript("seek", step) else { busy = false; return }
                src = s
            }
            Script.run(src) { [weak self] _ in self?.busy = false }
            show(forward, "\(Int(sp.rounded()))×")
        }
    }

    private func show(_ forward: Bool, _ amount: String) {
        let label = (forward ? "Fast‑forward " : "Rewind ") + amount
        Engine.shared.lastEvent = "Hold swipe → " + label
        guard label != lastLabel, ConfigStore.shared.settings.showHUD else { return }
        lastLabel = label
        HUD.shared.show(label, symbol: forward ? "forward.fill" : "backward.fill")
    }
}

/// Remote mode: swipe up or down and keep your finger down to keep moving through a list,
/// e.g. songs in Music. It repeats whatever that swipe does, at a pace you set, and (optionally)
/// faster the further you slide. Slide back to the middle to pause; lift to stop.
final class ListRepeater {
    static let shared = ListRepeater()

    private(set) var active = false
    var push: CGFloat = 0 {
        didSet { if oldValue == 0 && push != 0 { nextAt = .distantPast; tick() } }
    }
    private var timer: Timer?
    private var nextAt = Date.distantPast
    private var count = 0

    func start(push p: CGFloat) {
        stop()
        active = true; count = 0
        push = p
        timer = Timer.common(withTimeInterval: 0.02, repeats: true) { [weak self] _ in self?.tick() }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        guard active else { return }
        active = false; push = 0
    }

    /// Steps per second
    private var rate: Double {
        let s = ConfigStore.shared.settings
        guard s.repeatByDistance else { return s.repeatRate }
        return s.repeatRate * (0.4 + 2.6 * pow(Double(abs(push)), 1.3))   // gentle near the start, up to ~3× at full stretch
    }

    private func tick() {
        guard active, push != 0 else { return }
        let now = Date()
        guard now >= nextAt else { return }
        nextAt = now.addingTimeInterval(1 / max(0.5, rate))
        count += 1
        Engine.shared.fire(push > 0 ? .swipeUp : .swipeDown, repeating: true)
    }
}
