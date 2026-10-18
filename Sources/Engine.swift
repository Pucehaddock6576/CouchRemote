// Engine.swift — routes remote input to your mappings, tracks state for the interface
import AppKit
import Combine
import IOKit.hid
import ApplicationServices

final class Engine: ObservableObject {
    static let shared = Engine()

    @Published var connected = false { didSet { onStatusChange?() } }
    @Published var deviceName = ""
    @Published var mode: TouchMode = .trackpad
    @Published var lastEvent = "Waiting for the remote…"
    @Published var frontAppName = ""
    @Published var frontBundleID = ""
    @Published var activeProfile = "Global"
    @Published var pressed: Set<String> = []
    @Published var touchPoint: CGPoint?
    @Published var axGranted = false
    @Published var inputGranted = false

    /// Called when the connection or battery changes, so the menu bar title can update
    var onStatusChange: (() -> Void)?
    @Published var touchAttached = false
    @Published var battery: Int? { didSet { onStatusChange?() } }

    private var store: ConfigStore { ConfigStore.shared }
    private var selectDownAt: Date?
    private var selectHoldWork: DispatchWorkItem?
    private var selectHeld = false
    private var dragStarted = false
    private var stuckTimer: Timer?
    private var lastPlayHID = Date.distantPast
    private var lastVolumeHID = Date.distantPast
    private var mediaTap: CFMachPort?
    private var statusTimer: Timer?

    // MARK: startup

    func start() {
        mode = store.settings.defaultTouchMode
        MusicWatcher.shared.start()
        _ = UpNext.shared          // starts watching for the end of each song
        let hid = RemoteHID.shared
        hid.isMapped = { [weak self] t in
            guard let self = self, let found = self.store.action(for: t, bundleID: self.frontBundleID) else { return false }
            return found.0.kind != .none
        }
        hid.onTrigger = { [weak self] t in self?.fire(t) }
        hid.onSelect = { [weak self] down in self?.select(down) }
        // Safety net: if the app is holding the mouse button but nothing on the remote is still held
        // (a lost button release, a dropped connection, sleep), let go so clicks never get stuck.
        stuckTimer = Timer.common(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, Input.dragging, Date().timeIntervalSince(Input.heldSince) > 1 else { return }
            let clickHeld = self.dragStarted && self.connected
            if !clickHeld && !TouchSurface.shared.isTouching { Input.mouseUp() }
        }
        hid.onButtonVisual = { [weak self] name, down in
            if down { self?.pressed.insert(name) } else { self?.pressed.remove(name) }
        }
        hid.onConnection = { [weak self] up, name in
            self?.connected = up; self?.deviceName = name
            if !up { self?.dragStarted = false; self?.selectDownAt = nil; Input.releaseIfHeld() }
            if up { TouchSurface.shared.reattach() }
            HUD.shared.show(up ? "Remote connected" : "Remote disconnected", symbol: up ? "appletvremote.gen1.fill" : "appletvremote.gen1", kind: .connection)
        }
        hid.start()

        let touch = TouchSurface.shared
        touch.onVisual = { [weak self] p in self?.touchPoint = p }
        touch.onTouchingChanged = { [weak self] on in
            guard let self = self, self.store.settings.spotAutoOnTouch, self.mode == .trackpad else { return }
            Spotlight.shared.setTemporary(on)
        }
        touch.start()

        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.frontAppChanged()
        }
        frontAppChanged()
        installMediaTap()
        refreshStatus()
        statusTimer = Timer.common(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshStatus() }
    }

    func refreshStatus() {
        axGranted = AXIsProcessTrusted()
        inputGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        touchAttached = TouchSurface.shared.attached
        connected = RemoteHID.shared.connected
        battery = RemoteHID.shared.batteryPercent
        if mediaTap == nil { installMediaTap() }
    }

    func requestPermissions() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    private func frontAppChanged() {
        let app = NSWorkspace.shared.frontmostApplication
        guard app?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        frontAppName = app?.localizedName ?? ""
        frontBundleID = app?.bundleIdentifier ?? ""
        let p = store.profile(for: frontBundleID)
        activeProfile = p?.name ?? "Global"
        if store.settings.autoModePerApp {
            setMode(p?.touchMode ?? store.settings.defaultTouchMode, announce: false)
        }
    }

    // MARK: modes

    func setMode(_ m: TouchMode, announce: Bool) {
        if dragStarted { Input.mouseUp(); dragStarted = false }
        mode = m
        if announce { HUD.shared.show(m.short + " mode", symbol: m.symbol, kind: .touchMode) }
    }

    func cycleMode() -> String? {
        let all = TouchMode.allCases
        let next = all[(all.firstIndex(of: mode)! + 1) % all.count]
        setMode(next, announce: true)
        return nil
    }

    // MARK: input routing

    /// repeating: sent again and again by a held swipe (no click sound each time)
    func fire(_ t: Trigger, repeating: Bool = false) {
        if !repeating { UsageStats.shared.record(trigger: t.rawValue, app: frontAppName) }
        // Presenter pacing cue: moving on (a right swipe/click) restarts the per-slide timer
        if PresenterOverlay.shared.active, t == .swipeRight || t == .clickRight { PresenterOverlay.shared.advancedSlide() }
        // The tour and the confirm overlay take over the remote while they're up
        if Tutorial.shared.active { _ = Tutorial.shared.handle(t); return }
        if ConfirmOverlay.shared.active { ConfirmOverlay.shared.handle(t); return }
        // While drawing on screen, Menu clears the drawing (press the Draw button again to put it away)
        if DrawBoard.shared.active, t == .menuTap { DrawBoard.shared.clear(); lastEvent = "Draw → cleared"; return }
        // Overlays capture navigation while they are open (topmost first)
        if YouTubeApp.shared.isOpen, YouTubeApp.shared.handle(t) { return }
        if AppSwitcher.shared.active, AppSwitcher.shared.handle(t) { return }
        if KeyboardPanel.shared.isOpen, KeyboardPanel.shared.handle(t) { return }
        if CouchMenu.shared.isOpen, CouchMenu.shared.handle(t) { return }
        if BigScreen.shared.isOpen, BigScreen.shared.handle(t) { return }

        // Per-touch-mode gesture override: if this gesture has its own job in the current mode, do that.
        if t.isGesture, !anyPanelOpen, let a = store.settings.modeGesture(mode, t) {
            if a.kind == .none { lastEvent = "\(t.title) → nothing (\(mode.short) mode)"; return }
            if store.settings.clickSound && !repeating { NSSound(named: "Tink")?.play() }
            let result = Runner.run(a)
            let label = result ?? a.summary
            lastEvent = "\(t.title) → \(label)  (\(mode.short) mode)"
            announce(a, result: result, label: label)
            return
        }

        // Music swipes: in Remote mode, while Music or Spotify is playing, from any app
        let s = store.settings
        let music = MusicWatcher.shared
        if mode == .remote, music.musicPlaying, !anyPanelOpen, !s.musicSwipeExceptions.contains(frontBundleID) {
            if s.musicSwipes && (t == .swipeLeft || t == .swipeRight) {
                lastEvent = "\(t.title) → " + music.skip(forward: t == .swipeRight)
                return
            }
            if s.musicSwipesVolume && (t == .swipeUp || t == .swipeDown) {
                Runner.volumeStep(up: t == .swipeUp)
                lastEvent = "\(t.title) → Volume " + (t == .swipeUp ? "up" : "down")
                return
            }
        }

        if t == .playTap && store.settings.playPause == .letMacOSHandle { return }
        // Play/Pause for the whole Mac, whichever app is in front, unless that app uses the button
        // for something else (starting a slideshow, muting a call)
        if t == .playTap && store.settings.playPause == .global && !appUsesPlayButton(frontBundleID) {
            if store.settings.clickSound && !repeating { NSSound(named: "Tink")?.play() }
            let label = Runner.globalPlayPause()
            lastEvent = "\(t.title) → \(label)"
            announce(.k(.playPause), result: nil, label: label)
            return
        }
        guard let found = store.action(for: t, bundleID: frontBundleID), found.0.kind != .none else {
            lastEvent = t.title + " → nothing"
            return
        }
        let (a, profile) = found
        if store.settings.clickSound && !repeating { NSSound(named: "Tink")?.play() }
        let result = Runner.run(a)
        let label = result ?? a.summary
        lastEvent = "\(t.title) → \(label)" + (profile == "Global" ? "" : "  (\(profile))")
        announce(a, result: result, label: label)
    }

    /// True if the app in front maps Play/Pause to something other than playing and pausing,
    /// e.g. Keynote starting the slideshow or Zoom muting. Play/pause-like mappings (Space in a video
    /// player, the browser's video play/pause) don't count: the whole-Mac play/pause covers those.
    private func appUsesPlayButton(_ bid: String?) -> Bool {
        guard let found = store.action(for: .playTap, bundleID: bid), found.1 != "Global" else { return false }
        let a = found.0
        switch a.kind {
        case .inherit, .none, .playPause, .webPlayPause: return false
        case .keystroke: return !(a.keyCode == KeyCode.space && (a.modifiers ?? 0) == 0)
        default: return true
        }
    }

    private static let silentKinds: Set<ActionKind> = [.keystroke, .leftClick, .rightClick, .doubleClick, .scrollUp, .scrollDown,
                                                        .bigScreen, .couchMenu, .keyboardPanel, .cycleTouchMode, .trackpadMode, .remoteMode, .scrollMode]

    /// The first “NN%” in a message, as 0…1
    static func percent(in s: String) -> Double? {
        guard let r = s.range(of: #"\d{1,3}(?=%)"#, options: .regularExpression), let n = Double(s[r]) else { return nil }
        return n / 100
    }

    private func announce(_ a: Action, result: String?, label: String) {
        if store.settings.showHUD && (!Self.silentKinds.contains(a.kind) || result != nil) {
            let kind = hudKind(for: a.kind)
            // Volume messages like “Volume 40%” also get a level bar
            HUD.shared.show(label, symbol: symbol(for: a.kind), kind: kind, level: kind == .volume ? Self.percent(in: label) : nil)
        }
    }

    /// An edge or corner gesture from the Gestures settings (Trackpad mode)
    func runGesture(_ g: EdgeGesture) {
        guard g.action.kind != .none, g.action.kind != .inherit else { return }
        if store.settings.clickSound { NSSound(named: "Tink")?.play() }
        let result = Runner.run(g.action)
        let label = result ?? g.action.summary
        lastEvent = "\(g.title) → \(label)"
        announce(g.action, result: result, label: label)
    }

    func swipe(_ t: Trigger) {
        // Scroll mode and Trackpad mode use the glass for scrolling/pointing, so swipes don't trigger actions there
        if anyPanelOpen || mode == .remote { fire(t) }
    }

    func tap(fingers: Int) {
        guard mode == .trackpad, !anyPanelOpen else { return }
        if fingers >= 2 {
            // Two-finger tap: right-click, or whatever "Two-finger tap" is set to on the Buttons screen
            if store.settings.twoFingerRightClick { Input.rightClick(); lastEvent = "Two‑finger tap → Right‑click" }
            else { fire(.twoFingerTap) }
        }
        else if store.settings.tapToClick { Input.click() }
    }

    /// Remote mode only: a tap on the glass works like the Apple TV clickpad. A tap in the middle circle
    /// selects (Return); a tap above / below / left / right of it moves that way (arrow keys). This also
    /// drives Big Screen and the Couch Menu when they're open, since it fires the same triggers the
    /// edge‑clicks do. Great for navigating something like the Music app one‑handed, just by tapping.
    func tapZone(_ p: CGPoint) {
        guard mode == .remote else { return }
        let dx = p.x - 0.5, dy = p.y - 0.5
        let t: Trigger
        if hypot(dx, dy) < CGFloat(store.settings.remoteTapCenter) { t = .select }
        else if abs(dx) >= abs(dy) { t = dx > 0 ? .clickRight : .clickLeft }
        else { t = dy > 0 ? .clickUp : .clickDown }      // y increases upward, matching swipes
        fire(t)
    }

    /// Glass pressed and held in Trackpad mode: press the mouse button down where the pointer is,
    /// so sliding moves the window under it (by its title bar). Starts as soon as you slide while
    /// pressed, or after holding still for a moment. Unless “drag other things” is on, anywhere other
    /// than a title bar is left alone: the pointer just moves and letting go doesn't click.
    private var dragRefused = false
    func beginHeldDrag(moved: Bool = false) {
        guard selectDownAt != nil, !dragStarted, !dragRefused, mode == .trackpad, !anyPanelOpen else { return }
        if !store.settings.dragAnything && !Input.onTitleBar(Input.location) {
            if moved { dragRefused = true; selectHoldWork?.cancel(); TouchSurface.shared.dragRefused() }
            return
        }
        selectHoldWork?.cancel()
        dragStarted = true
        Input.mouseDown()
        TouchSurface.shared.dragBegan()
    }

    private func select(_ down: Bool) {
        // The calibration wizard measures how long you hold the click, and nothing else happens
        if Calibration.shared.active { Calibration.shared.press(down); return }
        // Hold-to-confirm: holding Select fills the ring; letting go cancels
        if ConfirmOverlay.shared.active { if down { ConfirmOverlay.shared.beginHold() } else { ConfirmOverlay.shared.endHold() }; return }
        // Drawing on screen: pressing the glass puts the pen down, moving draws, lifting ends the line
        if DrawBoard.shared.active && mode == .trackpad {
            if down { DrawBoard.shared.penDown() } else { DrawBoard.shared.penUp() }
            return
        }
        TouchSurface.shared.noteClicked()
        let s = store.settings
        let panelOpen = anyPanelOpen
        // Letting go of the click always lets go of a held drag, whatever opened or changed meanwhile
        if !down && (dragStarted || selectDownAt != nil) {
            selectHoldWork?.cancel(); selectDownAt = nil
            TouchSurface.shared.clickEnded()
            if dragStarted { Input.mouseUp(); dragStarted = false; return }
            if mode == .trackpad && !panelOpen && !dragRefused { Input.click() }
            return
        }
        if mode == .trackpad && !panelOpen {
            if down {
                TouchSurface.shared.clickBegan()
                Input.releaseIfHeld()
                selectDownAt = Date(); dragStarted = false; dragRefused = false
                guard s.dragOnLongClick else { return }
                // Holding still for a moment also starts a drag, for things that need the button held without moving
                let w = DispatchWorkItem { [weak self] in self?.beginHeldDrag() }
                selectHoldWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: w)
            } else {
                selectHoldWork?.cancel(); selectDownAt = nil
                TouchSurface.shared.clickEnded()
                if dragStarted { Input.mouseUp(); dragStarted = false } else if !dragRefused { Input.click() }
            }
            return
        }
        // Remote / Scroll mode (and panels): click, long click, or edge zones
        if down {
            selectHeld = false
            let w = DispatchWorkItem { [weak self] in self?.selectHeld = true; self?.fire(.selectHold) }
            selectHoldWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + s.holdTime, execute: w)
            return
        }
        selectHoldWork?.cancel()
        if selectHeld { selectHeld = false; return }
        if !panelOpen, mode == .remote, s.edgeClickZones, let p = TouchSurface.shared.lastPoint {
            let dx = p.x - 0.5, dy = p.y - 0.5
            if max(abs(dx), abs(dy)) > 0.28 {
                fire(abs(dx) > abs(dy) ? (dx > 0 ? .clickRight : .clickLeft) : (dy > 0 ? .clickUp : .clickDown))
                return
            }
        }
        fire(.select)
    }

    // MARK: Play/Pause de-duplication
    // The remote also sends Play/Pause to macOS over Bluetooth audio control (AVRCP).
    // We hold that system key briefly and drop it if the remote's own button press arrives.

    func notePlayButton() { lastPlayHID = Date() }
    func noteVolumeButton() { lastVolumeHID = Date() }

    private func installMediaTap() {
        guard AXIsProcessTrusted() else { return }
        let mask = CGEventMask(1 << 14)   // NX_SYSDEFINED
        let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                    eventsOfInterest: mask, callback: { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let engine = Unmanaged<Engine>.fromOpaque(refcon).takeUnretainedValue()
            return engine.mediaEvent(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap = tap else { return }
        mediaTap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func mediaEvent(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = mediaTap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.eventSourceUserData) != kCouchEventMarker,
              connected,
              let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return Unmanaged.passUnretained(event) }
        let code = (ns.data1 & 0xFFFF0000) >> 16
        // Volume: the remote can also change the volume itself over Bluetooth. If its button was just
        // pressed, Couch Remote already made the change, so drop macOS's copy (one press = one step)
        if code == 0 || code == 1 {
            let s = store.settings
            if s.volumeStep > 0 && Date().timeIntervalSince(lastVolumeHID) < 0.5 { return nil }
            return Unmanaged.passUnretained(event)
        }
        // PLAY: whenever Couch Remote handles the button itself (whole-Mac or per-app), drop macOS's own copy
        // of the remote's press, or one press would pause and then straight away resume
        guard code == 16, store.settings.playPause != .letMacOSHandle else { return Unmanaged.passUnretained(event) }
        if Date().timeIntervalSince(lastPlayHID) < 0.6 { return nil }           // remote already handled it
        guard let copy = event.copy() else { return Unmanaged.passUnretained(event) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            if Date().timeIntervalSince(self.lastPlayHID) < 0.6 { return }       // it was the remote: drop
            copy.setIntegerValueField(.eventSourceUserData, value: kCouchEventMarker)
            copy.post(tap: .cghidEventTap)                                       // it was your keyboard: let it through
        }
        return nil
    }

    // MARK: helpers

    func hudKind(for k: ActionKind) -> HUDKind {
        switch k {
        case .playPause, .nextTrack, .prevTrack: return .playback
        case .volumeUp, .volumeDown, .mute, .brightnessUp, .brightnessDown: return .volume
        case .webPlayPause, .webBack10, .webForward10, .webSlower, .webFaster, .webNormalSpeed, .webMute, .webFullscreen, .webPiP: return .webVideo
        case .showHUDInfo: return .nowPlaying
        case .sleepTimer: return .sleepTimer
        case .mouseSpot: return .mousespot
        case .keepAwake, .sleepMac, .displaySleep, .lockScreen: return .power
        case .cycleTouchMode, .trackpadMode, .remoteMode, .scrollMode: return .touchMode
        default: return .actions
        }
    }

    func symbol(for k: ActionKind) -> String {
        switch k.category {
        case "Media & sound": return k == .mute ? "speaker.slash.fill" : (k == .volumeUp ? "speaker.wave.3.fill" : (k == .volumeDown ? "speaker.wave.1.fill" : "playpause.fill"))
        case "Web video": return "play.rectangle.fill"
        case "Desktop": return "rectangle.3.group"
        case "Power": return "moon.fill"
        case "Apps & windows": return "macwindow"
        case "Couch Remote": return k == .mouseSpot ? "flashlight.on.fill" : (k == .sleepTimer ? "timer" : "sparkles")
        case "Advanced": return "terminal"
        default: return "appletvremote.gen1.fill"
        }
    }
}
