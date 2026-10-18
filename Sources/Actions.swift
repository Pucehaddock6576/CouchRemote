// Actions.swift — performs every action type
import AppKit
import CoreGraphics

/// Marks events we post ourselves so our own event taps ignore them.
let kCouchEventMarker: Int64 = 0x43_52_4D_54   // "CRMT"

enum MediaKey: Int32 {
    case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
    case play = 16, next = 17, previous = 18, fast = 19, rewind = 20
}

enum Input {
    // MARK: keyboard
    static func key(_ code: Int, _ flags: CGEventFlags = []) {
        let src = CGEventSource(stateID: .hidSystemState)
        var flags = flags
        // A real keyboard marks the arrow keys as Fn + number-pad keys. System shortcuts such as
        // ⌃← / ⌃→ (switch Space) and ⌃↓ (App Exposé) are ignored without these flags.
        if (123...126).contains(code) { flags.insert([.maskSecondaryFn, .maskNumericPad]) }
        // Hold the modifier keys down around the key, like a person would
        let allMods: [(CGEventFlags, CGKeyCode)] = [(CGEventFlags.maskControl, 59), (CGEventFlags.maskAlternate, 58),
                                                     (CGEventFlags.maskShift, 56), (CGEventFlags.maskCommand, 55)]
        let mods = allMods.filter { flags.contains($0.0) }
        var held: CGEventFlags = []
        func post(_ e: CGEvent?) {
            guard let e = e else { return }
            e.setIntegerValueField(.eventSourceUserData, value: kCouchEventMarker)
            e.post(tap: .cghidEventTap)
        }
        for (flag, mk) in mods {
            held.insert(flag)
            let e = CGEvent(keyboardEventSource: src, virtualKey: mk, keyDown: true)
            e?.flags = held
            post(e)
        }
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(code), keyDown: down)
            e?.flags = flags
            post(e)
        }
        for (flag, mk) in mods.reversed() {
            held.remove(flag)
            let e = CGEvent(keyboardEventSource: src, virtualKey: mk, keyDown: false)
            e?.flags = held
            post(e)
        }
    }

    static func type(_ text: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        var chars = Array(text.utf16)
        while !chars.isEmpty {
            let chunk = Array(chars.prefix(16)); chars.removeFirst(min(16, chars.count))
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down) else { continue }
                e.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                e.setIntegerValueField(.eventSourceUserData, value: kCouchEventMarker)
                e.post(tap: .cghidEventTap)
            }
        }
    }

    static func media(_ key: MediaKey) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = Int((key.rawValue << 16) | ((down ? 0xa : 0xb) << 8))
            let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                                        windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)
            if let cg = ev?.cgEvent {
                cg.setIntegerValueField(.eventSourceUserData, value: kCouchEventMarker)
                cg.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: mouse
    static var dragging = false

    static var location: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    private static var screensUnion: CGRect {
        var maxDisplays: UInt32 = 16
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        CGGetActiveDisplayList(maxDisplays, &ids, &maxDisplays)
        return ids.prefix(Int(maxDisplays)).reduce(CGRect.null) { $0.union(CGDisplayBounds($1)) }
    }

    private static func clamp(_ p: CGPoint) -> CGPoint {
        // keep the pointer on a real display (handles gaps between monitors)
        var maxDisplays: UInt32 = 16
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        CGGetActiveDisplayList(maxDisplays, &ids, &maxDisplays)
        let rects = ids.prefix(Int(maxDisplays)).map { CGDisplayBounds($0) }
        if rects.contains(where: { $0.contains(p) }) { return p }
        let cur = location
        let home = rects.first(where: { $0.contains(cur) }) ?? screensUnion
        return CGPoint(x: min(max(p.x, home.minX), home.maxX - 1), y: min(max(p.y, home.minY), home.maxY - 1))
    }

    /// Mouse events come from the same source a real mouse uses, so macOS keeps track of which button
    /// is down. Open menus (the menu bar, right-click menus) check that, and could ignore clicks without it.
    private static let mouseSource = CGEventSource(stateID: .hidSystemState)
    private static var eventNumber: Int64 = 0

    static func move(dx: CGFloat, dy: CGFloat) {
        let from = location
        let p = clamp(CGPoint(x: from.x + dx, y: from.y + dy))
        let type: CGEventType = dragging ? .leftMouseDragged : .mouseMoved
        let e = CGEvent(mouseEventSource: mouseSource, mouseType: type, mouseCursorPosition: p, mouseButton: .left)
        // Windows being dragged by the title bar follow these, so fill them in like a real mouse does
        e?.setIntegerValueField(.mouseEventDeltaX, value: Int64((p.x - from.x).rounded()))
        e?.setIntegerValueField(.mouseEventDeltaY, value: Int64((p.y - from.y).rounded()))
        if dragging {
            e?.setIntegerValueField(.mouseEventClickState, value: 1)
            e?.setIntegerValueField(.mouseEventNumber, value: eventNumber)   // same press as the button-down
            e?.setDoubleValueField(.mouseEventPressure, value: 1)
        }
        e?.setIntegerValueField(.eventSourceUserData, value: kCouchEventMarker)
        e?.post(tap: .cghidEventTap)
    }

    static func moveTo(_ p: CGPoint) {
        let e = CGEvent(mouseEventSource: mouseSource, mouseType: .mouseMoved, mouseCursorPosition: clamp(p), mouseButton: .left)
        e?.post(tap: .cghidEventTap)
    }

    private static func mouse(_ type: CGEventType, _ button: CGMouseButton, clickState: Int64 = 1, at point: CGPoint? = nil) {
        let down = type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown
        if down { eventNumber += 1 }                 // a press and its release share a number, like a real mouse
        let e = CGEvent(mouseEventSource: mouseSource, mouseType: type, mouseCursorPosition: point ?? location, mouseButton: button)
        e?.setIntegerValueField(.mouseEventClickState, value: clickState)
        e?.setIntegerValueField(.mouseEventNumber, value: eventNumber)
        e?.setDoubleValueField(.mouseEventPressure, value: down ? 1 : 0)
        e?.setIntegerValueField(.eventSourceUserData, value: kCouchEventMarker)
        e?.post(tap: .cghidEventTap)
    }

    /// Whether the point is on a window's title bar (or the empty part of a toolbar joined to it),
    /// i.e. somewhere that pressing and sliding moves the window rather than a file, text or a control.
    static func onTitleBar(_ p: CGPoint) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        // The frontmost window under the pointer (the list runs front to back)
        var frame = CGRect.zero
        let hit = list.first(where: { w in
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            frame = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            return frame.contains(p)
        })
        guard let w = hit, (w[kCGWindowLayer as String] as? Int) == 0,       // a normal window, not a menu, the Dock or the desktop
              let pid = w[kCGWindowOwnerPID as String] as? pid_t
        else { return false }
        let fromTop = p.y - frame.minY
        guard fromTop >= 0, fromTop < 54 else { return false }              // the title bar plus a joined toolbar
        // Our own windows: no Accessibility round trip (it would wait on itself). Their title bars are the top 28 points.
        if pid == getpid() || !AXIsProcessTrusted() { return fromTop < 28 }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(p.x), Float(p.y), &found) == .success, let el = found
        else { return fromTop < 28 }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
        // Empty title-bar and toolbar space, or the window's title text. Anything else there is a button,
        // a tab, a search field and so on, which should be clicked, not dragged.
        let background: Set<String> = ["AXWindow", "AXToolbar", "AXGroup", "AXStaticText", "AXUnknown", "AXSplitGroup", "AXLayoutArea"]
        return background.contains(role as? String ?? "AXUnknown")
    }

    /// Press, wait a moment, release. Some menus ignore a press and release that arrive at the same instant.
    private static func press(_ downType: CGEventType, _ upType: CGEventType, _ button: CGMouseButton, clickState: Int64, at p: CGPoint) {
        mouse(downType, button, clickState: clickState, at: p)
        usleep(30_000)
        mouse(upType, button, clickState: clickState, at: p)
    }

    /// If the pointer is over an item in another app's open menu (a menu bar dropdown, a right-click menu,
    /// a menu bar icon's menu), returns that item so it can be chosen directly instead of clicked.
    private static func menuItem(at p: CGPoint) -> AXUIElement? {
        guard AXIsProcessTrusted(),
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        // The frontmost window under the pointer (the list runs front to back)
        let hit = list.first(where: { w in
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            return CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0).contains(p)
        })
        guard let w = hit,
              (w[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.popUpMenuWindow)),
              let pid = w[kCGWindowOwnerPID as String] as? pid_t,
              pid != getpid()                       // our own menus take normal clicks fine
        else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(p.x), Float(p.y), &found) == .success, var el = found else { return nil }
        for _ in 0..<3 {                            // the hit can be the item’s title or icon, so look a little way up
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
            if (role as? String) == (kAXMenuItemRole as String) {
                var kids: CFTypeRef?
                AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &kids)
                if let k = kids as? [AXUIElement], !k.isEmpty { return nil }   // opens a submenu: let the click do that
                var enabled: CFTypeRef?
                AXUIElementCopyAttributeValue(el, kAXEnabledAttribute as CFString, &enabled)
                return (enabled as? Bool) == false ? nil : el
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &parent) == .success,
                  let up = parent, CFGetTypeID(up) == AXUIElementGetTypeID() else { return nil }
            el = up as! AXUIElement
        }
        return nil
    }

    // Two clicks close together in time and place count as a double-click, like a real mouse
    private static var lastClick = (at: Date.distantPast, point: CGPoint.zero, count: Int64(0))
    static func click() {
        if dragging { dragging = false; mouse(.leftMouseUp, .left) }   // a click always ends any drag still going
        let now = Date(), p = location
        let near = hypot(p.x - lastClick.point.x, p.y - lastClick.point.y) < 6
        let count: Int64 = (now.timeIntervalSince(lastClick.at) < NSEvent.doubleClickInterval && near) ? min(lastClick.count + 1, 3) : 1
        lastClick = (now, p, count)
        // In another app's open menu, choose the item directly; menus there can ignore made-up clicks
        if count == 1, let item = menuItem(at: p), AXUIElementPerformAction(item, kAXPressAction as CFString) == .success { return }
        press(.leftMouseDown, .leftMouseUp, .left, clickState: count, at: p)
    }
    static func rightClick() { press(.rightMouseDown, .rightMouseUp, .right, clickState: 1, at: location) }
    static func doubleClick() {
        let p = location
        press(.leftMouseDown, .leftMouseUp, .left, clickState: 1, at: p)
        press(.leftMouseDown, .leftMouseUp, .left, clickState: 2, at: p)
    }
    static func mouseDown() {
        if dragging { mouse(.leftMouseUp, .left) }   // never press it twice without letting go
        dragging = true; heldSince = Date(); mouse(.leftMouseDown, .left)
    }
    static func mouseUp() { dragging = false; mouse(.leftMouseUp, .left) }
    /// When the app last pressed the button and kept it down (for a drag)
    private(set) static var heldSince = Date.distantPast

    /// Lets go of the mouse button if the app is holding it down, so it can never stay stuck.
    static func releaseIfHeld() { if dragging { mouseUp() } }

    static func scroll(dx: Int32, dy: Int32) {
        let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)
        e?.setIntegerValueField(.eventSourceUserData, value: kCouchEventMarker)
        e?.post(tap: .cghidEventTap)
    }
}

// MARK: - Running actions

enum Runner {
    static var frontApp: NSRunningApplication? { NSWorkspace.shared.frontmostApplication }

    /// Play/Pause for the whole Mac: pauses whatever is playing in any app (Music, Spotify, a browser video,
    /// Podcasts, IINA…), or resumes whatever played last. It goes through macOS's own Now Playing, the same
    /// thing the Control Centre's play button uses; if that isn't available, it presses the play media key.
    @discardableResult
    static func globalPlayPause() -> String {
        if !NowPlaying.shared.send(.toggle) { Input.media(.play) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { MusicWatcher.shared.poll() }
        return "Play / Pause"
    }
    private static var caffeinate: Process?

    /// Loves / favourites the song playing now. Apple Music can do this from AppleScript; Spotify can't,
    /// so for a browser or Spotify we press the app's own shortcut where there is one.
    @discardableResult
    static func loveSong() -> String? {
        let music = MusicWatcher.shared
        let bid = frontApp?.bundleIdentifier ?? ""
        // Apple Music, whether it's in front or just playing
        if bid == "com.apple.Music" || music.app == "Music" || music.otherBundleID == "com.apple.Music" {
            // newer Music uses “favorited”, older uses “loved”; try favourited first, fall back
            let script = """
            tell application \u{22}Music\u{22}
            try
            set favorited of current track to true
            return \u{22}ok\u{22}
            on error
            try
            set loved of current track to true
            return \u{22}ok\u{22}
            end try
            end try
            end tell
            """
            return appleScript(script) == "ok" ? "♥ Loved on Apple Music" : "Couldn’t love this track"
        }
        if bid == "com.spotify.client" || music.app == "Spotify" {
            // Spotify has no scripting for this; its shortcut to save the song is ⌘S / Add to library
            Input.key(KeyCode.s, .maskCommand)
            return "Saved to your Spotify library"
        }
        return "Loving songs works in Apple Music (and saves in Spotify)"
    }

    /// Turns Do Not Disturb on or off. macOS doesn't allow this directly, so it runs a Shortcuts
    /// shortcut (the user picks or makes one that toggles a Focus). Falls back to guiding them.
    @discardableResult
    static func hushNotifications() -> String? {
        let name = ConfigStore.shared.settings.hushShortcut.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            return "Set up Hush first: Settings → Pop‑ups → make a Shortcut that toggles Do Not Disturb, then name it here"
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["run", name]
        do { try p.run() } catch { return "Couldn’t run the Shortcut “\(name)”" }
        return "Hush · ran “\(name)”"
    }

    /// Actions worth a confirmation when "Hold to confirm" is on: things that lose work or interrupt you
    static func isRisky(_ k: ActionKind) -> Bool {
        switch k {
        case .quitApp, .closeWindow, .sleepMac, .displaySleep, .lockScreen: return true
        default: return false
        }
    }

    @discardableResult
    static func run(_ a: Action) -> String? {
        // Risky actions: when turned on, hold Select to confirm first (unless already confirmed)
        if ConfigStore.shared.settings.holdToConfirm, isRisky(a.kind), !ConfirmOverlay.shared.confirming {
            if ConfirmOverlay.shared.justConfirmed { return nil }   // the confirming button just released; don't re-ask
            ConfirmOverlay.shared.ask(a)
            return nil
        }
        let cmd = CGEventFlags.maskCommand, ctrl = CGEventFlags.maskControl, shift = CGEventFlags.maskShift
        switch a.kind {
        case .inherit, .none: return nil
        case .keystroke:
            if let code = a.keyCode { Input.key(code, CGEventFlags(rawValue: a.modifiers ?? 0)) }
        case .typeText: Input.type(a.text ?? "")
        case .playPause: globalPlayPause()
        case .nextTrack: Input.media(.next)
        case .prevTrack: Input.media(.previous)
        case .volumeUp: return volumeStep(up: true)
        case .volumeDown: return volumeStep(up: false)
        case .mute:
            if ConfigStore.shared.settings.silentVolume {
                appleScript("set volume output muted not (output muted of (get volume settings))")
            } else { Input.media(.mute) }
        case .brightnessUp: Input.media(.brightnessUp)
        case .brightnessDown: Input.media(.brightnessDown)
        case .loveSong: return loveSong()
        case .skipIntro: return web("skip")
        case .leftClick: Input.click()
        case .rightClick: Input.rightClick()
        case .doubleClick: Input.doubleClick()
        case .scrollUp: Input.scroll(dx: 0, dy: 120)
        case .scrollDown: Input.scroll(dx: 0, dy: -120)
        case .cycleTouchMode: return Engine.shared.cycleMode()
        case .trackpadMode: Engine.shared.setMode(.trackpad, announce: true)
        case .remoteMode: Engine.shared.setMode(.remote, announce: true)
        case .scrollMode: Engine.shared.setMode(.scroll, announce: true)
        case .bigScreen: BigScreen.shared.toggle()
        case .couchMenu: CouchMenu.shared.toggle()
        case .mouseSpot: return Spotlight.shared.toggle() ? "Mousespot on" : "Mousespot off"
        case .keyboardPanel: KeyboardPanel.shared.toggle()
        case .sleepTimer: return SleepTimer.shared.cycle()
        case .showHUDInfo: return nowPlaying() ?? "Nothing playing"
        case .drawOnScreen: return DrawBoard.shared.toggle() ? "Draw: click and move to draw · Menu to clear · hold to erase" : "Draw: off"
        case .laserStyle: return Spotlight.shared.nextStyle()
        case .hushNotifications: return hushNotifications()
        case .presenterOverlay: return PresenterOverlay.shared.toggle() ? "Presenter overlay on" : "Presenter overlay off"
        case .showTutorial: Tutorial.shared.show(); return "Tutorial"
        case .openYouTube: YouTubeApp.shared.toggle(); return YouTubeApp.shared.isOpen ? "YouTube" : "YouTube closed"
        case .webPlayPause: return web("toggle")
        case .webBack10: return web("seek", -10)
        case .webForward10: return web("seek", 10)
        case .webSlower: return web("speed", -0.25)
        case .webFaster: return web("speed", 0.25)
        case .webNormalSpeed: return web("speed1")
        case .webMute: return web("mute")
        case .webFullscreen: return web("full")
        case .webPiP: return web("pip")
        case .launchApp:
            if let bid = a.text, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        case .quitApp: frontApp?.terminate()
        case .hideApp: frontApp?.hide()
        case .appSwitcher:
            // Holds ⌘ so the switcher stays on screen (see AppSwitcher.swift)
            AppSwitcher.shared.openOrNext()
            return "Swipe to choose · click to switch · Menu to cancel"
        case .fullScreen: Input.key(KeyCode.f, [cmd, ctrl])
        case .closeWindow: Input.key(KeyCode.w, cmd)
        case .minimizeWindow: Input.key(KeyCode.m, cmd)
        case .missionControl: openBundle("com.apple.exposelauncher")
        case .appExpose: missionControl(arg: "2", fallback: { Input.key(KeyCode.down, ctrl) })
        case .showDesktop: missionControl(arg: "1", fallback: { Input.key(103) })
        case .launchpad: openBundle("com.apple.launchpad.launcher")
        case .nextSpace: Input.key(KeyCode.right, ctrl)
        case .prevSpace: Input.key(KeyCode.left, ctrl)
        case .spotlightSearch: Input.key(KeyCode.space, cmd)
        case .screenshot: Input.key(23, [cmd, shift])
        case .notificationCenter:
            appleScript("tell application \"System Events\" to tell process \"ControlCenter\" to click menu bar item 1 of menu bar 1")
        case .sleepMac: DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { Runner.shell("pmset sleepnow") }
        case .displaySleep: shell("pmset displaysleepnow")
        case .lockScreen: Input.key(KeyCode.q, [cmd, ctrl])
        case .keepAwake:
            if let p = caffeinate, p.isRunning { p.terminate(); caffeinate = nil; return "Mac can sleep normally" }
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate"); p.arguments = ["-di"]
            try? p.run(); caffeinate = p; return "Keeping Mac awake"
        case .openURL:
            if let s = a.text, let u = URL(string: s) { NSWorkspace.shared.open(u) }
        case .appleScript: return appleScript(a.text ?? "")
        case .shell: shell(a.text ?? "")
        }
        return nil
    }

    static func stopKeepAwake() { caffeinate?.terminate() }

    /// Changes the volume by an exact amount (in %), from where the last press left it,
    /// so every press is exactly one step even if macOS also nudges the volume.
    static var volumeTarget: (value: Double, at: Date)?

    @discardableResult
    static func volume(_ percent: Double) -> String? {
        guard let cur = appleScript("output volume of (get volume settings)").flatMap({ Double($0) }) else {
            Input.media(percent > 0 ? .soundUp : .soundDown); return nil
        }
        var base = cur
        if let t = volumeTarget, Date().timeIntervalSince(t.at) < 2 { base = t.value }
        let v = min(100, max(0, base + percent))
        volumeTarget = (v, Date())
        appleScript("set volume output volume \(Int(v.rounded()))" + (percent > 0 ? " without output muted" : ""))
        let bars = Int((v / 6.25).rounded())
        return "Volume \(Int(v.rounded()))%  " + String(repeating: "▮", count: bars) + String(repeating: "▯", count: 16 - bars)
    }

    /// One press of volume up/down, using the step chosen in Settings
    @discardableResult
    static func volumeStep(up: Bool) -> String? {
        let step = ConfigStore.shared.settings.volumeStep
        guard step > 0 else { Input.media(up ? .soundUp : .soundDown); return nil }   // "macOS default"
        return volume(up ? step : -step)
    }

    // MARK: helpers
    static func openBundle(_ bid: String) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private static func missionControl(arg: String, fallback: () -> Void) {
        let paths = ["/System/Applications/Mission Control.app/Contents/MacOS/Mission Control",
                     "/Applications/Mission Control.app/Contents/MacOS/Mission Control"]
        if let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = [arg]
            if (try? p.run()) != nil { return }
        }
        fallback()
    }

    static func shell(_ command: String) {
        guard !command.isEmpty else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", command]
        try? p.run()
    }

    @discardableResult
    static func appleScript(_ source: String) -> String? {
        guard !source.isEmpty, let script = NSAppleScript(source: source) else { return nil }
        var err: NSDictionary?
        let out = script.executeAndReturnError(&err)
        if let err = err { return "Script error: \(err[NSAppleScript.errorMessage] ?? "unknown")" }
        return out.stringValue
    }

    static func nowPlaying() -> String? {
        for (bid, name) in [("com.spotify.client", "Spotify"), ("com.apple.Music", "Music")] {
            guard NSRunningApplication.runningApplications(withBundleIdentifier: bid).first != nil else { continue }
            let s = "tell application \"\(name)\" to if player state is playing then return (name of current track) & \" — \" & (artist of current track)"
            if let r = appleScript(s), !r.isEmpty, !r.hasPrefix("Script error") { return "♪ " + r }
        }
        let w = MusicWatcher.shared
        if w.playing, let app = w.app { return "♪ " + (w.track.isEmpty ? app : w.track + (w.artist.isEmpty ? "" : " — " + w.artist)) + "  (" + app + ")" }
        return nil
    }

    // MARK: web video
    private static let chromium: [String: String] = [
        "com.google.Chrome": "Google Chrome", "com.microsoft.edgemac": "Microsoft Edge",
        "com.brave.Browser": "Brave Browser", "company.thebrowser.Browser": "Arc", "com.vivaldi.Vivaldi": "Vivaldi",
    ]

    private static let videoJS = """
    (function(cmd,arg){var v=[].slice.call(document.querySelectorAll('video'));\
    document.querySelectorAll('iframe').forEach(function(f){try{v=v.concat([].slice.call(f.contentDocument.querySelectorAll('video')))}catch(e){}});\
    if(!v.length)return 'No video on this page';\
    v.sort(function(a,b){var x=a.getBoundingClientRect(),y=b.getBoundingClientRect();return y.width*y.height-x.width*x.height});\
    var e=v.find(function(x){return !x.paused})||v[0];\
    if(cmd=='toggle'){e.paused?e.play():e.pause();return e.paused?'Paused':'Playing'}\
    if(cmd=='seek'){e.currentTime=Math.max(0,e.currentTime+arg);return (arg>0?'+':'')+arg+'s'}\
    if(cmd=='speed'){e.playbackRate=Math.max(0.25,Math.min(4,Math.round((e.playbackRate+arg)*100)/100));return e.playbackRate+'×'}\
    if(cmd=='speed1'){e.playbackRate=1;return '1×'}\
    if(cmd=='skip'){var want=['skip intro','skip recap','skip ad','skip ads','skip','next episode','skip credits'];\
    var els=[].slice.call(document.querySelectorAll('button,[role=button],a,div'));\
    var hit=els.find(function(b){var t=((b.getAttribute('aria-label')||'')+' '+(b.textContent||'')).toLowerCase().trim();\
    if(!t||t.length>24)return false;return want.some(function(w){return t.indexOf(w)>=0})&&b.offsetParent!==null});\
    if(hit){hit.click();return 'Skipped'}return 'No Skip button on screen'}\
    if(cmd=='mute'){e.muted=!e.muted;return e.muted?'Muted':'Sound on'}\
    if(cmd=='full'){if(document.fullscreenElement){document.exitFullscreen()}else{(e.requestFullscreen||e.webkitEnterFullscreen).call(e)}return 'Full screen'}\
    if(cmd=='pip'){if(document.pictureInPictureElement){document.exitPictureInPicture();return 'Picture in picture off'}\
    if(e.webkitSupportsPresentationMode&&e.webkitSupportsPresentationMode('picture-in-picture')){e.webkitSetPresentationMode(e.webkitPresentationMode=='picture-in-picture'?'inline':'picture-in-picture');return 'Picture in picture'}\
    if(e.requestPictureInPicture){e.disablePictureInPicture=false;e.requestPictureInPicture().catch(function(){});return 'Picture in picture'}\
    return 'This page doesn\\'t allow picture in picture'}\
    })('%CMD%',%ARG%)
    """

    static func isBrowser(_ bid: String) -> Bool { bid == "com.apple.Safari" || chromium[bid] != nil }

    /// The AppleScript that runs a video command in the front browser (or the first one running).
    static func webScript(_ cmd: String, _ arg: Double = 0) -> String? {
        var bid = frontApp?.bundleIdentifier ?? ""
        if !isBrowser(bid) {
            // browser not in front: use the first running one
            let candidates = ["com.apple.Safari"] + Array(chromium.keys)
            guard let found = candidates.first(where: { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }) else {
                return nil
            }
            bid = found
        }
        let js = videoJS.replacingOccurrences(of: "%CMD%", with: cmd).replacingOccurrences(of: "%ARG%", with: String(arg))
        let quoted = "\"" + js.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        if bid == "com.apple.Safari" {
            return "tell application \"Safari\" to do JavaScript \(quoted) in current tab of front window"
        }
        return "tell application \"\(chromium[bid]!)\" to execute active tab of front window javascript \(quoted)"
    }

    static func web(_ cmd: String, _ arg: Double = 0) -> String? {
        guard let src = webScript(cmd, arg) else { return "No supported browser open" }
        let r = appleScript(src)
        if let r = r, r.hasPrefix("Script error") {
            return "Turn on “Allow JavaScript from Apple Events” in the browser's Develop menu"
        }
        return r
    }
}

extension Timer {
    /// Like scheduledTimer, but keeps firing while a menu is open or a window is being dragged
    /// (the main run loop switches to a tracking mode then, which pauses ordinary timers).
    @discardableResult
    static func common(withTimeInterval interval: TimeInterval, repeats: Bool, block: @escaping (Timer) -> Void) -> Timer {
        let t = Timer(timeInterval: interval, repeats: repeats, block: block)
        RunLoop.main.add(t, forMode: .common)
        return t
    }
}
