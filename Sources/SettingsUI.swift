// SettingsUI.swift — main window: Overview, Touchpad, Extras, Backup
import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

enum Pane: String, CaseIterable, Identifiable {
    case overview = "Overview", buttons = "Buttons", profiles = "App Profiles", touch = "Touchpad", gestures = "Gestures",
         bigScreen = "Big Screen", menu = "Couch Menu", popups = "Pop-ups", extras = "Extras", backup = "Backup"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: return "appletvremote.gen1.fill"
        case .buttons: return "button.programmable"
        case .profiles: return "square.stack.3d.up.fill"
        case .touch: return "hand.point.up.left.fill"
        case .gestures: return "hand.draw.fill"
        case .bigScreen: return "tv.inset.filled"
        case .menu: return "list.bullet.rectangle.fill"
        case .popups: return "bubble.left.fill"
        case .extras: return "sparkles"
        case .backup: return "externaldrive.fill"
        }
    }
    var tint: Color {
        switch self {
        case .overview: return Color(red: 0.45, green: 0.30, blue: 0.95)
        case .buttons: return Color(red: 0.20, green: 0.50, blue: 0.98)
        case .profiles: return Color(red: 0.98, green: 0.55, blue: 0.15)
        case .touch: return Color(red: 0.10, green: 0.66, blue: 0.75)
        case .gestures: return Color(red: 0.16, green: 0.70, blue: 0.42)
        case .bigScreen: return Color(red: 0.93, green: 0.27, blue: 0.45)
        case .menu: return Color(red: 0.36, green: 0.40, blue: 0.95)
        case .popups: return Color(red: 0.95, green: 0.40, blue: 0.30)
        case .extras: return Color(red: 0.85, green: 0.35, blue: 0.85)
        case .backup: return Color(red: 0.45, green: 0.48, blue: 0.55)
        }
    }
    var subtitle: String {
        switch self {
        case .overview: return "Your remote at a glance"
        case .buttons: return "What each button and swipe does"
        case .profiles: return "Different layouts for different apps"
        case .touch: return "How the glass touch surface feels"
        case .gestures: return "Edge and corner shortcuts on the glass"
        case .bigScreen: return "The full-screen home, widgets and music"
        case .menu: return "The quick pop-up menu"
        case .popups: return "The little messages on screen"
        case .extras: return "Seeking, volume slide, air mouse and more"
        case .backup: return "Save, restore and share your setup"
        }
    }
}

/// A small coloured, rounded icon, like System Settings
struct PaneBadge: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 24
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [tint, tint.opacity(0.75)], startPoint: .top, endPoint: .bottom)))
            .shadow(color: tint.opacity(0.3), radius: 2, y: 1)
    }
}

struct MainView: View {
    @ObservedObject private var ui = UIState.shared
    @ObservedObject private var engine = Engine.shared

    // A hand-built sidebar: plain buttons always respond to clicks,
    // even in a menu-bar app where list selection can be unreliable.
    var body: some View {
        let pane = ui.pane ?? .overview
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                // Which remote, and whether it's connected
                HStack(spacing: 10) {
                    PaneBadge(symbol: "appletvremote.gen1.fill", tint: Color(white: 0.25), size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Couch Remote").font(.system(size: 14, weight: .bold))
                        HStack(spacing: 5) {
                            Circle().fill(engine.connected ? Color.green : Color.orange).frame(width: 7, height: 7)
                            Text(engine.connected ? (engine.battery.map { "Connected · \($0)%" } ?? "Connected") : "Not connected")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 14)
                ForEach(Pane.allCases) { p in
                    let on = pane == p
                    Button { ui.pane = p } label: {
                        HStack(spacing: 10) {
                            PaneBadge(symbol: p.symbol, tint: p.tint)
                            Text(p.rawValue).font(.system(size: 13, weight: on ? .semibold : .regular))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? Color.accentColor.opacity(0.22) : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button { BigScreen.shared.open() } label: {
                    Label("Open Big Screen", systemImage: "tv.inset.filled").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
            .padding(.horizontal, 10).padding(.top, 40).padding(.bottom, 14)
            .frame(width: 220)
            .background(.regularMaterial)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    PaneBadge(symbol: pane.symbol, tint: pane.tint, size: 42)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(pane.rawValue).font(.system(size: 24, weight: .bold, design: .rounded))
                        Text(pane.subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
                Group {
                    switch pane {
                    case .overview: OverviewTab()
                    case .buttons: ButtonsTab(profileID: $ui.profileID)
                    case .profiles: ProfilesTab(editButtons: { id in ui.profileID = id; ui.pane = .buttons })
                    case .touch: TouchTab()
                    case .gestures: GesturesTab()
                    case .bigScreen: BigScreenTab()
                    case .menu: MenuTab()
                    case .popups: PopupsTab()
                    case .extras: ExtrasTab()
                    case .backup: BackupTab()
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 36).padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 980, minHeight: 660)
    }
}

// MARK: - Live remote picture (1st‑gen Siri Remote layout)

struct RemoteDrawing: View {
    @ObservedObject var engine = Engine.shared

    private func key(_ name: String, _ label: String, _ symbol: String? = nil) -> some View {
        let on = engine.pressed.contains(name)
        return ZStack {
            Circle().fill(on ? Color.accentColor : Color(white: 0.16))
            if let s = symbol { Image(systemName: s).font(.system(size: 14, weight: .semibold)) }
            else { Text(label).font(.system(size: 11, weight: .bold)) }
        }
        .foregroundStyle(.white)
        .frame(width: 44, height: 44)
        .scaleEffect(on ? 0.92 : 1)
        .animation(.easeOut(duration: 0.08), value: on)
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(engine.pressed.contains("select") ? Color.accentColor : .clear, lineWidth: 3))
                GeometryReader { g in
                    if let p = engine.touchPoint {
                        Circle().fill(Color.accentColor.opacity(0.85)).frame(width: 22, height: 22)
                            .position(x: p.x * g.size.width, y: (1 - p.y) * g.size.height)
                    }
                }
                Text(engine.mode.short).font(.caption2.bold()).foregroundStyle(.white.opacity(0.5))
                    .frame(maxHeight: .infinity, alignment: .bottom).padding(6)
            }
            .frame(width: 118, height: 118)
            HStack(spacing: 22) { key("menu", "MENU"); key("home", "", "tv") }
            HStack(alignment: .top, spacing: 22) {
                VStack(spacing: 14) { key("siri", "", "mic.fill"); key("play", "", "playpause.fill") }
                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        Capsule().fill(Color(white: 0.16)).frame(width: 44, height: 102)
                        VStack(spacing: 0) {
                            Image(systemName: "plus").frame(width: 44, height: 51)
                                .background(engine.pressed.contains("vol.up") ? Color.accentColor : .clear, in: Capsule())
                            Image(systemName: "minus").frame(width: 44, height: 51)
                                .background(engine.pressed.contains("vol.down") ? Color.accentColor : .clear, in: Capsule())
                        }
                        .foregroundStyle(.white).font(.system(size: 14, weight: .bold))
                    }
                }
            }
        }
        .padding(.vertical, 22).padding(.horizontal, 20)
        .background(RoundedRectangle(cornerRadius: 30).fill(Color(white: 0.04)))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }
}

// MARK: - Overview

struct StatusRow: View {
    var ok: Bool
    var title: String
    var detail: String
    var button: (String, () -> Void)? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let b = button, !ok { Button(b.0, action: b.1) }
        }
    }
}

struct OverviewTab: View {
    @ObservedObject var engine = Engine.shared
    @ObservedObject var timer = SleepTimer.shared
    @ObservedObject var music = MusicWatcher.shared

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(spacing: 14) {
                RemoteDrawing()
                Text("Press a button or touch the surface:\nit lights up here.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Setup checklist") {
                        VStack(alignment: .leading, spacing: 12) {
                            StatusRow(ok: engine.connected, title: engine.connected ? "Remote connected: \(engine.deviceName)" : "Remote not found",
                                      detail: engine.connected ? (engine.battery.map { "Battery \($0)%" } ?? "Ready to use") :
                                        "Pair it: hold Menu + Volume Up for 5 seconds near the Mac, then click Connect in System Settings › Bluetooth.",
                                      button: ("Open Bluetooth", { openSettings("x-apple.systempreferences:com.apple.BluetoothSettings") }))
                            StatusRow(ok: engine.inputGranted, title: "Input Monitoring",
                                      detail: "Lets Couch Remote read the remote's buttons.",
                                      button: ("Allow…", { engine.requestPermissions(); openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") }))
                            StatusRow(ok: engine.axGranted, title: "Accessibility",
                                      detail: "Lets Couch Remote move the pointer and press keys for you.",
                                      button: ("Allow…", { engine.requestPermissions(); openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") }))
                            StatusRow(ok: engine.touchAttached, title: engine.touchAttached ? "Touch surface active" : "Touch surface not found yet",
                                      detail: engine.touchAttached ? "Touch the glass to see the dot move." : "Touch the remote's surface or press a button to wake it. You can pick the device in Touchpad settings.",
                                      button: ("Retry", { TouchSurface.shared.reattach(); RemoteHID.shared.restart() }))
                        }
                        .padding(6)
                    }
                    GroupBox("Right now") {
                        VStack(alignment: .leading, spacing: 10) {
                            LabeledContent("Front app", value: engine.frontAppName.isEmpty ? "—" : engine.frontAppName)
                            LabeledContent("Using profile", value: engine.activeProfile)
                            Picker("Touch mode", selection: Binding(get: { engine.mode }, set: { engine.setMode($0, announce: false) })) {
                                ForEach(TouchMode.allCases) { m in Label(m.short, systemImage: m.symbol).tag(m) }
                            }
                            .pickerStyle(.segmented)
                            LabeledContent("Sleep timer", value: timer.fireAt.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) } ?? "Off")
                            LabeledContent("Music", value: music.summary)
                            Divider()
                            Text("Last input").font(.caption).foregroundStyle(.secondary)
                            Text(engine.lastEvent).font(.system(.body, design: .rounded)).lineLimit(2)
                        }
                        .padding(6)
                    }
                    GroupBox("Quick guide (default setup)") {
                        VStack(alignment: .leading, spacing: 6) {
                            guide("TV button", "Big Screen: full-screen home for the remote")
                            guide("Double‑press TV", "Couch Menu: quick list with files and more")
                            guide("In the Couch Menu", "Swipe ↑↓ to move, swipe → to open or choose, swipe ← to go back")
                            guide("Right edge of the glass", "Slide up/down to scroll with one finger (Trackpad mode, see Gestures)")
                            guide("Swipe ← / →", "Previous / next song while music plays (Remote mode)")
                            guide("Siri button", "Switch touch mode: Trackpad → Remote → Scroll")
                            guide("Hold Siri", "Mousespot spotlight on/off")
                            guide("Double‑press Siri", "On‑screen keyboard")
                            guide("Menu", "Back / Escape · hold for app switcher")
                            guide("Click the glass", "Click (Trackpad mode) or OK (Remote mode). Hold to drag.")
                        }
                        .padding(6)
                    }
                    GroupBox("Usage") {
                        UsageSummary()
                    }
                    GroupBox("Tour") {
                        HStack {
                            Text("New here, or want a refresher?").foregroundStyle(.secondary)
                            Spacer()
                            Button("Replay the tour") { Tutorial.shared.show() }
                        }
                        .padding(6)
                    }
                }
            }
        }
    }

    private func guide(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) { Text(k).bold().frame(width: 140, alignment: .leading); Text(v).foregroundStyle(.secondary) }
    }
}

func openSettings(_ s: String) { if let u = URL(string: s) { NSWorkspace.shared.open(u) } }

/// A small read-out of how the remote has been used (kept on this Mac only)
struct UsageSummary: View {
    @ObservedObject var usage = UsageStats.shared

    private func pretty(_ raw: String) -> String {
        (Trigger(rawValue: raw)?.title) ?? raw
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 24) {
                stat("\(usage.presses)", "button presses")
                stat("\(usage.daysUsed)", usage.daysUsed == 1 ? "day used" : "days used")
                stat(DateFormatter.localizedString(from: usage.since, dateStyle: .medium, timeStyle: .none), "since")
            }
            if !usage.topTriggers.isEmpty {
                Divider()
                Text("Most used").font(.caption).foregroundStyle(.secondary)
                ForEach(usage.topTriggers, id: \.0) { t in
                    HStack { Text(pretty(t.0)); Spacer(); Text("\(t.1)").monospacedDigit().foregroundStyle(.secondary) }
                }
            }
            if !usage.topApps.isEmpty {
                Divider()
                Text("Apps you control most").font(.caption).foregroundStyle(.secondary)
                ForEach(usage.topApps, id: \.0) { a in
                    HStack { Text(a.0); Spacer(); Text("\(a.1)").monospacedDigit().foregroundStyle(.secondary) }
                }
            }
            HStack {
                Spacer()
                Button("Reset stats") { usage.reset() }
                Text("Kept only on this Mac.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(6)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Touchpad

struct TouchTab: View {
    @ObservedObject var store = ConfigStore.shared
    @AppStorage("touchDeviceIndex") private var deviceIndex = 0
    @ObservedObject private var ui = UIState.shared
    private var devices: [TouchDeviceInfo] { ui.devices }

    var body: some View {
        Form {
            Section("Pointer (Trackpad mode)") {
                slider("Pointer speed", $store.config.settings.cursorSpeed, 0.2...3)
                slider("Acceleration", $store.config.settings.acceleration, 0...2)
                slider("Precision", $store.config.settings.precision, 0...1)
                Text("Higher precision makes slow, careful movements move the pointer less, so it's easier to hit small buttons. Fast swipes still cross the screen.")
                    .font(.caption).foregroundStyle(.secondary)
                slider("Smoothing", $store.config.settings.smoothing, 0...1)
                Toggle("Click stabiliser: keep the pointer still when you press to click", isOn: $store.config.settings.clickStabiliser)
                Toggle("Tap to click (light taps count as clicks)", isOn: $store.config.settings.tapToClick)
                Toggle("Press and slide on a title bar to drag the window", isOn: $store.config.settings.dragOnLongClick)
                Toggle("Also drag other things (files, selected text, sliders)", isOn: $store.config.settings.dragAnything)
                    .disabled(!store.config.settings.dragOnLongClick)
                Toggle("Two‑finger tap to right‑click", isOn: $store.config.settings.twoFingerRightClick)
                Text("Off: a two‑finger tap does whatever “Two‑finger tap” is set to on the Buttons screen.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Tap, then touch again and slide to drag", isOn: $store.config.settings.tapDrag)
                if store.config.settings.tapDrag {
                    slider("Time to touch again (s)", $store.config.settings.tapDragWindow, 0.2...1.5)
                }
                Text("Like a Mac trackpad: tap once, put your finger straight back down and slide to drag windows, sliders or selected text. Lift to drop. Works even with tap to click off. “Time to touch again” is how long you have after the tap; make it longer if drags don't start.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Fit to your thumb") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Calibration wizard")
                        Text("Tap, swipe, tap‑and‑drag and long‑press a few times, and Couch Remote sets the tap, swipe, drag and hold timings for you.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Start…") { ui.calibrating = true }
                }
                slider("Longest tap (s)", $store.config.settings.tapMaxTime, 0.1...0.45)
                slider("Tap wiggle room", $store.config.settings.tapMaxTravel, 0.01...0.08)
                slider("Long press (s)", $store.config.settings.holdTime, 0.25...1.5)
            }
            Section("Remote sleep") {
                Picker("Keep the remote awake after you last use it", selection: $store.config.settings.remoteStayAwakeMinutes) {
                    Text("Remote's own setting").tag(0)
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("As long as Couch Remote is open").tag(-1)
                }
                Text("The remote picks its own sleep time and the Mac can't change it directly. Couch Remote checks in with it every 20 seconds so it stays connected longer. This uses a little more battery. If it still drops off, any button wakes it again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Scrolling") {
                slider("Scroll speed", $store.config.settings.scrollSpeed, 0.2...3)
                Toggle("Natural scrolling", isOn: $store.config.settings.naturalScroll)
            }
            Section("Remote mode") {
                slider("Swipe distance", $store.config.settings.swipeDistance, 0.08...0.4)
                Toggle("Click the edges of the glass for up/down/left/right", isOn: $store.config.settings.edgeClickZones)
                Toggle("Tap the glass like an Apple TV clickpad", isOn: $store.config.settings.remoteTapZones)
                if store.config.settings.remoteTapZones {
                    HStack {
                        Text("Centre “select” circle").foregroundStyle(.secondary)
                        Slider(value: $store.config.settings.remoteTapCenter, in: 0.15...0.45)
                        Text("\(Int((store.config.settings.remoteTapCenter * 200).rounded()))% of the glass").monospacedDigit().frame(width: 120, alignment: .trailing)
                    }
                    Text("Tap the middle to select; tap above, below, left or right of the centre to move that way — just like the Apple TV remote. Works for navigating apps (such as Music) and the Big Screen alike.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Modes") {
                Picker("Default touch mode", selection: $store.config.settings.defaultTouchMode) {
                    ForEach(TouchMode.allCases) { m in Text(m.title).tag(m) }
                }
                Toggle("Switch mode automatically for each app, e.g. Remote mode in Music or TV (set in App Profiles)", isOn: $store.config.settings.autoModePerApp)
            }
            Section("Touch device") {
                Picker("Use", selection: $deviceIndex) {
                    Text("Automatic (smallest external surface)").tag(0)
                    ForEach(devices) { d in Text(d.label).tag(d.id + 1) }
                }
                .onChange(of: deviceIndex) { _ in TouchSurface.shared.reattach() }
                Text("If the pointer moves when you use a Magic Trackpad instead of the remote, pick the remote here.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Refresh list") { ui.devices = TouchSurface.shared.listDevices() }
            }
            MotionSection()
        }
        .formStyle(.grouped)
        .onAppear { ui.devices = TouchSurface.shared.listDevices() }
        .sheet(isPresented: $ui.calibrating) { CalibrationView() }
    }
}

/// Experimental air mouse: shows every non-button signal from the remote, and lets you pick two to steer the pointer
struct MotionSection: View {
    @ObservedObject var store = ConfigStore.shared
    @ObservedObject var lab = MotionLab.shared

    var body: some View {
        Section("Air mouse (experimental)") {
            Text("The 2015–2020 Siri Remote has motion sensors, but macOS may not pass their readings to apps. Tilt and wave the remote: any signal whose number changes as you move is a candidate. Pick one for left/right and one for up/down. If nothing below changes when you move the remote, your Mac doesn't share its motion data.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Move the pointer by tilting the remote (Trackpad mode)", isOn: $store.config.settings.airMouse)
            Toggle("Only while a finger rests on the glass", isOn: $store.config.settings.airNeedsTouch)
            Picker("Left/right signal", selection: $store.config.settings.airX) {
                Text("None").tag("")
                ForEach(lab.signals) { s in Text(s.name).tag(s.id) }
            }
            Picker("Up/down signal", selection: $store.config.settings.airY) {
                Text("None").tag("")
                ForEach(lab.signals) { s in Text(s.name).tag(s.id) }
            }
            HStack {
                Toggle("Flip left/right", isOn: $store.config.settings.airInvertX)
                Toggle("Flip up/down", isOn: $store.config.settings.airInvertY)
            }
            slider("Air mouse speed", $store.config.settings.airSpeed, 0.2...4)
            HStack {
                Button("Hold still, then click: set resting position") { lab.setStill() }
                Button("Clear readings") { lab.reset() }
            }
            if lab.signals.isEmpty {
                Text("No extra signals from the remote yet. Make sure it's connected, then move it around.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(lab.signals.prefix(14)) { s in
                    HStack {
                        Text(s.name).font(.caption.monospaced())
                        Spacer()
                        Text("\(s.value)").font(.caption.monospaced()).frame(width: 70, alignment: .trailing)
                        Text("\(s.minSeen)…\(s.maxSeen)").font(.caption.monospaced()).foregroundStyle(.secondary).frame(width: 110, alignment: .trailing)
                        Text("\(s.changes)×").font(.caption.monospaced()).foregroundStyle(s.changes > 20 ? Color.green : Color.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }
        }
    }
}

func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
    HStack {
        Text(title).frame(width: 150, alignment: .leading)
        Slider(value: value, in: range)
        Text(String(format: "%.2f", value.wrappedValue)).monospacedDigit().frame(width: 44)
    }
}

// MARK: - Pop-ups

struct PopupsTab: View {
    @ObservedObject var store = ConfigStore.shared

    var body: some View {
        Form {
            Section {
                Toggle("Show pop-up messages at all", isOn: $store.config.settings.showHUD)
                HStack {
                    Button("Turn all on") { store.config.settings.hudDisabled = [] }
                    Button("Turn all off") { store.config.settings.hudDisabled = HUDKind.allCases.map(\.rawValue) }
                    Spacer()
                    Button("Preview") { HUD.shared.show("This is a pop-up", symbol: "bubble.left.fill", kind: .actions) }
                }
            }
            Section("Show a pop-up for…") {
                ForEach(HUDKind.allCases) { k in
                    Toggle(k.title, isOn: Binding(
                        get: { !store.config.settings.hudDisabled.contains(k.rawValue) },
                        set: { on in
                            store.config.settings.hudDisabled.removeAll { $0 == k.rawValue }
                            if !on { store.config.settings.hudDisabled.append(k.rawValue) }
                        }))
                }
            }
            .disabled(!store.config.settings.showHUD)
            Section("Look") {
                Picker("Position", selection: $store.config.settings.hudPosition) {
                    ForEach(HUDPosition.allCases) { p in Text(p.title).tag(p) }
                }
                .pickerStyle(.segmented)
                slider("Time on screen (s)", $store.config.settings.hudDuration, 0.5...4)
            }
            Section("Volume") {
                Picker("Each press of Volume + / −", selection: $store.config.settings.volumeStep) {
                    Text("Tiny (1%)").tag(1.0)
                    Text("Small (3%)").tag(3.0)
                    Text("One bar (6%, like the keyboard)").tag(6.25)
                    Text("Let macOS decide").tag(0.0)
                }
                Text("Couch Remote sets the volume to an exact level each time, so one press is always one step, even if macOS also hears the remote over Bluetooth. Hold the button to keep going. A pop‑up shows the new level (switch it off under “Volume” above). “Let macOS decide” uses the normal volume keys and bubble instead.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("macOS's own bubbles") {
                Toggle("Mute silently (no macOS bubble)", isOn: $store.config.settings.silentVolume)
                Text("macOS draws its own bubble when you mute. With this on, Couch Remote mutes directly, so the bubble doesn't appear.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Extras

struct ExtrasTab: View {
    @ObservedObject var store = ConfigStore.shared
    @ObservedObject private var ui = UIState.shared

    var body: some View {
        Form {
            Section("Swipe and hold to keep going (Remote mode)") {
                HStack {
                    Text("Hold still for")
                    Slider(value: $store.config.settings.seekHoldDelay, in: 0.2...1.0)
                    Text(String(format: "%.2f s", store.config.settings.seekHoldDelay)).monospacedDigit().frame(width: 52, alignment: .trailing)
                }
                Text("How long you rest your finger after a swipe before it starts. Then slide further to go faster, back to the middle to pause, past it to go the other way. Lift to stop.")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Left / right: fast-forward or rewind", isOn: $store.config.settings.holdToSeek)
                if store.config.settings.holdToSeek {
                    Toggle("Speed follows how far you slide (off: speeds up the longer you hold)", isOn: $store.config.settings.seekByDistance)
                    HStack {
                        Text("Slowest")
                        Slider(value: $store.config.settings.seekMinSpeed, in: 1...16)
                        Text("\(Int(store.config.settings.seekMinSpeed.rounded()))×").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                    HStack {
                        Text("Fastest")
                        Slider(value: $store.config.settings.seekMaxSpeed, in: 4...120)
                        Text("\(Int(store.config.settings.seekMaxSpeed.rounded()))×").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                    Text("Seeks the song in Music or Spotify, the video in Safari, Chrome, Arc, Edge, Brave or Vivaldi, and presses the arrow keys in other apps.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Toggle("Up / down: step straight away as you slide (don’t wait until you lift)", isOn: $store.config.settings.instantListSwipe)
                if store.config.settings.instantListSwipe {
                    HStack {
                        Text("Slide per extra step")
                        Slider(value: $store.config.settings.listStepSpacing, in: 0.3...1.5)
                        Text(store.config.settings.listStepSpacing < 0.6 ? "Short" : (store.config.settings.listStepSpacing > 1.0 ? "Long" : "Medium"))
                            .frame(width: 60, alignment: .trailing)
                    }
                }
                Toggle("Up / down: keep moving through a list (songs, menus)", isOn: $store.config.settings.holdToRepeat)
                if store.config.settings.holdToRepeat {
                    HStack {
                        Text("Pace")
                        Slider(value: $store.config.settings.repeatRate, in: 1...25)
                        Text("\(Int(store.config.settings.repeatRate.rounded())) a second").monospacedDigit().frame(width: 90, alignment: .trailing)
                    }
                    Toggle("Go faster the further you slide", isOn: $store.config.settings.repeatByDistance)
                    Text("Repeats whatever a swipe up or down does in that app, e.g. moving the selection in Music.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Volume on the left edge (Remote mode)") {
                Toggle("Slide up or down the left edge of the glass to change the volume smoothly", isOn: $store.config.settings.remoteVolumeEdge)
                if store.config.settings.remoteVolumeEdge {
                    HStack {
                        Toggle("Reverse (slide down for louder)", isOn: $store.config.settings.remoteVolumeReverse)
                    }
                    HStack {
                        Text("Edge width")
                        Slider(value: $store.config.settings.remoteVolumeEdgeWidth, in: 0.05...0.4)
                        Text("\(Int((store.config.settings.remoteVolumeEdgeWidth * 100).rounded()))% of the glass").monospacedDigit().frame(width: 100, alignment: .trailing)
                    }
                    HStack {
                        Text("Sensitivity")
                        Slider(value: $store.config.settings.edgeVolumeSpeed, in: 0.3...2.5)
                        Text(String(format: "%.0f%% per slide", 60 * store.config.settings.edgeVolumeSpeed)).monospacedDigit().frame(width: 100, alignment: .trailing)
                    }
                }
                Text("Put your thumb on the left edge and slide. It moves in 1% steps and follows your finger. A quick swipe left or right that starts there still works as normal.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Music swipes (Remote mode)") {
                Toggle("While music is playing, swipe right for the next song and left for the previous one", isOn: $store.config.settings.musicSwipes)
                Toggle("Also swipe up/down to change the volume while music plays", isOn: $store.config.settings.musicSwipesVolume)
                Text("Works with Music and Spotify, whichever app is in front. When nothing is playing, swipes do what the app's profile says. Not used in these apps:")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(store.config.settings.musicSwipeExceptions, id: \.self) { bid in
                    HStack {
                        if let img = appIcon(bid) { Image(nsImage: img).resizable().frame(width: 18, height: 18) }
                        Text(appName(bid))
                        Spacer()
                        Button { store.config.settings.musicSwipeExceptions.removeAll { $0 == bid } } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Add app…") {
                    if let bid = chooseAppBundleID(), !store.config.settings.musicSwipeExceptions.contains(bid) {
                        store.config.settings.musicSwipeExceptions.append(bid)
                    }
                }
            }
            Section("Feedback") {
                Text("Pop-up messages now have their own screen: Pop-ups in the sidebar.").font(.caption).foregroundStyle(.secondary)
                Toggle("Click sound on every button", isOn: $store.config.settings.clickSound)
            }
            Section("Buttons") {
                slider("Hold time (s)", $store.config.settings.holdTime, 0.25...1.5)
                slider("Double‑press window (s)", $store.config.settings.doubleTapWindow, 0.15...0.6)
                Toggle("Repeat volume while held", isOn: $store.config.settings.repeatVolumeWhileHeld)
                Picker("Play/Pause button", selection: $store.config.settings.playPause) {
                    ForEach(PlayPauseHandling.allCases) { p in Text(p.title).tag(p) }
                }
            }
            Section("Laser pointer / spotlight") {
                Picker("Style", selection: $store.config.settings.spotStyle) {
                    Text("Dim around").tag("dim")
                    Text("Laser dot").tag("dot")
                    Text("Ring").tag("ring")
                    Text("Glow").tag("glow")
                    Text("Flashlight").tag("flashlight")
                }
                Picker("Colour", selection: $store.config.settings.spotColor) {
                    Text("Red").tag("red"); Text("Green").tag("green"); Text("Blue").tag("blue")
                    Text("Yellow").tag("yellow"); Text("White").tag("white"); Text("Pink").tag("pink")
                }
                slider("Size", $store.config.settings.spotRadius, 50...400)
                slider("Darkness (Dim / Flashlight)", $store.config.settings.spotDim, 0.2...0.9)
                Toggle("Show it whenever I rest a finger on the glass (Trackpad mode)", isOn: $store.config.settings.spotAutoOnTouch)
                HStack {
                    Button("Try it (on/off)") { _ = Spotlight.shared.toggle() }
                    Button("Next style") { HUD.shared.show(Spotlight.shared.nextStyle(), symbol: "scope") }
                }
                Text("You can also map a button to “Laser pointer: next style” to flip through looks with the remote.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Draw on screen") {
                Text("Map a button to “Draw on screen”. Then, in Trackpad mode, press the glass and slide to draw a line, lift to end it, and press Menu to clear. It draws in the laser colour above.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Try drawing (on/off)") { HUD.shared.show(DrawBoard.shared.toggle() ? "Draw on" : "Draw off", symbol: "scribble") }
            }
            Section("Hush notifications") {
                TextField("Shortcut name that toggles Do Not Disturb", text: $store.config.settings.hushShortcut)
                Text("macOS doesn’t let apps toggle Do Not Disturb directly. In the Shortcuts app, make a shortcut with “Set Focus → Do Not Disturb → Toggle”, name it, and type that name here. Then map a button to “Hush notifications”.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Test Hush now") { HUD.shared.show(Runner.hushNotifications() ?? "Hush", symbol: "moon.fill") }
            }
            Section("Menu bar") {
                Toggle("Show the remote’s battery % next to the menu bar icon", isOn: $store.config.settings.menuBarBattery)
            }
            Section("Safety") {
                Toggle("Hold Select to confirm risky actions (Quit, Close, Sleep, Lock)", isOn: $store.config.settings.holdToConfirm)
                Text("When on, those actions show a “hold to confirm” ring so a stray press can’t quit an app or sleep the Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Presenter overlay") {
                Text("Map a button to “Presenter overlay (clock & timer)” for a floating clock and elapsed timer during talks.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Pacing cue")
                    Slider(value: $store.config.settings.presenterSlideSeconds, in: 0...300, step: 15)
                    Text(store.config.settings.presenterSlideSeconds == 0 ? "Off" : "\(Int(store.config.settings.presenterSlideSeconds))s / slide")
                        .frame(width: 90, alignment: .trailing).monospacedDigit()
                }
                Text("When set, the overlay shows a bar for the current slide and gently flashes “Next slide ›” once you’ve spent longer than this. A right‑swipe resets it.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Try the presenter overlay (on/off)") { _ = PresenterOverlay.shared.toggle() }
            }
            Section("Phone remote") {
                Toggle("Use my phone as a remote (built‑in, no extra software)", isOn: Binding(
                    get: { PhoneServer.shared.running },
                    set: { on in on ? PhoneServer.shared.enable() : PhoneServer.shared.disable() }))
                HStack {
                    Text("Port"); Spacer()
                    TextField("8723", value: $store.config.settings.phoneRemotePort, format: .number.grouping(.never)).frame(width: 80)
                }
                if PhoneServer.shared.running {
                    HStack { Text("Open on your phone:").foregroundStyle(.secondary); Spacer(); Text(PhoneServer.shared.url).font(.system(.body, design: .monospaced)).textSelection(.enabled) }
                }
                Button("Show setup (address & QR)…") { PhoneSetup.shared.show() }
                Text("Your phone and Mac must be on the same Wi‑Fi. The first time, macOS may ask to allow local‑network access.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Sleep timer") {
                TextField("Steps in minutes (each press moves to the next)", text: $ui.stepsText)
                    .onSubmit { saveSteps() }
                HStack {
                    Button("Save steps") { saveSteps() }
                    Button("Start 30 min now") { SleepTimer.shared.set(minutes: 30) }
                    Button("Cancel timer") { SleepTimer.shared.set(minutes: nil) }
                }
            }
            Section("Startup") {
                Toggle("Open Couch Remote when I log in", isOn: Binding(
                    get: { store.config.settings.launchAtLogin },
                    set: { on in
                        store.config.settings.launchAtLogin = on
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { NSLog("Login item: \(error)") }
                    }))
            }
            KeyboardKeysSection()
        }
        .formStyle(.grouped)
        .onAppear { ui.stepsText = store.config.settings.sleepTimerSteps.map(String.init).joined(separator: ", ") }
    }

    private func saveSteps() {
        let steps = ui.stepsText.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.filter { $0 > 0 }.sorted()
        if !steps.isEmpty { store.config.settings.sleepTimerSteps = steps }
        ui.stepsText = store.config.settings.sleepTimerSteps.map(String.init).joined(separator: ", ")
    }
}

// MARK: - Backup

struct KeyboardKeysSection: View {
    @ObservedObject var store = ConfigStore.shared

    // Every button except the mic (Siri) can be re‑mapped while the on‑screen keyboard is up.
    private var triggers: [Trigger] { Trigger.allCases.filter { $0.group == "Buttons" && !$0.isSiri } }

    var body: some View {
        Section("Buttons while the on‑screen keyboard is open") {
            Text("While the keyboard is showing, the touch surface moves between keys and clicking types — that part is fixed. The physical buttons below can do whatever you like (the mic button is left for Siri).")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(triggers) { t in
                HStack(alignment: .center) {
                    Text(t.title).frame(width: 200, alignment: .leading)
                    ActionEditor(action: binding(t), allowInherit: true, id: "kbd.\(t.rawValue)")
                }
            }
            Text("“Same as Global” keeps the normal keyboard‑mode job: Menu closes the keyboard, Play/Pause presses Return, and the rest do nothing until you set them.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func binding(_ t: Trigger) -> Binding<Action> {
        Binding(
            get: { store.config.settings.keyboardKeys[t.rawValue] ?? .k(.inherit) },
            set: { new in
                if new.kind == .inherit { store.config.settings.keyboardKeys[t.rawValue] = nil }
                else { store.config.settings.keyboardKeys[t.rawValue] = new }
            })
    }
}

struct BackupTab: View {
    @ObservedObject var store = ConfigStore.shared
    @ObservedObject private var ui = UIState.shared
    private var message: String {
        get { ui.backupMessage }
        nonmutating set { ui.backupMessage = newValue }
    }

    var body: some View {
        Form {
            Section("Your settings") {
                Text("Everything is saved automatically to:").foregroundStyle(.secondary)
                Text(store.fileURL.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.fileURL]) }
            }
            Section("Backup & restore") {
                HStack {
                    Button("Export backup…") {
                        let p = NSSavePanel(); p.allowedContentTypes = [.json]; p.nameFieldStringValue = "Couch Remote backup.json"
                        if p.runModal() == .OK, let url = p.url {
                            do { try store.backup(to: url); message = "Saved backup." } catch { message = "Couldn't save: \(error.localizedDescription)" }
                        }
                    }
                    Button("Import backup…") {
                        let p = NSOpenPanel(); p.allowedContentTypes = [.json]
                        if p.runModal() == .OK, let url = p.url {
                            do { try store.restore(from: url); message = "Restored." } catch { message = "That file isn't a Couch Remote backup." }
                        }
                    }
                }
                Text("Tip: the file is plain JSON, so you can edit mappings in a text editor and import them back.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Reset") {
                Button("Reset everything to defaults…", role: .destructive) {
                    let a = NSAlert(); a.messageText = "Reset all mappings and settings?"
                    a.informativeText = "Export a backup first if you want to keep your changes."
                    a.addButton(withTitle: "Reset"); a.addButton(withTitle: "Cancel")
                    if a.runModal() == .alertFirstButtonReturn { store.resetToDefaults(); message = "Reset to defaults." }
                }
            }
            if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
        }
        .formStyle(.grouped)
    }
}
