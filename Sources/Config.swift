// Config.swift — everything you can customise lives in this model, saved as JSON at
// ~/Library/Application Support/Couch Remote/config.json
import Foundation
import Combine
import AppKit
import CoreGraphics

// MARK: - Inputs on the remote

enum Trigger: String, CaseIterable, Codable, Identifiable {
    case menuTap = "menu.tap", menuDouble = "menu.double", menuHold = "menu.hold"
    case homeTap = "home.tap", homeDouble = "home.double", homeHold = "home.hold"
    case siriTap = "siri.tap", siriDouble = "siri.double", siriHold = "siri.hold"
    case playTap = "play.tap", playDouble = "play.double", playHold = "play.hold"
    case volUp = "vol.up", volDown = "vol.down"
    case select = "select", selectHold = "select.hold"
    case swipeUp = "swipe.up", swipeDown = "swipe.down", swipeLeft = "swipe.left", swipeRight = "swipe.right"
    case clickUp = "click.up", clickDown = "click.down", clickLeft = "click.left", clickRight = "click.right"
    case twoFingerTap = "tap.two"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .menuTap: return "Menu — press"
        case .menuDouble: return "Menu — double press"
        case .menuHold: return "Menu — hold"
        case .homeTap: return "TV/Home — press"
        case .homeDouble: return "TV/Home — double press"
        case .homeHold: return "TV/Home — hold"
        case .siriTap: return "Siri (mic) — press"
        case .siriDouble: return "Siri (mic) — double press"
        case .siriHold: return "Siri (mic) — hold"
        case .playTap: return "Play/Pause — press"
        case .playDouble: return "Play/Pause — double press"
        case .playHold: return "Play/Pause — hold"
        case .volUp: return "Volume +"
        case .volDown: return "Volume −"
        case .select: return "Touch surface click (Remote mode)"
        case .selectHold: return "Touch surface long click (Remote mode)"
        case .swipeUp: return "Swipe up (Remote mode)"
        case .swipeDown: return "Swipe down (Remote mode)"
        case .swipeLeft: return "Swipe left (Remote mode)"
        case .swipeRight: return "Swipe right (Remote mode)"
        case .clickUp: return "Click top edge (Remote mode)"
        case .clickDown: return "Click bottom edge (Remote mode)"
        case .clickLeft: return "Click left edge (Remote mode)"
        case .clickRight: return "Click right edge (Remote mode)"
        case .twoFingerTap: return "Two‑finger tap (Trackpad mode)"
        }
    }

    var group: String {
        switch self {
        case .menuTap, .menuDouble, .menuHold, .homeTap, .homeDouble, .homeHold,
             .siriTap, .siriDouble, .siriHold, .playTap, .playDouble, .playHold, .volUp, .volDown:
            return "Buttons"
        default: return "Touch surface"
        }
    }

    /// A short name without the "(… mode)" suffix, for the per‑mode gesture lists.
    var gestureName: String {
        switch self {
        case .swipeUp: return "Swipe up"
        case .swipeDown: return "Swipe down"
        case .swipeLeft: return "Swipe left"
        case .swipeRight: return "Swipe right"
        case .clickUp: return "Click top edge"
        case .clickDown: return "Click bottom edge"
        case .clickLeft: return "Click left edge"
        case .clickRight: return "Click right edge"
        case .select: return "Touch surface click"
        case .selectHold: return "Touch surface long click"
        case .twoFingerTap: return "Two‑finger tap"
        default: return title
        }
    }

    /// A touch‑surface gesture (swipe, edge click, click, two‑finger tap) rather than a physical button.
    var isGesture: Bool { group == "Touch surface" }
    /// The microphone / Siri button, left alone so the system Siri keeps working.
    var isSiri: Bool { self == .siriTap || self == .siriDouble || self == .siriHold }

    /// The physical button a variant belongs to (used by the live remote picture)
    var button: String { String(rawValue.split(separator: ".").first ?? "") }
}

enum TouchMode: String, Codable, CaseIterable, Identifiable {
    case trackpad, remote, scroll
    var id: String { rawValue }
    var title: String {
        switch self {
        case .trackpad: return "Trackpad (moves the pointer)"
        case .remote: return "Remote (swipes = arrows)"
        case .scroll: return "Scroll (swipe to scroll pages)"
        }
    }
    var short: String { switch self { case .trackpad: return "Trackpad"; case .remote: return "Remote"; case .scroll: return "Scroll" } }
    var symbol: String { switch self { case .trackpad: return "cursorarrow.motionlines"; case .remote: return "dpad"; case .scroll: return "arrow.up.and.down" } }
}

extension Settings {
    /// A per‑touch‑mode override for a gesture, if the user set one for this mode (nil means "use the normal action").
    func modeGesture(_ mode: TouchMode, _ t: Trigger) -> Action? {
        guard let a = modeGestures[mode.rawValue]?[t.rawValue], a.kind != .inherit else { return nil }
        return a
    }
}

// MARK: - Things a button can do

enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case inherit, none
    // Keyboard
    case keystroke, typeText
    // Media
    case playPause, nextTrack, prevTrack, volumeUp, volumeDown, mute, brightnessUp, brightnessDown
    case loveSong, skipIntro
    // Mouse
    case leftClick, rightClick, doubleClick, scrollUp, scrollDown
    // Touch mode
    case cycleTouchMode, trackpadMode, remoteMode, scrollMode
    // Couch Remote features
    case bigScreen, couchMenu, mouseSpot, keyboardPanel, sleepTimer, showHUDInfo
    case drawOnScreen, laserStyle, hushNotifications, presenterOverlay, showTutorial, openYouTube
    // Web video (Safari, Chrome, Edge, Brave, Arc)
    case webPlayPause, webBack10, webForward10, webSlower, webFaster, webNormalSpeed, webMute, webFullscreen, webPiP
    // Apps & windows
    case launchApp, quitApp, hideApp, appSwitcher, fullScreen, closeWindow, minimizeWindow
    // Desktop
    case missionControl, appExpose, showDesktop, launchpad, nextSpace, prevSpace, spotlightSearch, screenshot, notificationCenter
    // Power
    case sleepMac, displaySleep, lockScreen, keepAwake
    // Advanced
    case openURL, appleScript, shell

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inherit: return "Same as Global"
        case .none: return "Do nothing"
        case .keystroke: return "Press keys…"
        case .typeText: return "Type text…"
        case .playPause: return "Play / Pause"
        case .nextTrack: return "Next track"
        case .prevTrack: return "Previous track"
        case .volumeUp: return "Volume up"
        case .volumeDown: return "Volume down"
        case .mute: return "Mute"
        case .brightnessUp: return "Screen brighter"
        case .brightnessDown: return "Screen dimmer"
        case .loveSong: return "Love the current song"
        case .skipIntro: return "Skip intro / skip ad"
        case .leftClick: return "Click"
        case .rightClick: return "Right‑click"
        case .doubleClick: return "Double‑click"
        case .scrollUp: return "Scroll up"
        case .scrollDown: return "Scroll down"
        case .cycleTouchMode: return "Switch touch mode"
        case .trackpadMode: return "Trackpad mode"
        case .remoteMode: return "Remote mode"
        case .scrollMode: return "Scroll mode"
        case .bigScreen: return "Open Big Screen"
        case .couchMenu: return "Open Couch Menu"
        case .mouseSpot: return "Mousespot on/off"
        case .keyboardPanel: return "On‑screen keyboard"
        case .sleepTimer: return "Sleep timer (cycle)"
        case .showHUDInfo: return "Show what's playing"
        case .drawOnScreen: return "Draw on screen"
        case .laserStyle: return "Laser pointer: next style"
        case .hushNotifications: return "Hush notifications"
        case .presenterOverlay: return "Presenter overlay (clock & timer)"
        case .showTutorial: return "Show the tutorial"
        case .openYouTube: return "Open YouTube"
        case .webPlayPause: return "Web video: play/pause"
        case .webBack10: return "Web video: back 10s"
        case .webForward10: return "Web video: forward 10s"
        case .webSlower: return "Web video: slower"
        case .webFaster: return "Web video: faster"
        case .webNormalSpeed: return "Web video: normal speed"
        case .webMute: return "Web video: mute"
        case .webFullscreen: return "Web video: full screen"
        case .webPiP: return "Web video: picture in picture"
        case .launchApp: return "Open app…"
        case .quitApp: return "Quit front app"
        case .hideApp: return "Hide front app"
        case .appSwitcher: return "App switcher (⌘⇥)"
        case .fullScreen: return "Toggle full screen"
        case .closeWindow: return "Close window"
        case .minimizeWindow: return "Minimise window"
        case .missionControl: return "Mission Control"
        case .appExpose: return "App windows"
        case .showDesktop: return "Show desktop"
        case .launchpad: return "Launchpad"
        case .nextSpace: return "Next Space"
        case .prevSpace: return "Previous Space"
        case .spotlightSearch: return "Spotlight search"
        case .screenshot: return "Screenshot tools"
        case .notificationCenter: return "Notification Center"
        case .sleepMac: return "Sleep Mac"
        case .displaySleep: return "Turn screen off"
        case .lockScreen: return "Lock screen"
        case .keepAwake: return "Keep awake on/off"
        case .openURL: return "Open link…"
        case .appleScript: return "Run AppleScript…"
        case .shell: return "Run shell command…"
        }
    }

    var category: String {
        switch self {
        case .inherit, .none: return "Basic"
        case .keystroke, .typeText: return "Keyboard"
        case .playPause, .nextTrack, .prevTrack, .volumeUp, .volumeDown, .mute, .brightnessUp, .brightnessDown, .loveSong, .skipIntro: return "Media & sound"
        case .leftClick, .rightClick, .doubleClick, .scrollUp, .scrollDown: return "Mouse"
        case .cycleTouchMode, .trackpadMode, .remoteMode, .scrollMode: return "Touch mode"
        case .bigScreen, .couchMenu, .mouseSpot, .keyboardPanel, .sleepTimer, .showHUDInfo, .drawOnScreen, .laserStyle, .hushNotifications, .presenterOverlay, .showTutorial, .openYouTube: return "Couch Remote"
        case .webPlayPause, .webBack10, .webForward10, .webSlower, .webFaster, .webNormalSpeed, .webMute, .webFullscreen, .webPiP: return "Web video"
        case .launchApp, .quitApp, .hideApp, .appSwitcher, .fullScreen, .closeWindow, .minimizeWindow: return "Apps & windows"
        case .missionControl, .appExpose, .showDesktop, .launchpad, .nextSpace, .prevSpace, .spotlightSearch, .screenshot, .notificationCenter: return "Desktop"
        case .sleepMac, .displaySleep, .lockScreen, .keepAwake: return "Power"
        case .openURL, .appleScript, .shell: return "Advanced"
        }
    }

    static let categories = ["Basic", "Keyboard", "Media & sound", "Mouse", "Touch mode", "Couch Remote", "Web video",
                             "Apps & windows", "Desktop", "Power", "Advanced"]

    enum Param { case none, keys, text, app }
    var param: Param {
        switch self {
        case .keystroke: return .keys
        case .typeText, .openURL, .appleScript, .shell: return .text
        case .launchApp: return .app
        default: return .none
        }
    }
}

struct Action: Codable, Hashable {
    var kind: ActionKind
    var keyCode: Int? = nil
    var modifiers: UInt64? = nil
    var text: String? = nil

    static func k(_ kind: ActionKind) -> Action { Action(kind: kind) }
    static func key(_ code: Int, _ mods: CGEventFlags = []) -> Action { Action(kind: .keystroke, keyCode: code, modifiers: mods.rawValue) }
    static func app(_ bundleID: String) -> Action { Action(kind: .launchApp, text: bundleID) }

    var summary: String {
        switch kind.param {
        case .keys: return keyCode.map { KeyNames.describe(code: $0, mods: CGEventFlags(rawValue: modifiers ?? 0)) } ?? "Press keys…"
        case .text: return kind.title.replacingOccurrences(of: "…", with: "") + ": " + (text ?? "")
        case .app:
            if let bid = text, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                return "Open " + url.deletingPathExtension().lastPathComponent
            }
            return "Open app…"
        case .none: return kind.title
        }
    }
}

enum KeyCode {
    static let escape = 53, ret = 36, space = 49, tab = 48, delete = 51
    static let left = 123, right = 124, down = 125, up = 126
    static let f = 3, p = 35, w = 13, q = 12, k = 40, j = 38, l = 37, m = 46, leftBracket = 33, rightBracket = 30, b = 11, s = 1
}

enum KeyNames {
    static let names: [Int: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M",
        45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        53: "Esc", 36: "Return", 49: "Space", 48: "Tab", 51: "Delete", 117: "Fwd Delete",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        33: "[", 30: "]", 27: "-", 24: "=", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 42: "\\", 50: "`",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19",
    ]
    static func describe(code: Int, mods: CGEventFlags) -> String {
        var s = ""
        if mods.contains(.maskControl) { s += "⌃" }
        if mods.contains(.maskAlternate) { s += "⌥" }
        if mods.contains(.maskShift) { s += "⇧" }
        if mods.contains(.maskCommand) { s += "⌘" }
        return s + (names[code] ?? "Key \(code)")
    }
}

// MARK: - Profiles

struct Profile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var bundleIDs: [String] = []
    var touchMode: TouchMode? = nil       // switch to this mode when the app comes to the front
    var mappings: [String: Action] = [:]
    var enabled = true
    var global = false                    // the one profile used for every app

    var isGlobal: Bool { global }
}

// MARK: - Settings

/// The Big Screen look: the colourful default, or a faithful Apple TV style.
enum BigTheme: String, Codable, CaseIterable, Identifiable {
    case tvOS, midnight
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tvOS: return "Apple TV (faithful)"
        case .midnight: return "Midnight (colourful)"
        }
    }
    var blurb: String {
        switch self {
        case .tvOS: return "A dark, neutral background with the focused tile lifting on a big soft shadow, like tvOS."
        case .midnight: return "A softly moving, colourful glow that picks up the selected tile and the album art."
        }
    }
}

enum PlayPauseHandling: String, Codable, CaseIterable, Identifiable {    case global, useMapping, letMacOSHandle
    var id: String { rawValue }
    var title: String {
        switch self {
        case .global: return "Pause or resume whatever is playing, in any app"
        case .useMapping: return "Use each app’s own Play/Pause mapping"
        case .letMacOSHandle: return "Let macOS handle Play/Pause"
        }
    }
}

/// Every kind of on-screen pop-up, so each can be switched off separately.
enum HUDKind: String, Codable, CaseIterable, Identifiable {
    case connection, touchMode, playback, songChange, volume, webVideo, nowPlaying, sleepTimer, mousespot, power, bigScreen, actions
    var id: String { rawValue }
    var title: String {
        switch self {
        case .connection: return "Remote connected / disconnected"
        case .touchMode: return "Touch mode changed"
        case .playback: return "Play / pause / next / previous"
        case .songChange: return "Next song name (after a swipe)"
        case .volume: return "Volume, mute and brightness"
        case .webVideo: return "Web video (seek, speed, mute)"
        case .nowPlaying: return "What's playing (hold Play)"
        case .sleepTimer: return "Sleep timer"
        case .mousespot: return "Mousespot on/off"
        case .power: return "Keep awake, lock, sleep"
        case .bigScreen: return "Messages inside Big Screen"
        case .actions: return "Everything else (apps, desktop, scripts)"
        }
    }
}

enum HUDPosition: String, Codable, CaseIterable, Identifiable {
    case top, middle, bottom
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var yFraction: CGFloat { switch self { case .top: return 0.84; case .middle: return 0.5; case .bottom: return 0.16 } }
}

struct Settings: Codable, Equatable {
    var cursorSpeed: Double = 1.0           // 0.2 … 3
    var acceleration: Double = 1.0          // 0 … 2
    var scrollSpeed: Double = 1.0           // 0.2 … 3
    var naturalScroll = true                // one source of truth: used by Scroll mode, two-finger scroll and edge-scroll gestures alike
    var modeGestures: [String: [String: Action]] = [:]  // per touch mode: TouchMode.rawValue → Trigger.rawValue → Action override
    var keyboardKeys: [String: Action] = [:]            // what the buttons do while the on-screen keyboard is open (Trigger.rawValue → Action)
    var tapToClick = false              // off by default: light touches caused accidental clicks
    var dragOnLongClick = true
    var dragAnything = false                // press-and-slide drags only windows (by the title bar) unless this is on
    var swipeDistance: Double = 0.18        // fraction of the surface
    var holdTime: Double = 0.5              // seconds
    var doubleTapWindow: Double = 0.3       // seconds
    var edgeClickZones = true               // remote mode: click the edges for arrows
    var remoteTapZones = true               // remote mode: tap the glass like a D‑pad — centre = select, around it = up/down/left/right
    var remoteTapCenter: Double = 0.3       // radius of the centre "select" circle (0…0.5 of the glass)
    var repeatVolumeWhileHeld = true
    var defaultTouchMode: TouchMode = .trackpad
    var autoModePerApp = false              // switch touch mode when an app (e.g. Music, TV) comes to the front
    var showHUD = true
    var nowPlayingFull = true               // Big Screen: clicking Now Playing opens a full-screen view with the cover
    var liveAlbumArt = true                 // …and plays Apple Music’s moving album art when there is one
    var bigTheme: BigTheme = .tvOS          // Big Screen look: faithful Apple TV by default
    var youtubeURL = "https://www.youtube.com/tv"   // the remote-friendly YouTube page the built-in app opens
    var youtubeTVUserAgent = true           // pretend to be a TV so YouTube serves its D-pad interface
    var clickSound = false
    var spotRadius: Double = 120
    var spotDim: Double = 0.6
    var spotStyle = "dim"                    // laser pointer look: dim, dot, ring, glow, flashlight
    var spotColor = "red"                    // red, green, blue, yellow, white, pink
    var menuBarBattery = true                // show the remote's battery % next to the menu bar icon
    var hushShortcut = ""                    // name of a Shortcuts shortcut that toggles Do Not Disturb
    var holdToConfirm = false                // ask you to hold Select before risky actions (quit, close, sleep, lock)
    var tutorialDone = false                 // the interactive tutorial has been shown once
    var phoneRemoteEnabled = false           // the built-in phone-remote web server is running
    var phoneRemotePort = 8723               // port the phone remote listens on
    var phoneSetupSeen = false               // the phone-remote setup window has been shown once
    var presenterSlideSeconds: Double = 0    // presenter overlay: seconds per slide for the pacing cue (0 = off)
    var spotAutoOnTouch = false             // show Mousespot whenever you rest a finger
    var playPause: PlayPauseHandling = .global
    var launchAtLogin = false
    var menuShowsRunningApps = true
    var favourites: [String] = ["com.apple.TV", "com.apple.Music", "com.spotify.client", "com.apple.Safari", "com.apple.Photos", "com.apple.iWork.Keynote"]
    var sleepTimerSteps: [Int] = [15, 30, 60, 90]
    // Music swipes: in Remote mode, while Music or Spotify is playing
    var musicSwipes = true
    var musicSwipesVolume = false
    var musicSwipeExceptions: [String] = ["com.apple.iWork.Keynote", "com.microsoft.Powerpoint", "com.apple.Photos", "com.apple.Preview"]
    // Big Screen
    var navStep: Double = 0.16
    var bigScreenShortcuts: [WebShortcut] = WebShortcut.defaults
    // Pop-ups
    var hudDisabled: [String] = []
    var hudDuration: Double = 1.3
    var hudPosition: HUDPosition = .bottom
    var silentVolume = false                // change volume without macOS's own volume bubble
    var volumeStep: Double = 6.25           // % per press (6.25 = one bar of macOS's 16); 0 = let macOS decide
    var holdToSeek = true                   // remote mode: swipe sideways and hold to fast-forward / rewind
    var remoteVolumeEdge = true             // remote mode: slide up/down the left edge of the glass for the volume
    var edgeVolumeSpeed: Double = 1.0       // how much the volume changes per slide
    var remoteVolumeEdgeWidth: Double = 0.16  // how far the remote-mode volume edge reaches into the glass
    var remoteVolumeReverse = false           // slide down for louder instead of up
    var seekHoldDelay: Double = 0.35        // how long you hold still before seeking starts
    var seekByDistance = true                // fast-forward speed follows how far you slide (off: speeds up over time)
    var seekMinSpeed: Double = 2             // × normal speed just after the swipe
    var seekMaxSpeed: Double = 32            // × normal speed with your finger slid all the way out
    var holdToRepeat = true                  // remote mode: swipe up/down and hold to keep moving through a list
    var instantListSwipe = true              // remote mode: up/down steps while you slide, not when you lift
    var listStepSpacing = 0.75               // after the first step, slide this much of a swipe for each further step
    var repeatRate: Double = 6               // steps per second
    var repeatByDistance = true              // slide further to go faster
    // Trackpad feel
    var precision: Double = 0.6             // 0 = same speed always, 1 = very slow & precise when moving slowly
    var smoothing: Double = 0.4             // 0 = raw, 1 = very smooth
    var clickStabiliser = true              // undo the wobble when you press down to click
    // Remote
    var remoteStayAwakeMinutes = 15         // 0 = remote's own default, -1 = as long as the app is open
    // Edge and corner gestures (Trackpad mode)
    var edgeGesturesOn = true
    var edgeZoneSize: Double = 0.1          // how far in from the edge counts as "the edge"
    var spacesSpeed: Double = 1.0           // top-edge Spaces swipe
    var spacesInvert = false
    var spacesShortcutOnly = true           // true: switch with ⌃← / ⌃→ when you let go (reliable; shows the native slide). false: follow-the-finger live swipe (experimental)
    var edgeScrollSpeed: Double = 1.0
    var edgeScrollMomentum = true
    var edgeGestures: [EdgeGesture] = EdgeGesture.defaults
    // Taps (set by the calibration wizard)
    var tapMaxTime: Double = 0.18           // longest touch that still counts as a tap
    var tapMaxTravel: Double = 0.03         // furthest a finger can slide and still tap
    var twoFingerRightClick = true          // two-finger tap = right-click (off: use the Buttons mapping)
    var tapDrag = true                      // tap, then touch again and slide = drag
    var tapDragWindow: Double = 0.5         // how long after a tap you can touch again to start a drag
    // Big Screen extras
    var recentRows = true                   // Recently played / Recently added in Apple Music
    var rememberSearches = true
    var recentSearches: [String] = []
    var widgetBattery = true
    var widgetCalendar = false
    var widgetWeather = false
    var weatherCity = ""
    var weatherCelsius = true
    var bigWidgets: [String] = BigWidget.defaults   // Big Screen widget row: which ones, in order
    // Media
    var systemNowPlaying = true             // read what's playing in any app (may not work on newer macOS)
    // Air mouse (experimental)
    var airMouse = false
    var airX = ""                           // "page:usage" of the signal for left/right
    var airY = ""
    var airSpeed: Double = 1.0
    var airInvertX = false
    var airInvertY = false
    var airNeedsTouch = true                // only moves while a finger rests on the glass

    func hudEnabled(_ k: HUDKind) -> Bool { showHUD && !hudDisabled.contains(k.rawValue) }

    init() {}

    // Tolerant decoding: new settings added in later versions fall back to defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        cursorSpeed = try c.decodeIfPresent(Double.self, forKey: .cursorSpeed) ?? d.cursorSpeed
        acceleration = try c.decodeIfPresent(Double.self, forKey: .acceleration) ?? d.acceleration
        scrollSpeed = try c.decodeIfPresent(Double.self, forKey: .scrollSpeed) ?? d.scrollSpeed
        naturalScroll = try c.decodeIfPresent(Bool.self, forKey: .naturalScroll) ?? d.naturalScroll
        modeGestures = try c.decodeIfPresent([String: [String: Action]].self, forKey: .modeGestures) ?? d.modeGestures
        keyboardKeys = try c.decodeIfPresent([String: Action].self, forKey: .keyboardKeys) ?? d.keyboardKeys
        tapToClick = try c.decodeIfPresent(Bool.self, forKey: .tapToClick) ?? d.tapToClick
        dragOnLongClick = try c.decodeIfPresent(Bool.self, forKey: .dragOnLongClick) ?? d.dragOnLongClick
        dragAnything = try c.decodeIfPresent(Bool.self, forKey: .dragAnything) ?? d.dragAnything
        swipeDistance = try c.decodeIfPresent(Double.self, forKey: .swipeDistance) ?? d.swipeDistance
        holdTime = try c.decodeIfPresent(Double.self, forKey: .holdTime) ?? d.holdTime
        doubleTapWindow = try c.decodeIfPresent(Double.self, forKey: .doubleTapWindow) ?? d.doubleTapWindow
        edgeClickZones = try c.decodeIfPresent(Bool.self, forKey: .edgeClickZones) ?? d.edgeClickZones
        remoteTapZones = try c.decodeIfPresent(Bool.self, forKey: .remoteTapZones) ?? d.remoteTapZones
        remoteTapCenter = try c.decodeIfPresent(Double.self, forKey: .remoteTapCenter) ?? d.remoteTapCenter
        repeatVolumeWhileHeld = try c.decodeIfPresent(Bool.self, forKey: .repeatVolumeWhileHeld) ?? d.repeatVolumeWhileHeld
        defaultTouchMode = try c.decodeIfPresent(TouchMode.self, forKey: .defaultTouchMode) ?? d.defaultTouchMode
        autoModePerApp = try c.decodeIfPresent(Bool.self, forKey: .autoModePerApp) ?? d.autoModePerApp
        showHUD = try c.decodeIfPresent(Bool.self, forKey: .showHUD) ?? d.showHUD
        nowPlayingFull = try c.decodeIfPresent(Bool.self, forKey: .nowPlayingFull) ?? d.nowPlayingFull
        liveAlbumArt = try c.decodeIfPresent(Bool.self, forKey: .liveAlbumArt) ?? d.liveAlbumArt
        bigTheme = try c.decodeIfPresent(BigTheme.self, forKey: .bigTheme) ?? d.bigTheme
        youtubeURL = try c.decodeIfPresent(String.self, forKey: .youtubeURL) ?? d.youtubeURL
        youtubeTVUserAgent = try c.decodeIfPresent(Bool.self, forKey: .youtubeTVUserAgent) ?? d.youtubeTVUserAgent
        clickSound = try c.decodeIfPresent(Bool.self, forKey: .clickSound) ?? d.clickSound
        spotRadius = try c.decodeIfPresent(Double.self, forKey: .spotRadius) ?? d.spotRadius
        spotDim = try c.decodeIfPresent(Double.self, forKey: .spotDim) ?? d.spotDim
        spotStyle = try c.decodeIfPresent(String.self, forKey: .spotStyle) ?? d.spotStyle
        spotColor = try c.decodeIfPresent(String.self, forKey: .spotColor) ?? d.spotColor
        menuBarBattery = try c.decodeIfPresent(Bool.self, forKey: .menuBarBattery) ?? d.menuBarBattery
        hushShortcut = try c.decodeIfPresent(String.self, forKey: .hushShortcut) ?? d.hushShortcut
        holdToConfirm = try c.decodeIfPresent(Bool.self, forKey: .holdToConfirm) ?? d.holdToConfirm
        tutorialDone = try c.decodeIfPresent(Bool.self, forKey: .tutorialDone) ?? d.tutorialDone
        phoneRemoteEnabled = try c.decodeIfPresent(Bool.self, forKey: .phoneRemoteEnabled) ?? d.phoneRemoteEnabled
        phoneRemotePort = try c.decodeIfPresent(Int.self, forKey: .phoneRemotePort) ?? d.phoneRemotePort
        phoneSetupSeen = try c.decodeIfPresent(Bool.self, forKey: .phoneSetupSeen) ?? d.phoneSetupSeen
        presenterSlideSeconds = try c.decodeIfPresent(Double.self, forKey: .presenterSlideSeconds) ?? d.presenterSlideSeconds
        spotAutoOnTouch = try c.decodeIfPresent(Bool.self, forKey: .spotAutoOnTouch) ?? d.spotAutoOnTouch
        playPause = try c.decodeIfPresent(PlayPauseHandling.self, forKey: .playPause) ?? d.playPause
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        menuShowsRunningApps = try c.decodeIfPresent(Bool.self, forKey: .menuShowsRunningApps) ?? d.menuShowsRunningApps
        favourites = try c.decodeIfPresent([String].self, forKey: .favourites) ?? d.favourites
        sleepTimerSteps = try c.decodeIfPresent([Int].self, forKey: .sleepTimerSteps) ?? d.sleepTimerSteps
        musicSwipes = try c.decodeIfPresent(Bool.self, forKey: .musicSwipes) ?? d.musicSwipes
        musicSwipesVolume = try c.decodeIfPresent(Bool.self, forKey: .musicSwipesVolume) ?? d.musicSwipesVolume
        musicSwipeExceptions = try c.decodeIfPresent([String].self, forKey: .musicSwipeExceptions) ?? d.musicSwipeExceptions
        navStep = try c.decodeIfPresent(Double.self, forKey: .navStep) ?? d.navStep
        bigScreenShortcuts = try c.decodeIfPresent([WebShortcut].self, forKey: .bigScreenShortcuts) ?? d.bigScreenShortcuts
        hudDisabled = try c.decodeIfPresent([String].self, forKey: .hudDisabled) ?? d.hudDisabled
        hudDuration = try c.decodeIfPresent(Double.self, forKey: .hudDuration) ?? d.hudDuration
        hudPosition = try c.decodeIfPresent(HUDPosition.self, forKey: .hudPosition) ?? d.hudPosition
        silentVolume = try c.decodeIfPresent(Bool.self, forKey: .silentVolume) ?? d.silentVolume
        volumeStep = try c.decodeIfPresent(Double.self, forKey: .volumeStep) ?? d.volumeStep
        holdToSeek = try c.decodeIfPresent(Bool.self, forKey: .holdToSeek) ?? d.holdToSeek
        remoteVolumeEdge = try c.decodeIfPresent(Bool.self, forKey: .remoteVolumeEdge) ?? d.remoteVolumeEdge
        edgeVolumeSpeed = try c.decodeIfPresent(Double.self, forKey: .edgeVolumeSpeed) ?? d.edgeVolumeSpeed
        remoteVolumeEdgeWidth = try c.decodeIfPresent(Double.self, forKey: .remoteVolumeEdgeWidth) ?? d.remoteVolumeEdgeWidth
        remoteVolumeReverse = try c.decodeIfPresent(Bool.self, forKey: .remoteVolumeReverse) ?? d.remoteVolumeReverse
        seekHoldDelay = try c.decodeIfPresent(Double.self, forKey: .seekHoldDelay) ?? d.seekHoldDelay
        seekByDistance = try c.decodeIfPresent(Bool.self, forKey: .seekByDistance) ?? d.seekByDistance
        seekMinSpeed = try c.decodeIfPresent(Double.self, forKey: .seekMinSpeed) ?? d.seekMinSpeed
        seekMaxSpeed = try c.decodeIfPresent(Double.self, forKey: .seekMaxSpeed) ?? d.seekMaxSpeed
        holdToRepeat = try c.decodeIfPresent(Bool.self, forKey: .holdToRepeat) ?? d.holdToRepeat
        instantListSwipe = try c.decodeIfPresent(Bool.self, forKey: .instantListSwipe) ?? d.instantListSwipe
        listStepSpacing = try c.decodeIfPresent(Double.self, forKey: .listStepSpacing) ?? d.listStepSpacing
        repeatRate = try c.decodeIfPresent(Double.self, forKey: .repeatRate) ?? d.repeatRate
        repeatByDistance = try c.decodeIfPresent(Bool.self, forKey: .repeatByDistance) ?? d.repeatByDistance
        precision = try c.decodeIfPresent(Double.self, forKey: .precision) ?? d.precision
        smoothing = try c.decodeIfPresent(Double.self, forKey: .smoothing) ?? d.smoothing
        clickStabiliser = try c.decodeIfPresent(Bool.self, forKey: .clickStabiliser) ?? d.clickStabiliser
        remoteStayAwakeMinutes = try c.decodeIfPresent(Int.self, forKey: .remoteStayAwakeMinutes) ?? d.remoteStayAwakeMinutes
        edgeGesturesOn = try c.decodeIfPresent(Bool.self, forKey: .edgeGesturesOn) ?? d.edgeGesturesOn
        edgeZoneSize = try c.decodeIfPresent(Double.self, forKey: .edgeZoneSize) ?? d.edgeZoneSize
        edgeScrollSpeed = try c.decodeIfPresent(Double.self, forKey: .edgeScrollSpeed) ?? d.edgeScrollSpeed
        edgeScrollMomentum = try c.decodeIfPresent(Bool.self, forKey: .edgeScrollMomentum) ?? d.edgeScrollMomentum
        spacesSpeed = try c.decodeIfPresent(Double.self, forKey: .spacesSpeed) ?? d.spacesSpeed
        spacesInvert = try c.decodeIfPresent(Bool.self, forKey: .spacesInvert) ?? d.spacesInvert
        spacesShortcutOnly = try c.decodeIfPresent(Bool.self, forKey: .spacesShortcutOnly) ?? d.spacesShortcutOnly
        edgeGestures = (try? c.decodeIfPresent([EdgeGesture].self, forKey: .edgeGestures)) ?? d.edgeGestures
        tapMaxTime = try c.decodeIfPresent(Double.self, forKey: .tapMaxTime) ?? d.tapMaxTime
        tapMaxTravel = try c.decodeIfPresent(Double.self, forKey: .tapMaxTravel) ?? d.tapMaxTravel
        twoFingerRightClick = try c.decodeIfPresent(Bool.self, forKey: .twoFingerRightClick) ?? d.twoFingerRightClick
        tapDrag = try c.decodeIfPresent(Bool.self, forKey: .tapDrag) ?? d.tapDrag
        tapDragWindow = try c.decodeIfPresent(Double.self, forKey: .tapDragWindow) ?? d.tapDragWindow
        recentRows = try c.decodeIfPresent(Bool.self, forKey: .recentRows) ?? d.recentRows
        rememberSearches = try c.decodeIfPresent(Bool.self, forKey: .rememberSearches) ?? d.rememberSearches
        recentSearches = try c.decodeIfPresent([String].self, forKey: .recentSearches) ?? d.recentSearches
        widgetBattery = try c.decodeIfPresent(Bool.self, forKey: .widgetBattery) ?? d.widgetBattery
        widgetCalendar = try c.decodeIfPresent(Bool.self, forKey: .widgetCalendar) ?? d.widgetCalendar
        widgetWeather = try c.decodeIfPresent(Bool.self, forKey: .widgetWeather) ?? d.widgetWeather
        weatherCity = try c.decodeIfPresent(String.self, forKey: .weatherCity) ?? d.weatherCity
        weatherCelsius = try c.decodeIfPresent(Bool.self, forKey: .weatherCelsius) ?? d.weatherCelsius
        bigWidgets = try c.decodeIfPresent([String].self, forKey: .bigWidgets) ?? d.bigWidgets
        systemNowPlaying = try c.decodeIfPresent(Bool.self, forKey: .systemNowPlaying) ?? d.systemNowPlaying
        airMouse = try c.decodeIfPresent(Bool.self, forKey: .airMouse) ?? d.airMouse
        airX = try c.decodeIfPresent(String.self, forKey: .airX) ?? d.airX
        airY = try c.decodeIfPresent(String.self, forKey: .airY) ?? d.airY
        airSpeed = try c.decodeIfPresent(Double.self, forKey: .airSpeed) ?? d.airSpeed
        airInvertX = try c.decodeIfPresent(Bool.self, forKey: .airInvertX) ?? d.airInvertX
        airInvertY = try c.decodeIfPresent(Bool.self, forKey: .airInvertY) ?? d.airInvertY
        airNeedsTouch = try c.decodeIfPresent(Bool.self, forKey: .airNeedsTouch) ?? d.airNeedsTouch
    }
}

struct WebShortcut: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var url: String
    var search: String? = nil          // search link with {q} where the words go

    func searchURL(_ q: String) -> URL? {
        guard let s = search, s.contains("{q}"),
              let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: s.replacingOccurrences(of: "{q}", with: enc))
    }

    static let defaults: [WebShortcut] = [
        WebShortcut(name: "YouTube", url: "https://www.youtube.com", search: "https://www.youtube.com/results?search_query={q}"),
        WebShortcut(name: "Netflix", url: "https://www.netflix.com/browse", search: "https://www.netflix.com/search?q={q}"),
        WebShortcut(name: "Disney+", url: "https://www.disneyplus.com"),
        WebShortcut(name: "Prime Video", url: "https://www.primevideo.com", search: "https://www.primevideo.com/search?phrase={q}"),
        WebShortcut(name: "Stan", url: "https://www.stan.com.au"),
        WebShortcut(name: "ABC iview", url: "https://iview.abc.net.au"),
        WebShortcut(name: "SBS On Demand", url: "https://www.sbs.com.au/ondemand"),
        WebShortcut(name: "Apple TV+", url: "https://tv.apple.com", search: "https://tv.apple.com/search?term={q}"),
    ]
}

struct Config: Codable {
    var version = 9
    var settings = Settings()
    var profiles: [Profile] = Presets.all()
}

// MARK: - Built-in presets

enum Presets {
    static let cmd = CGEventFlags.maskCommand, opt = CGEventFlags.maskAlternate, shift = CGEventFlags.maskShift, ctrl = CGEventFlags.maskControl

    static func global() -> Profile {
        var p = Profile(name: "Global")
        p.global = true
        p.mappings = [
            Trigger.menuTap.rawValue: .key(KeyCode.escape),
            Trigger.menuHold.rawValue: .k(.appSwitcher),
            Trigger.homeTap.rawValue: .k(.bigScreen),
            Trigger.homeDouble.rawValue: .k(.couchMenu),
            Trigger.homeHold.rawValue: .k(.missionControl),
            Trigger.siriTap.rawValue: .k(.cycleTouchMode),
            Trigger.siriDouble.rawValue: .k(.keyboardPanel),
            Trigger.siriHold.rawValue: .k(.mouseSpot),
            Trigger.playTap.rawValue: .k(.playPause),
            // no double-press on Play: a single press responds instantly. Swipe to skip songs instead.
            Trigger.playHold.rawValue: .k(.showHUDInfo),
            Trigger.volUp.rawValue: .k(.volumeUp),
            Trigger.volDown.rawValue: .k(.volumeDown),
            Trigger.select.rawValue: .key(KeyCode.ret),
            Trigger.selectHold.rawValue: .key(KeyCode.space),
            Trigger.swipeUp.rawValue: .key(KeyCode.up), Trigger.swipeDown.rawValue: .key(KeyCode.down),
            Trigger.swipeLeft.rawValue: .key(KeyCode.left), Trigger.swipeRight.rawValue: .key(KeyCode.right),
            Trigger.clickUp.rawValue: .key(KeyCode.up), Trigger.clickDown.rawValue: .key(KeyCode.down),
            Trigger.clickLeft.rawValue: .key(KeyCode.left), Trigger.clickRight.rawValue: .key(KeyCode.right),
            Trigger.twoFingerTap.rawValue: .k(.rightClick),
        ]
        return p
    }

    static func music(_ name: String, _ ids: [String]) -> Profile {
        Profile(name: name, bundleIDs: ids, touchMode: .remote, mappings: [
            Trigger.select.rawValue: .k(.playPause),
            Trigger.swipeLeft.rawValue: .k(.prevTrack), Trigger.swipeRight.rawValue: .k(.nextTrack),
            Trigger.clickLeft.rawValue: .k(.prevTrack), Trigger.clickRight.rawValue: .k(.nextTrack),
            Trigger.swipeUp.rawValue: .k(.volumeUp), Trigger.swipeDown.rawValue: .k(.volumeDown),
        ])
    }

    static func video(_ name: String, _ ids: [String], fullscreen: Action) -> Profile {
        Profile(name: name, bundleIDs: ids, touchMode: .remote, mappings: [
            Trigger.select.rawValue: .key(KeyCode.space),
            Trigger.selectHold.rawValue: fullscreen,
            Trigger.swipeLeft.rawValue: .key(KeyCode.left), Trigger.swipeRight.rawValue: .key(KeyCode.right),
            Trigger.swipeUp.rawValue: .k(.volumeUp), Trigger.swipeDown.rawValue: .k(.volumeDown),
            Trigger.playTap.rawValue: .key(KeyCode.space),
        ])
    }

    static func slides(_ name: String, _ ids: [String], start: Action) -> Profile {
        Profile(name: name, bundleIDs: ids, touchMode: .remote, mappings: [
            Trigger.select.rawValue: .key(KeyCode.right),
            Trigger.swipeRight.rawValue: .key(KeyCode.right), Trigger.clickRight.rawValue: .key(KeyCode.right),
            Trigger.swipeLeft.rawValue: .key(KeyCode.left), Trigger.clickLeft.rawValue: .key(KeyCode.left),
            Trigger.swipeDown.rawValue: .key(KeyCode.right), Trigger.swipeUp.rawValue: .key(KeyCode.left),
            Trigger.playTap.rawValue: start,
            Trigger.playDouble.rawValue: .key(KeyCode.b),          // black screen
            Trigger.siriTap.rawValue: .k(.mouseSpot),
        ])
    }

    static func browser() -> Profile {
        Profile(name: "Web browsers", bundleIDs: ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac",
                                                   "com.brave.Browser", "company.thebrowser.Browser"],
                touchMode: .trackpad, mappings: [
            Trigger.playTap.rawValue: .k(.webPlayPause),
            Trigger.playDouble.rawValue: .k(.webFullscreen),
            Trigger.menuTap.rawValue: .key(KeyCode.leftBracket, cmd),
            Trigger.swipeLeft.rawValue: .k(.webBack10), Trigger.swipeRight.rawValue: .k(.webForward10),
            Trigger.swipeUp.rawValue: .k(.webFaster), Trigger.swipeDown.rawValue: .k(.webSlower),
            Trigger.select.rawValue: .k(.webPlayPause),
        ])
    }

    /// Version 2: TV button opens Big Screen, and Play no longer waits for a double-press.
    /// Only changes buttons that are still on their old defaults.
    static func migrateToV2(_ c: inout Config) {
        if let g = c.profiles.firstIndex(where: { $0.isGlobal }) {
            var m = c.profiles[g].mappings
            if m[Trigger.playDouble.rawValue] == .k(.nextTrack) { m[Trigger.playDouble.rawValue] = nil }
            if m[Trigger.homeTap.rawValue] == .k(.couchMenu) {
                m[Trigger.homeTap.rawValue] = .k(.bigScreen)
                if m[Trigger.homeDouble.rawValue] == nil || m[Trigger.homeDouble.rawValue] == .k(.showDesktop) {
                    m[Trigger.homeDouble.rawValue] = .k(.couchMenu)
                }
            }
            c.profiles[g].mappings = m
        }
        c.version = 2
    }

    /// Version 3: more app presets, search links, and tap-to-click off (it caused accidental clicks).
    static func migrateToV3(_ c: inout Config) {
        let names = Set(c.profiles.map(\.name))
        let used = Set(c.profiles.flatMap(\.bundleIDs))
        for p in extras() where !names.contains(p.name) {
            var q = p
            q.bundleIDs = q.bundleIDs.filter { !used.contains($0) }
            if !q.bundleIDs.isEmpty { c.profiles.append(q) }
        }
        for i in c.settings.bigScreenShortcuts.indices where c.settings.bigScreenShortcuts[i].search == nil {
            if let d = WebShortcut.defaults.first(where: { $0.name == c.settings.bigScreenShortcuts[i].name }) {
                c.settings.bigScreenShortcuts[i].search = d.search
            }
        }
        c.settings.tapToClick = false
        c.version = 3
    }

    /// Version 4: even more apps
    /// Version 5: swipe sideways along the top edge of the glass to change Spaces
    /// Version 6: edge gestures start closer to the edge, and the top edge switches Spaces by following
    /// your finger (like a trackpad swipe) instead of pressing ⌃← / ⌃→
    /// Version 7: opening an app such as Music or TV no longer switches the touch mode unless you turn it on
    /// Version 8: Play/Pause works on whatever is playing in any app, not just the app in front
    /// Version 9: the Spaces swipe switches with the reliable ⌃← / ⌃→ shortcut (the live follow-the-finger
    /// version is kept as an experimental toggle, since macOS 27 ignores the synthesized trackpad gesture)
    static func migrateToV9(_ c: inout Config) {
        c.settings.spacesShortcutOnly = true
        c.version = 9
    }

    static func migrateToV8(_ c: inout Config) {
        if c.settings.playPause == .useMapping { c.settings.playPause = .global }
        c.version = 8
    }

    static func migrateToV7(_ c: inout Config) {
        c.settings.autoModePerApp = false
        c.version = 7
    }

    static func migrateToV6(_ c: inout Config) {
        if abs(c.settings.edgeZoneSize - 0.2) < 0.001 { c.settings.edgeZoneSize = 0.1 }
        let isOldSpaces: (EdgeGesture) -> Bool = { g in
            g.zone == .topEdge && (g.action.kind == .nextSpace || g.action.kind == .prevSpace)
        }
        if let i = c.settings.edgeGestures.firstIndex(where: isOldSpaces) {
            let wasOn = c.settings.edgeGestures.filter(isOldSpaces).contains { $0.enabled }
            c.settings.edgeGestures.removeAll(where: isOldSpaces)
            c.settings.edgeGestures.insert(EdgeGesture(enabled: wasOn, zone: .topEdge, motion: .spaceSwipe), at: min(i, c.settings.edgeGestures.count))
        } else if !c.settings.edgeGestures.contains(where: { $0.motion == .spaceSwipe }) {
            c.settings.edgeGestures.insert(EdgeGesture(zone: .topEdge, motion: .spaceSwipe), at: min(1, c.settings.edgeGestures.count))
        }
        c.version = 6
    }

    static func migrateToV5(_ c: inout Config) {
        let g = c.settings.edgeGestures
        let hasTopSwipe = g.contains { $0.zone == .topEdge && ($0.motion == .swipeLeft || $0.motion == .swipeRight) }
        if !hasTopSwipe {
            c.settings.edgeGestures += EdgeGesture.defaults.filter { $0.zone == .topEdge }
        }
        c.version = 5
    }

    static func migrateToV4(_ c: inout Config) {
        let names = Set(c.profiles.map(\.name))
        let used = Set(c.profiles.flatMap(\.bundleIDs))
        for p in extrasV4() where !names.contains(p.name) {
            var q = p
            q.bundleIDs = q.bundleIDs.filter { !used.contains($0) }
            if !q.bundleIDs.isEmpty { c.profiles.append(q) }
        }
        c.version = 4
    }

    static func extrasV4() -> [Profile] {
        [
            // Browsers that can't be scripted: these use the keyboard shortcuts most web players understand
            Profile(name: "More browsers", bundleIDs: ["company.thebrowser.dia", "org.mozilla.firefox", "com.operasoftware.Opera",
                                                       "com.vivaldi.Vivaldi", "org.chromium.Chromium", "app.zen-browser.zen"],
                    touchMode: .trackpad, mappings: [
                Trigger.playTap.rawValue: .key(KeyCode.space),
                Trigger.playDouble.rawValue: .key(KeyCode.f),
                Trigger.menuTap.rawValue: .key(KeyCode.leftBracket, cmd),
            ]),
            video("Media centres", ["tv.plex.htpc", "com.github.iwalton3.jellyfin-media-player", "com.stremio.stremio",
                                    "com.movist.MovistPro", "com.firecore.infuse.pro"], fullscreen: .key(KeyCode.f)),
            music("More music players", ["com.coppertino.Vox", "com.swinsian.Swinsian", "com.audirvana.Audirvana-Studio",
                                         "com.roon.Roon", "com.apple.Music.Classical"]),
            Profile(name: "Game launchers", bundleIDs: ["com.epicgames.EpicGamesLauncher", "com.gog.galaxy", "net.battle.app"],
                    touchMode: .remote, mappings: [
                Trigger.select.rawValue: .key(KeyCode.ret),
                Trigger.menuTap.rawValue: .key(KeyCode.escape),
            ]),
            Profile(name: "Discord", bundleIDs: ["com.hnc.Discord"], touchMode: .trackpad, mappings: [
                Trigger.playTap.rawValue: .key(KeyCode.m, [cmd, shift]),   // mute (⌘⇧M)
                Trigger.playHold.rawValue: .key(2, [cmd, shift]),          // deafen (⌘⇧D)
            ]),
        ]
    }

    /// Extra app support added in version 3
    static func extras() -> [Profile] {
        [
            music("Other music apps", ["com.tidal.desktop", "com.amazon.music", "com.deezer.deezer-desktop", "tv.plex.plexamp"]),
            video("More video players", ["com.firecore.infuse", "io.mpv", "com.Eltima.ElmediaPlayer"], fullscreen: .k(.fullScreen)),
            Profile(name: "Zoom", bundleIDs: ["us.zoom.xos"], touchMode: .trackpad, mappings: [
                Trigger.playTap.rawValue: .key(0, [cmd, shift]),          // mute / unmute (⌘⇧A)
                Trigger.playHold.rawValue: .key(9, [cmd, shift]),         // camera on/off (⌘⇧V)
                Trigger.siriDouble.rawValue: .key(1, [cmd, shift]),       // share screen (⌘⇧S)
            ]),
            Profile(name: "Microsoft Teams", bundleIDs: ["com.microsoft.teams2"], touchMode: .trackpad, mappings: [
                Trigger.playTap.rawValue: .key(KeyCode.m, [cmd, shift]),  // mute (⌘⇧M)
                Trigger.playHold.rawValue: .key(31, [cmd, shift]),        // camera (⌘⇧O)
            ]),
            Profile(name: "Books", bundleIDs: ["com.apple.iBooksX"], touchMode: .remote, mappings: [
                Trigger.select.rawValue: .key(KeyCode.right),
                Trigger.swipeLeft.rawValue: .key(KeyCode.left), Trigger.swipeRight.rawValue: .key(KeyCode.right),
                Trigger.clickLeft.rawValue: .key(KeyCode.left), Trigger.clickRight.rawValue: .key(KeyCode.right),
            ]),
            Profile(name: "Steam", bundleIDs: ["com.valvesoftware.steam"], touchMode: .remote, mappings: [
                Trigger.select.rawValue: .key(KeyCode.ret),
                Trigger.menuTap.rawValue: .key(KeyCode.escape),
            ]),
            Profile(name: "Finder", bundleIDs: ["com.apple.finder"], touchMode: nil, mappings: [
                Trigger.select.rawValue: .key(KeyCode.down, cmd),         // open
                Trigger.selectHold.rawValue: .key(KeyCode.space),         // Quick Look
                Trigger.menuTap.rawValue: .key(KeyCode.up, cmd),          // up a folder
            ]),
        ]
    }

    static func all() -> [Profile] {
        [
            global(),
            music("Music & Spotify", ["com.apple.Music", "com.spotify.client"]),
            video("Video players", ["com.apple.TV", "com.apple.QuickTimePlayerX", "com.colliderli.iina", "org.videolan.vlc",
                                    "com.apple.podcasts", "tv.plex.desktop", "org.xbmc.kodi"],
                  fullscreen: .k(.fullScreen)),
            slides("Keynote", ["com.apple.iWork.Keynote"], start: .key(KeyCode.p, [cmd, opt])),
            slides("PowerPoint", ["com.microsoft.Powerpoint"], start: .key(KeyCode.ret, [cmd, shift])),
            Profile(name: "Photos & Preview", bundleIDs: ["com.apple.Photos", "com.apple.Preview"], touchMode: .remote, mappings: [
                Trigger.select.rawValue: .key(KeyCode.space),
                Trigger.swipeLeft.rawValue: .key(KeyCode.left), Trigger.swipeRight.rawValue: .key(KeyCode.right),
                Trigger.swipeUp.rawValue: .key(24, cmd), Trigger.swipeDown.rawValue: .key(27, cmd),
            ]),
            browser(),
        ] + extras() + extrasV4()
    }
}

// MARK: - Store

final class ConfigStore: ObservableObject {
    static let shared = ConfigStore()

    @Published var config: Config { didSet { scheduleSave() } }

    let folder: URL
    var fileURL: URL { folder.appendingPathComponent("config.json") }
    private var saveWork: DispatchWorkItem?

    private init() {
        folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Couch Remote", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        if let data = try? Data(contentsOf: url), var c = try? JSONDecoder().decode(Config.self, from: data) {
            let migrate = c.version < 9
            if c.version < 2 { Presets.migrateToV2(&c) }
            if c.version < 3 { Presets.migrateToV3(&c) }
            if c.version < 4 { Presets.migrateToV4(&c) }
            if c.version < 5 { Presets.migrateToV5(&c) }
            if c.version < 6 { Presets.migrateToV6(&c) }
            if c.version < 7 { Presets.migrateToV7(&c) }
            if c.version < 8 { Presets.migrateToV8(&c) }
            if c.version < 9 { Presets.migrateToV9(&c) }
            config = c
            if migrate { saveNow() }
        } else {
            if FileManager.default.fileExists(atPath: url.path) {   // keep a copy of anything we couldn't read
                try? FileManager.default.copyItem(at: url, to: folder.appendingPathComponent("config-unreadable-\(Int(Date().timeIntervalSince1970)).json"))
            }
            config = Config()
        }
    }

    var settings: Settings { config.settings }

    private func scheduleSave() {
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }

    func saveNow() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(config) { try? data.write(to: fileURL, options: .atomic) }
    }

    /// Finds the action for an input: the front app's profile first, then Global.
    func action(for trigger: Trigger, bundleID: String?) -> (Action, String)? {
        if let bid = bundleID,
           let p = config.profiles.first(where: { $0.enabled && $0.bundleIDs.contains(bid) }),
           let a = p.mappings[trigger.rawValue], a.kind != .inherit {
            return (a, p.name)
        }
        if let g = config.profiles.first(where: { $0.isGlobal }), let a = g.mappings[trigger.rawValue] {
            return (a, g.name)
        }
        return nil
    }

    func profile(for bundleID: String?) -> Profile? {
        guard let bid = bundleID else { return nil }
        return config.profiles.first(where: { $0.enabled && $0.bundleIDs.contains(bid) })
    }

    func backup(to url: URL) throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(config).write(to: url, options: .atomic)
    }

    func restore(from url: URL) throws {
        config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
    }

    func resetToDefaults() { config = Config() }
}
