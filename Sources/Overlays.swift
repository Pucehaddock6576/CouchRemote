// Overlays.swift — HUD, Mousespot, Couch Menu, on-screen keyboard, sleep timer
import AppKit
import SwiftUI

// MARK: - Floating panel helper

/// True while any remote-driven overlay is showing (they take over the touch surface).
var anyPanelOpen: Bool { KeyboardPanel.shared.isOpen || CouchMenu.shared.isOpen || BigScreen.shared.isOpen || AppSwitcher.shared.active || YouTubeApp.shared.isOpen }

final class FloatingPanel: NSPanel {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func centre(yFraction: CGFloat = 0.5) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let f = screen.visibleFrame
        setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.minY + f.height * yFraction - frame.height / 2))
    }
}

// MARK: - HUD

final class HUDModel: ObservableObject {
    @Published var text = ""
    @Published var symbol = "appletvremote.gen1.fill"
    @Published var level: Double?         // shows a bar (volume and the like)
    @Published var tint = Color.accentColor
    @Published var pop = false            // flips each time, for a little spring as it appears
}

final class HUD {
    static let shared = HUD()
    private let model = HUDModel()
    private lazy var panel: FloatingPanel = {
        let p = FloatingPanel(size: NSSize(width: 460, height: 110))
        p.ignoresMouseEvents = true
        p.hasShadow = false                   // the pill draws its own soft shadow
        p.contentView = NSHostingView(rootView: HUDView(model: model))
        return p
    }()
    private var hideWork: DispatchWorkItem?

    static func tint(_ kind: HUDKind) -> Color {
        switch kind {
        case .playback, .songChange, .nowPlaying: return Color(red: 0.95, green: 0.27, blue: 0.47)
        case .volume: return Color(red: 0.20, green: 0.52, blue: 0.98)
        case .touchMode: return Color(red: 0.55, green: 0.36, blue: 0.95)
        case .connection: return Color(red: 0.16, green: 0.72, blue: 0.42)
        case .webVideo: return Color(red: 0.98, green: 0.45, blue: 0.15)
        case .sleepTimer: return Color(red: 0.36, green: 0.36, blue: 0.85)
        case .power: return Color(red: 0.93, green: 0.30, blue: 0.30)
        default: return Color(red: 0.30, green: 0.40, blue: 0.95)
        }
    }

    func show(_ text: String, symbol: String, kind: HUDKind = .actions, level: Double? = nil) {
        let s = ConfigStore.shared.settings
        guard s.hudEnabled(kind) else { return }
        let wasVisible = panel.isVisible && panel.alphaValue > 0.5
        model.text = text; model.symbol = symbol; model.tint = Self.tint(kind)
        model.level = level.map { max(0, min(1, $0)) }
        if !wasVisible {
            model.pop = false
            DispatchQueue.main.async { withAnimation(.spring(response: 0.32, dampingFraction: 0.66)) { self.model.pop = true } }
        }
        panel.centre(yFraction: s.hudPosition.yFraction)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; self?.panel.animator().alphaValue = 0 },
                                                 completionHandler: { self?.panel.orderOut(nil) })
        }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + s.hudDuration, execute: w)
    }
}

struct HUDView: View {
    @ObservedObject var model: HUDModel
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: model.symbol).font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(LinearGradient(colors: [model.tint, model.tint.opacity(0.7)], startPoint: .top, endPoint: .bottom)))
            VStack(alignment: .leading, spacing: 7) {
                Text(model.text).font(.system(size: 16, weight: .semibold, design: .rounded)).lineLimit(1).foregroundStyle(.white)
                if let l = model.level {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.18))
                            Capsule().fill(Color.white).frame(width: max(6, g.size.width * CGFloat(l)))
                                .animation(.easeOut(duration: 0.12), value: l)
                        }
                    }
                    .frame(width: 220, height: 6)
                }
            }
        }
        .padding(.leading, 10).padding(.trailing, 24).padding(.vertical, 10)
        .background(Capsule().fill(Color(white: 0.07).opacity(0.86)))
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        .scaleEffect(model.pop ? 1 : 0.9)
        .opacity(model.pop ? 1 : 0.4)
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Mousespot / laser pointer

/// The named laser-pointer colours
enum SpotPalette {
    static let order = ["red", "green", "blue", "yellow", "white", "pink"]
    static func color(_ name: String) -> NSColor {
        switch name {
        case "green": return NSColor(red: 0.20, green: 0.95, blue: 0.35, alpha: 1)
        case "blue": return NSColor(red: 0.25, green: 0.60, blue: 1.00, alpha: 1)
        case "yellow": return NSColor(red: 1.00, green: 0.86, blue: 0.20, alpha: 1)
        case "white": return NSColor.white
        case "pink": return NSColor(red: 1.00, green: 0.35, blue: 0.70, alpha: 1)
        default: return NSColor(red: 1.00, green: 0.23, blue: 0.19, alpha: 1)   // red
        }
    }
}

final class SpotView: NSView {
    var centre = NSPoint.zero
    override func draw(_ dirtyRect: NSRect) {
        let s = ConfigStore.shared.settings
        let r = CGFloat(s.spotRadius)
        let tint = SpotPalette.color(s.spotColor)
        let c = centre
        func dot(_ radius: CGFloat, _ color: NSColor) {
            color.setFill(); NSBezierPath(ovalIn: NSRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)).fill()
        }
        switch s.spotStyle {
        case "dot":
            // A laser dot: a bright core with a soft halo
            dot(r * 0.5, tint.withAlphaComponent(0.18))
            dot(r * 0.28, tint.withAlphaComponent(0.35))
            dot(r * 0.11, tint.withAlphaComponent(0.95))
            NSColor.white.withAlphaComponent(0.9).setFill()
            let core = r * 0.05
            NSBezierPath(ovalIn: NSRect(x: c.x - core, y: c.y - core, width: core * 2, height: core * 2)).fill()
        case "ring":
            tint.withAlphaComponent(0.95).setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: c.x - r * 0.5, y: c.y - r * 0.5, width: r, height: r))
            ring.lineWidth = 5; ring.stroke()
        case "glow":
            // A gentle glow, no dimming of the rest of the screen
            for (i, a) in [(0.9, 0.08), (0.6, 0.14), (0.35, 0.22)].enumerated() { _ = i; dot(r * CGFloat(a.0), tint.withAlphaComponent(CGFloat(a.1))) }
            dot(r * 0.12, tint.withAlphaComponent(0.9))
        case "flashlight":
            // Everything dark except a soft circle of normal brightness, with a coloured rim
            let path = NSBezierPath(rect: bounds)
            path.appendOval(in: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            path.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(max(CGFloat(s.spotDim), 0.75)).setFill(); path.fill()
            tint.withAlphaComponent(0.8).setStroke()
            let rim = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)); rim.lineWidth = 3; rim.stroke()
        default:   // "dim": the original — darken everything but a clear circle, with a coloured ring
            let path = NSBezierPath(rect: bounds)
            path.appendOval(in: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            path.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(CGFloat(s.spotDim)).setFill(); path.fill()
            tint.withAlphaComponent(0.6).setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)); ring.lineWidth = 2; ring.stroke()
        }
    }
}

final class Spotlight {
    static let shared = Spotlight()
    private var windows: [(NSWindow, SpotView)] = []
    private var timer: Timer?
    private(set) var on = false
    private var temporary = false

    @discardableResult
    func toggle() -> Bool { set(!on); return on }

    /// Cycle through the pointer looks: dim → dot → ring → glow → flashlight. Turns the pointer on if it was off.
    func nextStyle() -> String {
        let styles = ["dim", "dot", "ring", "glow", "flashlight"]
        let names = ["Dim around", "Laser dot", "Ring", "Glow", "Flashlight"]
        let cur = styles.firstIndex(of: ConfigStore.shared.settings.spotStyle) ?? 0
        let next = (cur + 1) % styles.count
        ConfigStore.shared.config.settings.spotStyle = styles[next]
        if !on { set(true) } else { windows.forEach { $0.1.needsDisplay = true } }
        return "Laser: " + names[next]
    }

    func setTemporary(_ show: Bool) {
        if on && !temporary { return }     // already switched on for real
        temporary = show
        set(show)
    }

    private func set(_ show: Bool) {
        on = show
        windows.forEach { $0.0.orderOut(nil) }
        windows.removeAll()
        timer?.invalidate(); timer = nil
        guard show else { temporary = false; return }
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false; w.backgroundColor = .clear; w.ignoresMouseEvents = true
            w.level = .screenSaver; w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let v = SpotView(frame: NSRect(origin: .zero, size: screen.frame.size))
            w.contentView = v
            w.setFrame(screen.frame, display: false)
            w.orderFrontRegardless()
            windows.append((w, v))
        }
        follow()
        timer = Timer.common(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.follow() }
    }

    private func follow() {
        let m = NSEvent.mouseLocation
        for (w, v) in windows {
            let local = NSPoint(x: m.x - w.frame.minX, y: m.y - w.frame.minY)
            v.centre = w.frame.contains(m) ? local : NSPoint(x: -10000, y: -10000)
            v.needsDisplay = true
        }
    }
}

// MARK: - Sleep timer

final class SleepTimer: ObservableObject {
    static let shared = SleepTimer()
    @Published var fireAt: Date?
    private var timer: Timer?

    func cycle() -> String {
        let steps = ConfigStore.shared.settings.sleepTimerSteps
        let current = fireAt.map { Int(ceil($0.timeIntervalSinceNow / 60)) } ?? 0
        let next = steps.first(where: { $0 > current + 1 })
        set(minutes: next)
        return next.map { "Sleep in \($0) min" } ?? "Sleep timer off"
    }

    func set(minutes: Int?) {
        timer?.invalidate(); timer = nil
        guard let m = minutes, m > 0 else { fireAt = nil; return }
        fireAt = Date().addingTimeInterval(TimeInterval(m * 60))
        timer = Timer.common(withTimeInterval: TimeInterval(m * 60), repeats: false) { [weak self] _ in
            self?.fireAt = nil
            for app in ["Music", "Spotify"] {
                Runner.appleScript("if application \"\(app)\" is running then tell application \"\(app)\" to pause")
            }
            _ = Runner.web("toggle")   // best effort: pause a playing web video
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { Runner.shell("pmset sleepnow") }
        }
    }
}

// MARK: - Couch Menu (Remote Buddy-style big menu, driven by the remote)

struct MenuItem: Identifiable {
    let id = UUID()
    var title: String
    var symbol: String = "circle"
    var icon: NSImage? = nil
    var detail: String = ""
    /// Return a submenu to open it; return nil to close the menu (or keep it if `stays`).
    var run: () -> [MenuItem]? = { nil }
    var stays = false
    var opens = false                     // has a submenu (shows a › and opens with swipe →)
}

final class CouchMenuModel: ObservableObject {
    @Published var stack: [(title: String, items: [MenuItem])] = []
    @Published var index = 0
    var returnIndex: [Int] = []           // where you were in each parent menu
    var items: [MenuItem] { stack.last?.items ?? [] }
    var title: String { stack.last?.title ?? "" }
}

final class CouchMenu {
    static let shared = CouchMenu()
    let model = CouchMenuModel()
    private lazy var panel: FloatingPanel = {
        let p = FloatingPanel(size: NSSize(width: 520, height: 600))
        p.contentView = NSHostingView(rootView: CouchMenuView(model: model, activate: { [weak self] i in self?.activate(i) }))
        return p
    }()

    var isOpen: Bool { panel.isVisible }

    func toggle() { isOpen ? close() : open() }

    func open() {
        Input.releaseIfHeld()
        model.stack = [("Couch Menu", rootItems())]
        model.returnIndex = []
        model.index = 0
        panel.centre()
        panel.orderFrontRegardless()
    }

    func close() { panel.orderOut(nil) }

    /// Remote input while open. Returns true if handled.
    /// Works the same in every touch mode and whatever your button mappings are.
    func handle(_ t: Trigger) -> Bool {
        switch t {
        case .swipeUp, .clickUp: model.index = max(0, model.index - 1)
        case .swipeDown, .clickDown: model.index = min(model.items.count - 1, model.index + 1)
        case .select, .swipeRight, .clickRight, .playTap: activate(model.index)   // swipe → : open / choose
        case .menuTap, .swipeLeft, .clickLeft: back()                              // swipe ← : back
        case .homeTap: close()
        default: return false
        }
        return true
    }

    private func back() {
        if model.stack.count > 1 {
            model.stack.removeLast()
            model.index = model.returnIndex.popLast() ?? 0
        } else { close() }
    }

    func activate(_ i: Int) {
        guard model.items.indices.contains(i) else { return }
        let item = model.items[i]
        if let sub = item.run() {
            model.returnIndex.append(i)          // so going back lands on the item you opened
            model.stack.append((item.title, sub)); model.index = 0
        } else if !item.stays {
            close()
        } else {
            model.stack[model.stack.count - 1].items = refreshed(model.stack.last!.title) ?? model.items
        }
    }

    private func refreshed(_ title: String) -> [MenuItem]? { title == "Couch Menu" ? rootItems() : nil }

    // MARK: menu contents
    private func icon(_ bid: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func rootItems() -> [MenuItem] {
        var items: [MenuItem] = []
        let favs = ConfigStore.shared.settings.favourites.compactMap { bid -> MenuItem? in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) else { return nil }
            return MenuItem(title: url.deletingPathExtension().lastPathComponent, icon: icon(bid), run: {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()); return nil
            })
        }
        if !favs.isEmpty { items.append(MenuItem(title: "Favourites", symbol: "star.fill", detail: "\(favs.count) apps", run: { favs }, opens: true)) }
        if ConfigStore.shared.settings.menuShowsRunningApps {
            items.append(MenuItem(title: "Running apps", symbol: "square.grid.2x2.fill", detail: "Switch or quit", run: { [weak self] in self?.runningApps() }, opens: true))
        }
        items += [
            MenuItem(title: "Big Screen", symbol: "tv.inset.filled", detail: "Full-screen home for the remote",
                     run: { DispatchQueue.main.async { BigScreen.shared.open() }; return nil }),
            MenuItem(title: "YouTube", symbol: "play.rectangle.fill", detail: "Browse and play with the remote",
                     run: { DispatchQueue.main.async { YouTubeApp.shared.open() }; return nil }),
            MenuItem(title: "Volume up", symbol: "speaker.wave.3.fill", run: { Runner.volumeStep(up: true); return nil }, stays: true),
            MenuItem(title: "Volume down", symbol: "speaker.wave.1.fill", run: { Runner.volumeStep(up: false); return nil }, stays: true),
            MenuItem(title: "Mute", symbol: "speaker.slash.fill", run: { Input.media(.mute); return nil }, stays: true),
            MenuItem(title: "Play / Pause", symbol: "playpause.fill", run: { Input.media(.play); return nil }, stays: true),
            MenuItem(title: "Touch mode: \(Engine.shared.mode.short)", symbol: Engine.shared.mode.symbol, detail: "Press to switch",
                     run: { _ = Engine.shared.cycleMode(); return nil }, stays: true),
            MenuItem(title: "Desktop", symbol: "rectangle.3.group", run: { [weak self] in self?.desktopItems() }, opens: true),
            MenuItem(title: "Files", symbol: "folder.fill", detail: "Browse your Home folder",
                     run: { [weak self] in self?.files(FileManager.default.homeDirectoryForCurrentUser) }, opens: true),
            MenuItem(title: "Sleep timer", symbol: "timer",
                     detail: SleepTimer.shared.fireAt.map { "Sleeping at " + DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) } ?? "Off",
                     run: { _ = SleepTimer.shared.cycle(); return nil }, stays: true),
            MenuItem(title: "Power", symbol: "power", run: { [weak self] in self?.powerItems() }, opens: true),
        ]
        return items
    }

    private func runningApps() -> [MenuItem] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
            .map { app in
                MenuItem(title: app.localizedName ?? "App", icon: app.icon, detail: app.isActive ? "In front" : "", run: {
                    [MenuItem(title: "Switch to \(app.localizedName ?? "app")", symbol: "arrow.right.circle.fill", run: { app.activate(); return nil }),
                     MenuItem(title: "Hide", symbol: "eye.slash", run: { app.hide(); return nil }),
                     MenuItem(title: "Quit", symbol: "xmark.circle.fill", run: { app.terminate(); return nil })]
                }, opens: true)
            }
    }

    private func desktopItems() -> [MenuItem] {
        let list: [(String, String, ActionKind)] = [
            ("Mission Control", "rectangle.3.group", .missionControl), ("App windows", "macwindow.on.rectangle", .appExpose),
            ("Show desktop", "menubar.dock.rectangle", .showDesktop), ("Next Space", "arrow.right.square", .nextSpace),
            ("Previous Space", "arrow.left.square", .prevSpace), ("Full screen", "arrow.up.left.and.arrow.down.right", .fullScreen),
            ("Mousespot", "flashlight.on.fill", .mouseSpot), ("On‑screen keyboard", "keyboard", .keyboardPanel),
        ]
        return list.map { t in MenuItem(title: t.0, symbol: t.1, run: { DispatchQueue.main.async { _ = Runner.run(.k(t.2)) }; return nil }) }
    }

    private func powerItems() -> [MenuItem] {
        [MenuItem(title: "Turn screen off", symbol: "display", run: { Runner.run(.k(.displaySleep)); return nil }),
         MenuItem(title: "Lock screen", symbol: "lock.fill", run: { Runner.run(.k(.lockScreen)); return nil }),
         MenuItem(title: "Keep awake on/off", symbol: "cup.and.saucer.fill", run: { Runner.run(.k(.keepAwake)); return nil }),
         MenuItem(title: "Sleep now", symbol: "moon.fill", run: { Runner.run(.k(.sleepMac)); return nil })]
    }

    private func files(_ dir: URL) -> [MenuItem] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(300).map { url in
                let v = try? url.resourceValues(forKeys: Set(keys))
                let isDir = (v?.isDirectory ?? false) && !(v?.isPackage ?? false)
                return MenuItem(title: url.lastPathComponent, icon: NSWorkspace.shared.icon(forFile: url.path),
                                detail: isDir ? "Folder" : "", run: { [weak self] in
                    if isDir { return self?.files(url) }
                    NSWorkspace.shared.open(url); return nil
                }, opens: isDir)
            }
    }
}

struct CouchMenuView: View {
    @ObservedObject var model: CouchMenuModel
    var activate: (Int) -> Void

    private static let palette: [Color] = [
        Color(red: 0.95, green: 0.30, blue: 0.47), Color(red: 0.25, green: 0.50, blue: 0.98), Color(red: 0.16, green: 0.70, blue: 0.45),
        Color(red: 0.98, green: 0.58, blue: 0.15), Color(red: 0.55, green: 0.36, blue: 0.95), Color(red: 0.10, green: 0.66, blue: 0.75),
    ]
    // the same colour for the same item every time (Swift's own hash changes each launch)
    private func tint(_ s: String) -> Color { Self.palette[s.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % Self.palette.count] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if model.stack.count > 1 {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold))
                        .frame(width: 32, height: 32).background(Circle().fill(Color.white.opacity(0.1)))
                } else {
                    Image(systemName: "appletvremote.gen1.fill").font(.system(size: 16, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LinearGradient(colors: [Color(red: 0.95, green: 0.3, blue: 0.5), Color(red: 0.45, green: 0.25, blue: 0.95)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
                }
                Text(model.title).font(.system(size: 22, weight: .heavy, design: .rounded)).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(Array(model.items.enumerated()), id: \.element.id) { i, item in
                            let on = i == model.index
                            Button { activate(i) } label: {
                                HStack(spacing: 14) {
                                    if let img = item.icon {
                                        Image(nsImage: img).resizable().frame(width: 34, height: 34)
                                    } else {
                                        Image(systemName: item.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                            .frame(width: 34, height: 34)
                                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint(item.title)))
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.title).font(.system(size: 17, weight: .semibold, design: .rounded)).lineLimit(1)
                                        if !item.detail.isEmpty {
                                            Text(item.detail).font(.system(size: 12)).opacity(0.6).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if item.opens { Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).opacity(0.5) }
                                }
                                .foregroundStyle(on ? Color.black : Color.white)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? Color.white : Color.white.opacity(0.0001)))
                                .scaleEffect(on ? 1.02 : 1)
                                .shadow(color: on ? .black.opacity(0.3) : .clear, radius: 8, y: 3)
                                .animation(.spring(response: 0.22, dampingFraction: 0.8), value: on)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(i)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 4)
                }
                .onChange(of: model.index) { i in withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(i, anchor: .center) } }
            }
            HStack(spacing: 16) {
                Label("Swipe ↑↓", systemImage: "hand.draw.fill")
                Label("Click or → to open", systemImage: "cursorarrow.click")
                Label("Menu or ← back", systemImage: "arrow.uturn.backward")
            }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(0.5))
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .foregroundStyle(Color.white)
        .frame(width: 520, height: 600)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color(red: 0.07, green: 0.075, blue: 0.11).opacity(0.9)))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - On-screen keyboard (type with the remote)

final class KeyboardModel: ObservableObject {
    @Published var row = 1
    @Published var col = 0
    @Published var shift = false
    static let rows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l", "'"],
        ["⇧", "z", "x", "c", "v", "b", "n", "m", ",", "."],
        ["⌫", "space", "⏎", "←", "→", "@", "-", "?", "!", "✕"],
    ]
}

final class KeyboardPanel {
    static let shared = KeyboardPanel()
    let model = KeyboardModel()
    private lazy var panel: FloatingPanel = {
        let p = FloatingPanel(size: NSSize(width: 760, height: 320))
        p.contentView = NSHostingView(rootView: KeyboardView(model: model, press: { [weak self] r, c in self?.press(r, c) }))
        return p
    }()
    var isOpen: Bool { panel.isVisible }

    func toggle() {
        if isOpen { panel.orderOut(nil); return }
        Input.releaseIfHeld()
        panel.centre(yFraction: 0.25)
        panel.orderFrontRegardless()
    }

    func close() { if isOpen { panel.orderOut(nil) } }

    func handle(_ t: Trigger) -> Bool {
        let rows = KeyboardModel.rows
        // The touch surface always drives the key grid, so you can pick keys the same way everywhere.
        switch t {
        case .swipeUp, .clickUp: model.row = (model.row + rows.count - 1) % rows.count; return true
        case .swipeDown, .clickDown: model.row = (model.row + 1) % rows.count; return true
        case .swipeLeft, .clickLeft: model.col = (model.col + 9) % 10; return true
        case .swipeRight, .clickRight: model.col = (model.col + 1) % 10; return true
        case .select: press(model.row, model.col); return true
        default: break
        }
        // Every physical button except the mic can be given its own job while the keyboard is up.
        if t.group == "Buttons", !t.isSiri {
            if let a = ConfigStore.shared.settings.keyboardKeys[t.rawValue], a.kind != .inherit {
                if a.kind != .none { _ = Runner.run(a) }
                return true
            }
            // Built-in defaults when you haven't customised it
            switch t {
            case .menuTap: panel.orderOut(nil); return true
            case .playTap: Input.key(KeyCode.ret); return true
            default: break
            }
        }
        return false
    }

    func press(_ r: Int, _ c: Int) {
        model.row = r; model.col = c
        let k = KeyboardModel.rows[r][c]
        switch k {
        case "⇧": model.shift.toggle()
        case "⌫": Input.key(KeyCode.delete)
        case "space": Input.key(KeyCode.space)
        case "⏎": Input.key(KeyCode.ret)
        case "←": Input.key(KeyCode.left)
        case "→": Input.key(KeyCode.right)
        case "✕": panel.orderOut(nil)
        default:
            Input.type(model.shift ? k.uppercased() : k)
            model.shift = false
        }
    }
}

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    var press: (Int, Int) -> Void
    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<KeyboardModel.rows.count, id: \.self) { r in
                HStack(spacing: 8) {
                    ForEach(0..<10, id: \.self) { c in
                        let k = KeyboardModel.rows[r][c]
                        let sel = r == model.row && c == model.col
                        Button { press(r, c) } label: {
                            Text(model.shift && k.count == 1 ? k.uppercased() : k)
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .frame(width: 62, height: 46)
                                .background(RoundedRectangle(cornerRadius: 10).fill(sel ? Color.accentColor : Color.primary.opacity(0.08)))
                                .foregroundStyle(sel ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("Swipe to move · click the touch surface to type · Menu closes").font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 760, height: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
}
