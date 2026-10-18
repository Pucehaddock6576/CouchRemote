// BigScreen.swift — a full-screen, TV-style home screen made for the remote (like Steam Big Picture)
import AppKit
import SwiftUI

// MARK: - Model

struct BigTile: Identifiable {
    let id: String
    var title: String
    var subtitle: String
    var icon: NSImage?
    var symbol: String?
    var tint: Color
    var wide: Bool
    var closes: Bool                      // close Big Screen, then run
    var run: () -> String?                // returns a short message to show, if any
    var altLabel: String? = nil           // what a long click does
    var alt: (() -> String?)? = nil
    var push: (() -> BigPage)? = nil      // opens a page inside Big Screen
    var art: URL? = nil                   // artwork / poster from the internet
    var small = false                     // keyboard keys
    var menu: (() -> [BigMenuItem])? = nil  // hold-click menu
    var widget: String? = nil             // a live widget tile (battery, weather…)

    init(id: String, title: String, subtitle: String = "", icon: NSImage? = nil, symbol: String? = nil,
         tint: Color = Color(white: 0.2), wide: Bool = false, closes: Bool = false, run: @escaping () -> String? = { nil }) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.icon = icon; self.symbol = symbol
        self.tint = tint; self.wide = wide; self.closes = closes; self.run = run
    }

    /// A tile that opens another Big Screen page
    static func page(_ id: String, _ title: String, subtitle: String = "", symbol: String? = nil, icon: NSImage? = nil,
                     tint: Color, _ make: @escaping () -> BigPage) -> BigTile {
        var t = BigTile(id: id, title: title, subtitle: subtitle, icon: icon, symbol: symbol, tint: tint)
        t.push = make
        return t
    }
}

struct BigRow: Identifiable {
    let id: String
    var title: String
    var tiles: [BigTile]
    /// Set for rows you can rearrange (hold-click a tile → Move). Gets the tile ids in their new order.
    var reorder: (([String]) -> Void)? = nil
}

/// One choice in a tile's hold-click menu
struct BigMenuItem: Identifiable {
    let id = UUID()
    var title: String
    var symbol: String
    var run: () -> BigMenuResult
}

enum BigMenuResult {
    case done(String?)                    // close the menu (and show a message)
    case submenu(String, [BigMenuItem])   // open a list inside the menu
    case push(BigPage)                    // close the menu and open a page
    case closeScreen                      // close Big Screen (the action already ran)
    case rearrange                        // start moving this tile
}

struct BigMenuState {
    var tileTitle: String
    var stack: [(title: String, items: [BigMenuItem])]
    var index = 0
    var returnIndex: [Int] = []
    var items: [BigMenuItem] { stack.last?.items ?? [] }
    var title: String { stack.last?.title ?? tileTitle }
}

/// The A–Z strip for jumping through long lists
struct JumpState {
    var letters: [String]
    var rows: [Int]
    var index: Int
}

/// One screen inside Big Screen (Home, Apple Music, a playlist, Search…)
struct BigPage {
    var id: String
    var title: String
    var isSearch = false
    var build: () -> [BigRow]
}

final class BigScreenModel: ObservableObject {
    @Published var rows: [BigRow] = []
    @Published var row = 0
    @Published var cols: [String: Int] = [:]
    @Published var focusToken = 0
    @Published var toast = ""
    @Published var pageTitle = ""
    @Published var depth = 0
    @Published var menu: BigMenuState?      // hold-click menu, when open
    @Published var moving: String?          // id of the tile being rearranged
    @Published var jump: JumpState?         // A–Z strip, when open
    @Published var nowPlayingOpen = false   // the full-screen Now Playing view
    @Published var widgetDetail: String?    // a widget opened full screen
    @Published var detailScroll = 0
    @Published var topInset: CGFloat = 0    // height of the display's notch, so the top content clears it

    func col(_ r: Int) -> Int {
        guard rows.indices.contains(r) else { return 0 }
        return min(cols[rows[r].id] ?? 0, max(0, rows[r].tiles.count - 1))
    }

    var focused: BigTile? {
        guard rows.indices.contains(row) else { return nil }
        let c = col(row)
        return rows[row].tiles.indices.contains(c) ? rows[row].tiles[c] : nil
    }
}

final class BigWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    // By default macOS constrains every window to sit *below* the menu bar (and above the Dock), which
    // silently shrinks a full-screen overlay and clipped the top and bottom. Returning the rect unchanged
    // lets Big Screen actually fill the whole display, edge to edge.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// THE fix for the top/bottom clipping. When a SwiftUI view is a borderless window's content view,
/// AppKit still reports a top safe-area inset the size of the menu bar — so SwiftUI lays the header,
/// rows and footer into a box shorter than the screen, riding the header up under the top edge and
/// running the footer off the bottom. (It's also why it flashed correct for one frame, then snapped
/// back: the inset is applied a frame after the first layout.) Forcing the insets to zero makes the
/// SwiftUI content fill the whole window exactly. We also opt out of SwiftUI's own safe-area regions.
final class FullBleedHostingView: NSHostingView<BigScreenView> {
    required init(rootView: BigScreenView) {
        super.init(rootView: rootView)
        if #available(macOS 13.3, *) { safeAreaRegions = [] }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }
}

// MARK: - Controller

final class BigScreen {
    static let shared = BigScreen()
    let model = BigScreenModel()
    private var window: BigWindow?
    private var refreshTimer: Timer?
    private var toastWork: DispatchWorkItem?
    private var lastNavAt = Date.distantPast
    private var lastClickSound = Date.distantPast
    private var navSound: NSSound?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?
    // page stack, with the focus position saved for each page so Back returns you where you were
    private var pages: [(page: BigPage, row: Int, cols: [String: Int])] = []
    private var currentPage: BigPage? { pages.last?.page }

    var isOpen: Bool { window?.isVisible ?? false }
    /// The full-screen Now Playing view is up: swiping and holding sideways fast-forwards and rewinds there
    var seeksOnSwipe: Bool { isOpen && model.nowPlayingOpen }

    func toggle() { isOpen ? close(restore: true) : open() }

    func open() {
        guard !isOpen else { return }
        Input.releaseIfHeld()
        CouchMenu.shared.close()
        KeyboardPanel.shared.close()
        if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]

        if window == nil {
            let w = BigWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            // Above the menu bar (level 24) and the Dock (~20) so the overlay covers them instead of being
            // drawn over — that's what was cutting the header off the top and the footer off the bottom.
            w.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
            w.isOpaque = true
            w.backgroundColor = .black
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.isReleasedWhenClosed = false
            window = w
        }
        // Clear whatever is at the top of this display: the notch if there is one, otherwise at least the
        // menu-bar's worth of space. Guaranteed non-zero so the header is never tucked under the top edge.
        model.topInset = max(max(screen.safeAreaInsets.top, NSStatusBar.system.thickness), 28)
        // Rebuild the SwiftUI tree each open so a theme change (and anything else in Settings) takes effect.
        // FullBleedHostingView reports zero safe-area insets so the content fills the whole window.
        let host = FullBleedHostingView(rootView: BigScreenView(model: model, activate: { [weak self] r, c in self?.activate(r, c) }))
        host.frame = NSRect(origin: .zero, size: screen.frame.size)
        host.autoresizingMask = [.width, .height]
        window?.contentView = host
        guard let w = window else { return }
        w.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)   // keep it above the menu bar / Dock on every open
        w.setFrame(screen.frame, display: true)

        MusicWatcher.shared.poll()
        model.row = 0
        model.cols = [:]
        model.menu = nil; model.moving = nil; model.jump = nil
        pages = [(homePage(), 0, [:])]
        MediaLibrary.shared.onChange = { [weak self] in self?.rebuildIfOpen() }
        SearchStore.shared.onChange = { [weak self] in self?.rebuildIfOpen() }
        MusicExtras.shared.onChange = { [weak self] in self?.rebuildIfOpen() }
        UpNext.shared.onChange = { [weak self] in self?.rebuildIfOpen() }
        Widgets.shared.start()
        SystemInfo.shared.start()
        model.widgetDetail = nil
        rebuild()

        NSApp.activate(ignoringOtherApps: true)
        // NOTE: we deliberately do NOT set NSApp.presentationOptions to auto-hide the menu bar / Dock.
        // The window already sits above both (level mainMenu+1) and covers them, so they're hidden anyway —
        // and the auto-hide animation (~½ s) changes the screen's safe area mid-open, which made the hosting
        // view recompute its insets and snap the layout back to clipped a moment after it appeared correct.
        w.alphaValue = 0
        w.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.22; w.animator().alphaValue = 1 }
        NSCursor.setHiddenUntilMouseMoves(true)

        // Only the Home page needs live refreshing (now playing, running apps); big library pages stay put.
        // Skip a refresh if you navigated in the last ⅓ second, so a rebuild never hitches a swipe.
        refreshTimer = Timer.common(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            guard let self = self, self.pages.count == 1, self.model.menu == nil, self.model.moving == nil,
                  Date().timeIntervalSince(self.lastNavAt) > 0.35 else { return }
            self.rebuild()
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self = self, self.isOpen else { return e }
            // A–Z strip open: typing a letter jumps to it
            if self.model.jump != nil, let ch = e.characters, ch.count == 1, self.jumpTo(ch) { return nil }
            // On a search page, a real keyboard types into the search box
            if self.currentPage?.isSearch == true && self.model.menu == nil {
                if e.keyCode == 51 { SearchStore.shared.backspace(); return nil }
                if let ch = e.characters, ch.count == 1, let u = ch.unicodeScalars.first,
                   CharacterSet.alphanumerics.contains(u) || ch == " " || ch == "'" || ch == "-" {
                    SearchStore.shared.type(ch.lowercased()); return nil
                }
            }
            let map: [UInt16: Trigger] = [123: .swipeLeft, 124: .swipeRight, 125: .swipeDown, 126: .swipeUp,
                                          36: .select, 76: .select, 53: .menuTap]
            guard let t = map[e.keyCode] else { return e }
            _ = self.handle(t)
            return nil
        }
    }

    private func rebuildIfOpen() { if isOpen && model.moving == nil { rebuild() } }

    func close(restore: Bool) {
        guard let w = window, w.isVisible else { return }
        model.nowPlayingOpen = false; model.widgetDetail = nil
        SystemInfo.shared.stop()
        refreshTimer?.invalidate(); refreshTimer = nil
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
        NSApp.presentationOptions = []
        NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.18; w.animator().alphaValue = 0 },
                                             completionHandler: { w.orderOut(nil); w.alphaValue = 1 })
        if restore { previousApp?.activate() }
    }

    /// Remote input while open. Returns true if handled.
    func handle(_ t: Trigger) -> Bool {
        if t == .homeTap { model.menu = nil; model.jump = nil; model.nowPlayingOpen = false; model.widgetDetail = nil; dropMoving(save: true); close(restore: true); return true }
        if model.nowPlayingOpen { handleNowPlaying(t); return true }
        if model.widgetDetail != nil { handleWidgetDetail(t); return true }
        if model.menu != nil { handleMenu(t); return true }
        if model.moving != nil { handleMoving(t); return true }
        if model.jump != nil { handleJump(t); return true }
        switch t {
        case .swipeUp, .clickUp: moveRow(-1)
        case .swipeDown, .clickDown: moveRow(1)
        case .swipeLeft, .clickLeft: moveCol(-1)
        case .swipeRight, .clickRight: moveCol(1)
        case .select: activate(model.row, model.col(model.row))
        case .selectHold: altActivate()
        case .menuTap: back()
        case .playTap: Runner.globalPlayPause()
        default: return false
        }
        return true
    }

    /// Remote input while the full-screen Now Playing view is up
    private func handleNowPlaying(_ t: Trigger) {
        let music = MusicWatcher.shared
        switch t {
        case .menuTap: withAnimation(.easeOut(duration: 0.2)) { model.nowPlayingOpen = false }
        case .select, .playTap: Runner.globalPlayPause()
        case .swipeLeft, .clickLeft: _ = music.skip(forward: false)
        case .swipeRight, .clickRight: _ = music.skip(forward: true)
        case .swipeUp, .clickUp: Input.media(.soundUp)
        case .swipeDown, .clickDown: Input.media(.soundDown)
        default: break
        }
    }

    /// Remote input while a widget is open full screen
    private func handleWidgetDetail(_ t: Trigger) {
        let list = BigWidget.enabled
        guard let cur = model.widgetDetail, let i = list.firstIndex(where: { $0.rawValue == cur }) else { model.widgetDetail = nil; return }
        switch t {
        case .menuTap: withAnimation(.easeOut(duration: 0.2)) { model.widgetDetail = nil }
        case .swipeLeft, .clickLeft:
            model.detailScroll = 0
            withAnimation(.easeOut(duration: 0.2)) { model.widgetDetail = list[(i + list.count - 1) % list.count].rawValue }
        case .swipeRight, .clickRight:
            model.detailScroll = 0
            withAnimation(.easeOut(duration: 0.2)) { model.widgetDetail = list[(i + 1) % list.count].rawValue }
        case .swipeDown, .clickDown: model.detailScroll = min(model.detailScroll + 1, 12)
        case .swipeUp, .clickUp: model.detailScroll = max(model.detailScroll - 1, 0)
        case .select: if list[i] == .ports { SystemInfo.shared.refreshPorts() }   // click on Ports: read them again now
        case .playTap: Runner.globalPlayPause()
        default: break
        }
    }

    /// The widget row on Home: live tiles you can open, hide, and rearrange
    private func widgetRow() -> BigRow? {
        let list = BigWidget.enabled
        guard !list.isEmpty else { return nil }
        let tiles = list.map { k -> BigTile in
            var t = BigTile(id: "w.\(k.rawValue)", title: k.title, subtitle: k.blurb, symbol: k.symbol, tint: k.tint, run: { [unowned self] in
                self.model.detailScroll = 0
                withAnimation(.easeOut(duration: 0.2)) { self.model.widgetDetail = k.rawValue }
                if k == .ports { SystemInfo.shared.refreshPorts() }
                return nil
            })
            t.widget = k.rawValue
            t.menu = { [unowned self] in
                [BigMenuItem(title: "Open", symbol: "arrow.up.left.and.arrow.down.right") {
                    self.model.widgetDetail = k.rawValue; return .done(nil)
                 },
                 BigMenuItem(title: "Hide this widget", symbol: "eye.slash") {
                    ConfigStore.shared.config.settings.bigWidgets.removeAll { $0 == k.rawValue }
                    return .done("Hidden. Turn it back on in Settings → Big Screen → Widgets")
                 }]
            }
            return t
        }
        return BigRow(id: "widgets", title: "At a glance", tiles: tiles, reorder: { ids in
            ConfigStore.shared.config.settings.bigWidgets = ids.compactMap { $0.hasPrefix("w.") ? String($0.dropFirst(2)) : nil }
        })
    }

    // MARK: hold-click menu

    /// What a tile's hold-click menu shows: its own choices, plus Move on rows you can rearrange.
    private func menuItems(row: BigRow, tile: BigTile) -> [BigMenuItem] {
        var items = tile.menu?() ?? []
        if items.isEmpty, let alt = tile.alt, let label = tile.altLabel {
            items.append(BigMenuItem(title: label, symbol: "xmark.circle.fill") { .done(alt()) })
        }
        if row.reorder != nil {
            items.append(BigMenuItem(title: "Move", symbol: "arrow.left.and.right") { .rearrange })
        }
        return items
    }

    private func openMenu() {
        guard model.rows.indices.contains(model.row), let tile = model.focused else { return }
        let items = menuItems(row: model.rows[model.row], tile: tile)
        guard !items.isEmpty else { return }
        model.menu = BigMenuState(tileTitle: tile.title, stack: [(tile.title, items)])
        click()
    }

    private func handleMenu(_ t: Trigger) {
        guard var m = model.menu else { return }
        switch t {
        case .swipeUp, .clickUp: m.index = max(0, m.index - 1)
        case .swipeDown, .clickDown: m.index = min(max(0, m.items.count - 1), m.index + 1)
        case .select, .swipeRight, .clickRight:
            guard m.items.indices.contains(m.index) else { return }
            chooseMenu(m.items[m.index])
            return
        case .menuTap, .swipeLeft, .clickLeft:
            if m.stack.count > 1 {
                m.stack.removeLast()
                m.index = m.returnIndex.popLast() ?? 0
            } else {
                model.menu = nil; return
            }
        default: return
        }
        model.menu = m
        click()
    }

    private func chooseMenu(_ item: BigMenuItem) {
        let result = item.run()
        switch result {
        case .done(let msg):
            model.menu = nil
            showToast(msg)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.rebuild() }
        case .submenu(let title, let items):
            guard var m = model.menu else { return }
            m.returnIndex.append(m.index)
            m.stack.append((title, items.isEmpty ? [BigMenuItem(title: "Nothing here yet", symbol: "tray") { .done(nil) }] : items))
            m.index = 0
            model.menu = m
        case .push(let page):
            model.menu = nil
            push(page)
        case .closeScreen:
            model.menu = nil
            close(restore: false)
        case .rearrange:
            model.menu = nil
            model.moving = model.focused?.id
            showToast("Swipe left or right to move it, then click to drop it")
        }
    }

    // MARK: rearrange

    private func handleMoving(_ t: Trigger) {
        guard model.rows.indices.contains(model.row) else { dropMoving(save: false); return }
        let r = model.row
        switch t {
        case .swipeLeft, .clickLeft, .swipeRight, .clickRight:
            let d = (t == .swipeLeft || t == .clickLeft) ? -1 : 1
            let c = model.col(r), n = c + d
            guard model.rows[r].tiles.indices.contains(n) else { return }
            model.rows[r].tiles.swapAt(c, n)
            model.cols[model.rows[r].id] = n
            model.focusToken += 1
            click()
        case .select, .menuTap, .selectHold, .swipeUp, .swipeDown, .clickUp, .clickDown:
            dropMoving(save: true)
            showToast("Moved")
        default:
            break
        }
    }

    private func dropMoving(save: Bool) {
        guard model.moving != nil else { return }
        model.moving = nil
        if save, model.rows.indices.contains(model.row), let reorder = model.rows[model.row].reorder {
            reorder(model.rows[model.row].tiles.map(\.id))
        }
        rebuild()
    }

    // MARK: A–Z jump

    /// Long lists are split into one row per letter. Swiping past the top or bottom opens an A–Z strip.
    private func openJump() -> Bool {
        let letterRows = model.rows.indices.filter { model.rows[$0].title.count == 1 && model.rows[$0].id.contains(".") }
        guard letterRows.count >= 3 else { return false }
        let current = letterRows.lastIndex { $0 <= model.row } ?? 0
        model.jump = JumpState(letters: letterRows.map { model.rows[$0].title }, rows: letterRows, index: current)
        click()
        return true
    }

    private func handleJump(_ t: Trigger) {
        guard var j = model.jump else { return }
        switch t {
        case .swipeLeft, .clickLeft: j.index = (j.index + j.letters.count - 1) % j.letters.count
        case .swipeRight, .clickRight: j.index = (j.index + 1) % j.letters.count
        case .select:
            model.jump = nil
            model.row = j.rows[j.index]
            model.focusToken += 1
            click()
            return
        case .menuTap, .swipeUp, .swipeDown, .clickUp, .clickDown:
            model.jump = nil
            return
        default: return
        }
        model.jump = j
        click()
    }

    /// Jumps straight to a letter (typing on a real keyboard while the strip is open)
    private func jumpTo(_ letter: String) -> Bool {
        guard let j = model.jump, let i = j.letters.firstIndex(of: letter.uppercased()) else { return false }
        model.jump = nil
        model.row = j.rows[i]
        model.focusToken += 1
        return true
    }

    // MARK: pages

    func push(_ p: BigPage) {
        if !pages.isEmpty { pages[pages.count - 1].row = model.row; pages[pages.count - 1].cols = model.cols }
        pages.append((p, 0, [:]))
        model.row = 0; model.cols = [:]
        if p.isSearch { SearchStore.shared.clear() }
        rebuild()
        model.focusToken += 1
    }

    private func back() {
        guard pages.count > 1 else { close(restore: true); return }
        pages.removeLast()
        model.row = pages.last?.row ?? 0
        model.cols = pages.last?.cols ?? [:]
        rebuild()
        model.focusToken += 1
    }

    private func moveRow(_ d: Int) {
        let r = model.row + d
        guard model.rows.indices.contains(r) else { _ = openJump(); return }
        model.row = r
        model.focusToken += 1
        click()
    }

    private func moveCol(_ d: Int) {
        guard model.rows.indices.contains(model.row) else { return }
        let row = model.rows[model.row]
        let c = model.col(model.row) + d
        guard row.tiles.indices.contains(c) else { return }
        model.cols[row.id] = c
        model.focusToken += 1
        click()
    }

    private func click() {
        lastNavAt = Date()
        guard ConfigStore.shared.settings.clickSound else { return }
        // Cache the sound and don't machine-gun it during a fast glide, or playing it stalls navigation
        let now = Date()
        guard now.timeIntervalSince(lastClickSound) > 0.07 else { return }
        lastClickSound = now
        if navSound == nil { navSound = NSSound(named: "Tink") }
        navSound?.stop(); navSound?.play()
    }

    func activate(_ r: Int, _ c: Int) {
        guard model.rows.indices.contains(r), model.rows[r].tiles.indices.contains(c) else { return }
        model.row = r
        model.cols[model.rows[r].id] = c
        model.focusToken += 1
        let tile = model.rows[r].tiles[c]
        if let make = tile.push {
            push(make())
        } else if tile.closes {
            close(restore: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { _ = tile.run() }
        } else {
            showToast(tile.run())
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.rebuild() }
        }
    }

    /// Hold-click: opens the tile's menu (Play next, Add to playlist, Move…)
    private func altActivate() {
        guard model.rows.indices.contains(model.row), let tile = model.focused else { return }
        if !menuItems(row: model.rows[model.row], tile: tile).isEmpty { openMenu(); return }
        guard let alt = tile.alt else { return }
        showToast(alt())
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.rebuild() }
    }

    /// Whether the focused tile has a hold-click menu (for the hint at the bottom)
    var focusedHasMenu: Bool {
        guard model.rows.indices.contains(model.row), let tile = model.focused else { return false }
        return tile.menu != nil || model.rows[model.row].reorder != nil
    }

    func showToast(_ s: String?) {
        guard let s = s, !s.isEmpty, ConfigStore.shared.settings.hudEnabled(.bigScreen) else { return }
        model.toast = s
        toastWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.model.toast = "" }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: w)
    }

    func rebuild() {
        guard let p = currentPage else { return }
        let previousRows = model.rows
        let previousRowID = previousRows.indices.contains(model.row) ? previousRows[model.row].id : nil
        let rows = p.build()
        let rowStructureChanged = previousRows.map(\.id) != rows.map(\.id)
        let nowPlayingAppearedOrDisappeared = p.id == "home"
            && previousRows.contains(where: { $0.id == "now" }) != rows.contains(where: { $0.id == "now" })

        model.rows = rows
        model.pageTitle = p.title
        model.depth = pages.count - 1

        if nowPlayingAppearedOrDisappeared {
            // The Now Playing row is inserted at the very top of Home. Reset to the top row so
            // the new card is visible, rather than retaining a scroll offset from the old layout.
            model.row = 0
        } else if let previousRowID, let newRow = rows.firstIndex(where: { $0.id == previousRowID }) {
            // Keep focus on the same row when asynchronous content adds or removes other rows.
            model.row = newRow
        } else {
            model.row = min(model.row, max(0, rows.count - 1))
        }

        // Row insertion/removal changes the geometry of the lazy stack. Nudge its scroll view to
        // resolve the new focus against the updated layout instead of retaining a stale position.
        if rowStructureChanged { model.focusToken += 1 }
    }

    // MARK: rows

    static let palette: [Color] = [
        Color(red: 0.89, green: 0.20, blue: 0.24), Color(red: 0.16, green: 0.42, blue: 0.93), Color(red: 0.10, green: 0.62, blue: 0.58),
        Color(red: 0.95, green: 0.55, blue: 0.13), Color(red: 0.42, green: 0.30, blue: 0.86), Color(red: 0.86, green: 0.25, blue: 0.56),
        Color(red: 0.22, green: 0.64, blue: 0.30), Color(red: 0.55, green: 0.35, blue: 0.20),
    ]

    func buildRows() -> [BigRow] {
        let s = ConfigStore.shared.settings
        var rows: [BigRow] = []
        let music = MusicWatcher.shared
        let pink = Color(red: 0.92, green: 0.26, blue: 0.45)

        // Now playing (the card shows the song’s cover once it’s been found)
        if let name = music.app {
            NowPlayingArt.shared.update()
            let bid = music.bundleID ?? ""
            var tiles = [
                BigTile(id: "now.card", title: music.track.isEmpty ? name : music.track,
                        subtitle: (music.artist.isEmpty ? "" : music.artist + " · ") + name,
                        icon: NowPlayingArt.shared.cover ?? (music.otherBundleID != nil ? NowPlaying.shared.artwork : nil) ?? appIcon(bid), tint: pink, wide: true,
                        run: { [unowned self] in
                            if ConfigStore.shared.settings.nowPlayingFull { self.model.nowPlayingOpen = true; NowPlayingArt.shared.update() }
                            else { music.playPause() }
                            return nil
                        }),
                BigTile(id: "now.prev", title: "Previous", symbol: "backward.fill", tint: pink.opacity(0.75),
                        run: { music.skip(forward: false); return nil }),
                BigTile(id: "now.play", title: music.playing ? "Pause" : "Play", symbol: music.playing ? "pause.fill" : "play.fill",
                        tint: pink.opacity(0.75), run: { music.playPause(); return nil }),
                BigTile(id: "now.next", title: "Next", symbol: "forward.fill", tint: pink.opacity(0.75),
                        run: { music.skip(forward: true); return nil }),
                BigTile(id: "now.vdown", title: "Volume −", symbol: "speaker.wave.1.fill", tint: Color(white: 0.24),
                        run: { Input.media(.soundDown); return nil }),
                BigTile(id: "now.vup", title: "Volume +", symbol: "speaker.wave.3.fill", tint: Color(white: 0.24),
                        run: { Input.media(.soundUp); return nil }),
            ]
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                tiles.append(BigTile(id: "now.open", title: "Open \(name)", icon: appIcon(bid), closes: true, run: {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()); return nil
                }))
            }
            rows.append(BigRow(id: "now", title: music.playing ? "Now Playing" : "Paused", tiles: tiles))
        }

        if let w = widgetRow() { rows.append(w) }
        rows.append(browseRow())

        // Favourite apps
        let favs: [BigTile] = s.favourites.compactMap { bid in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) else { return nil }
            let name = url.deletingPathExtension().lastPathComponent
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first
            var t = BigTile(id: "fav.\(bid)", title: name, subtitle: running != nil ? "Open" : "",
                            icon: NSWorkspace.shared.icon(forFile: url.path), closes: true, run: {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()); return nil
            })
            if let app = running { t.altLabel = "Quit \(name)"; t.alt = { app.terminate(); return "Quit \(name)" } }
            t.menu = {
                var items = [BigMenuItem(title: "Open", symbol: "arrow.up.forward.app") {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()); return .closeScreen
                }]
                if let app = running {
                    items.append(BigMenuItem(title: "Hide", symbol: "eye.slash") { app.hide(); return .done("Hid \(name)") })
                    items.append(BigMenuItem(title: "Quit", symbol: "xmark.circle.fill") { app.terminate(); return .done("Quit \(name)") })
                }
                items.append(BigMenuItem(title: "Remove from Apps", symbol: "minus.circle") {
                    ConfigStore.shared.config.settings.favourites.removeAll { $0 == bid }
                    return .done("Removed \(name)")
                })
                return items
            }
            return t
        }
        if !favs.isEmpty {
            rows.append(BigRow(id: "apps", title: "Apps", tiles: favs, reorder: { ids in
                let order = ids.compactMap { $0.hasPrefix("fav.") ? String($0.dropFirst(4)) : nil }
                let rest = ConfigStore.shared.settings.favourites.filter { !order.contains($0) }
                ConfigStore.shared.config.settings.favourites = order + rest
            }))
        }

        // Streaming / web shortcuts
        let web: [BigTile] = s.bigScreenShortcuts.enumerated().compactMap { i, sc in
            guard let url = URL(string: sc.url), url.scheme != nil else { return nil }
            var t = BigTile(id: "web.\(sc.id)", title: sc.name, subtitle: url.host ?? "",
                            tint: Self.palette[i % Self.palette.count], closes: true,
                            run: { NSWorkspace.shared.open(url); return nil })
            t.menu = {
                [BigMenuItem(title: "Open", symbol: "safari") { NSWorkspace.shared.open(url); return .closeScreen },
                 BigMenuItem(title: "Remove", symbol: "minus.circle") {
                     ConfigStore.shared.config.settings.bigScreenShortcuts.removeAll { $0.id == sc.id }
                     return .done("Removed \(sc.name)")
                 }]
            }
            return t
        }
        if !web.isEmpty {
            rows.append(BigRow(id: "watch", title: "Watch", tiles: web, reorder: { ids in
                let all = ConfigStore.shared.settings.bigScreenShortcuts
                let ordered = ids.compactMap { id in all.first { "web.\($0.id)" == id } }
                ConfigStore.shared.config.settings.bigScreenShortcuts = ordered + all.filter { sc in !ordered.contains { $0.id == sc.id } }
            }))
        }

        // Running apps
        let running: [BigTile] = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
            .map { app in
                let name = app.localizedName ?? "App"
                var t = BigTile(id: "run.\(app.processIdentifier)", title: name,
                                subtitle: app.processIdentifier == previousApp?.processIdentifier ? "Last used" : "",
                                icon: app.icon, closes: true, run: { app.activate(); return nil })
                t.altLabel = "Quit \(name)"
                t.alt = { app.terminate(); return "Quit \(name)" }
                return t
            }
        if !running.isEmpty { rows.append(BigRow(id: "open", title: "Open now", tiles: running)) }

        // Controls
        let teal = Color(red: 0.10, green: 0.50, blue: 0.55)
        let timerText = SleepTimer.shared.fireAt.map { "At " + DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) } ?? "Off"
        rows.append(BigRow(id: "controls", title: "Controls", tiles: [
            BigTile(id: "c.mode", title: "Touch: \(Engine.shared.mode.short)", subtitle: "Click to switch", symbol: Engine.shared.mode.symbol,
                    tint: teal, run: { _ = Engine.shared.cycleMode(); return nil }),
            BigTile(id: "c.timer", title: "Sleep timer", subtitle: timerText, symbol: "timer", tint: teal,
                    run: { SleepTimer.shared.cycle() }),
            BigTile(id: "c.awake", title: "Keep awake", subtitle: "On/off", symbol: "cup.and.saucer.fill", tint: teal,
                    run: { Runner.run(.k(.keepAwake)) }),
            BigTile(id: "c.spot", title: "Mousespot", symbol: "flashlight.on.fill", tint: teal, closes: true,
                    run: { _ = Spotlight.shared.toggle(); return nil }),
            BigTile(id: "c.keys", title: "Keyboard", subtitle: "Type with swipes", symbol: "keyboard", tint: teal, closes: true,
                    run: { KeyboardPanel.shared.toggle(); return nil }),
            BigTile(id: "c.pip", title: "Picture in picture", subtitle: "Web video", symbol: "pip.enter", tint: teal, closes: true,
                    run: { Runner.run(.k(.webPiP)) }),
            BigTile(id: "c.mission", title: "Mission Control", symbol: "rectangle.3.group", tint: teal, closes: true,
                    run: { Runner.run(.k(.missionControl)) }),
            BigTile(id: "c.desktop", title: "Show desktop", symbol: "menubar.dock.rectangle", tint: teal, closes: true,
                    run: { Runner.run(.k(.showDesktop)) }),
            BigTile(id: "c.menu", title: "Couch Menu", subtitle: "Files & more", symbol: "list.bullet.rectangle.fill", tint: teal, closes: true,
                    run: { CouchMenu.shared.open(); return nil }),
            BigTile(id: "c.settings", title: "Settings", symbol: "gearshape.fill", tint: Color(white: 0.3), closes: true,
                    run: { (NSApp.delegate as? AppDelegate)?.showWindow(); return nil }),
        ]))

        // Power
        let night = Color(red: 0.20, green: 0.22, blue: 0.40)
        rows.append(BigRow(id: "power", title: "Power", tiles: [
            BigTile(id: "p.screen", title: "Screen off", symbol: "display", tint: night, closes: true, run: { Runner.run(.k(.displaySleep)) }),
            BigTile(id: "p.lock", title: "Lock", symbol: "lock.fill", tint: night, closes: true, run: { Runner.run(.k(.lockScreen)) }),
            BigTile(id: "p.sleep", title: "Sleep Mac", symbol: "moon.fill", tint: night, closes: true, run: { Runner.run(.k(.sleepMac)) }),
        ]))
        return rows
    }
}

// MARK: - Settings screen

struct BigScreenTab: View {
    @ObservedObject var store = ConfigStore.shared
    @ObservedObject var widgets = Widgets.shared
    @ObservedObject var music = MusicWatcher.shared

    private var nowPlayingNote: String {
        let np = NowPlaying.shared
        if !np.available { return "Not available on this Mac. Music and Spotify still work as before." }
        if let app = music.otherBundleID.flatMap({ _ in music.app }) { return "Working: it can see \(app) right now." }
        if np.everWorked { return "Working. Play something in a browser or another app to see it." }
        return "Uses a hidden part of macOS. On some newer macOS versions it can still play, pause and skip, but can't read what's playing. Music and Spotify always work."
    }

    var body: some View {
        Form {
            Section {
                Text("A full-screen home screen built for the remote, like Steam Big Picture. By default the TV button opens it. You can change that on the Buttons screen.")
                    .foregroundStyle(.secondary)
                Button("Open Big Screen now") { BigScreen.shared.open() }
                Text("Rows: Now Playing · Browse (Apple Music, TV, Search, Podcasts, Movies, Files) · Apps · Watch · Open now · Controls · Power. Swipe or use the arrow keys to move, click or Return to open, Menu or Esc to go back, and the TV button to close. Hold the click on any tile for options (Play next, Add to playlist, Love, Move…). In long lists, swipe past the top or bottom for an A–Z strip. The first time you open Apple Music or TV, macOS asks to let Couch Remote control them: click OK.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Theme") {
                Picker("Look", selection: $store.config.settings.bigTheme) {
                    ForEach(BigTheme.allCases) { t in Text(t.title).tag(t) }
                }
                .pickerStyle(.segmented)
                Text(store.config.settings.bigTheme.blurb).font(.caption).foregroundStyle(.secondary)
                Text("Changing the theme takes effect next time you open Big Screen.").font(.caption).foregroundStyle(.secondary)
            }
            Section("YouTube") {
                Text("A built‑in, remote‑friendly YouTube. It opens YouTube's TV layout so you can browse and play with the remote: swipe or use the edges to move, click to choose, Play/Pause to pause, Menu to go back, and the TV button to close.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open YouTube now") { YouTubeApp.shared.open() }
                Toggle("Ask YouTube for its TV layout (recommended)", isOn: $store.config.settings.youtubeTVUserAgent)
                HStack {
                    Text("Address").foregroundStyle(.secondary)
                    TextField("https://www.youtube.com/tv", text: $store.config.settings.youtubeURL)
                        .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                }
                Text("If the TV page won't load, turn the switch off, or set the address to https://m.youtube.com or https://www.youtube.com and use Trackpad mode to point and click.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Watch row (opens in your browser)") {
                ForEach(store.config.settings.bigScreenShortcuts) { sc in
                    HStack {
                        TextField("Name", text: field(sc.id, \.name)).frame(width: 160)
                        TextField("https://…", text: field(sc.id, \.url))
                        Button { store.config.settings.bigScreenShortcuts.removeAll { $0.id == sc.id } } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Button("Add shortcut") { store.config.settings.bigScreenShortcuts.append(WebShortcut(name: "New", url: "https://")) }
                    Button("Restore defaults") { store.config.settings.bigScreenShortcuts = WebShortcut.defaults }
                }
            }
            WidgetSettingsSection()
            Section("Music and search") {
                Toggle("Recently played and Recently added in Apple Music", isOn: $store.config.settings.recentRows)
                Text("Reading these takes a few seconds on very big libraries.").font(.caption).foregroundStyle(.secondary)
                Toggle("Remember my searches", isOn: $store.config.settings.rememberSearches)
                HStack {
                    Text("\(store.config.settings.recentSearches.count) saved").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear search history") { SearchStore.shared.forgetRecent() }
                }
                Toggle("Know what's playing in any app (browsers, Podcasts, IINA, VLC…)", isOn: $store.config.settings.systemNowPlaying)
                Text(nowPlayingNote).font(.caption).foregroundStyle(.secondary)
                Toggle("Clicking Now Playing opens a full‑screen view with the cover", isOn: $store.config.settings.nowPlayingFull)
                Toggle("Play Apple Music’s moving album art there when an album has it", isOn: $store.config.settings.liveAlbumArt)
                    .disabled(!store.config.settings.nowPlayingFull)
            }
            Section("Navigation") {
                slider("Swipe per step", $store.config.settings.navStep, 0.06...0.35)
                Text("How far you glide your thumb to move one tile. Smaller moves faster. This also applies to the Couch Menu and on-screen keyboard.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func field(_ id: UUID, _ kp: WritableKeyPath<WebShortcut, String>) -> Binding<String> {
        Binding(
            get: { store.config.settings.bigScreenShortcuts.first { $0.id == id }?[keyPath: kp] ?? "" },
            set: { v in
                if let i = store.config.settings.bigScreenShortcuts.firstIndex(where: { $0.id == id }) {
                    store.config.settings.bigScreenShortcuts[i][keyPath: kp] = v
                }
            })
    }
}
