// BigScreenViews.swift — how Big Screen looks: an ambient background, header, rows of glassy tiles,
// the widget row, footer hints, and the hold-click menu
import AppKit
import SwiftUI

/// The shared look. Two themes: a faithful Apple TV style (dark and neutral, the focused tile lifts on
/// a big soft shadow) and the colourful "Midnight" default. The colours are computed from the current
/// theme so switching takes effect the next time Big Screen opens.
enum BigStyle {
    static var theme: BigTheme { ConfigStore.shared.settings.bigTheme }
    static var tv: Bool { theme == .tvOS }
    static var base: Color { tv ? Color(red: 0.015, green: 0.016, blue: 0.022) : Color(red: 0.035, green: 0.04, blue: 0.075) }
    static var glass: Color { Color.white.opacity(tv ? 0.08 : 0.09) }
    static var hairline: Color { Color.white.opacity(tv ? 0.14 : 0.12) }
    static var panel: Color { tv ? Color(red: 0.1, green: 0.1, blue: 0.12) : Color(red: 0.08, green: 0.085, blue: 0.12) }
}

/// A soft glow behind everything. In Midnight it's a colourful wash that picks up the selected tile.
/// In the Apple TV theme it's a dark, almost‑neutral lift from the upper middle with only a whisper of
/// the focused tile's colour — like tvOS. Built from radial gradients, not Gaussian blur, so it's cheap
/// to draw even on a MacBook Air and never stutters while you navigate. The cover of what's playing is a
/// separate layer (see CoverWash) so it only redraws when the song changes.
struct AmbientBackground: View {
    var accent: Color

    /// A soft blob of colour, as a radial gradient (far cheaper than a blurred circle)
    private func blob(_ color: Color, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, in g: CGSize) -> some View {
        RadialGradient(colors: [color, color.opacity(0)], center: .center, startRadius: 0, endRadius: r * min(g.width, g.height))
            .frame(width: g.width, height: g.height)
            .position(x: g.width * cx, y: g.height * cy)
    }

    var body: some View {
        GeometryReader { geo in
            let g = geo.size
            ZStack {
                BigStyle.base
                if BigStyle.tv {
                    // tvOS: a neutral lift from the upper middle, a faint breath of the focused colour, and a
                    // gentle darkening towards the edges and bottom so the tiles sit on near‑black.
                    RadialGradient(colors: [Color(red: 0.1, green: 0.11, blue: 0.14), BigStyle.base],
                                   center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: max(g.width, g.height) * 0.9)
                        .frame(width: g.width, height: g.height)
                    blob(accent.opacity(0.1), 0.5, 0.14, 0.7, in: g)
                    LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                } else {
                    blob(accent.opacity(0.5), 0.18, 0.1, 0.6, in: g)
                    blob(Color(red: 0.36, green: 0.22, blue: 0.88).opacity(0.4), 0.82, 0.78, 0.6, in: g)
                    blob(Color(red: 0.05, green: 0.55, blue: 0.75).opacity(0.28), 0.6, 0.3, 0.45, in: g)
                    LinearGradient(colors: [Color.black.opacity(0.05), Color.black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                }
            }
            .animation(.easeInOut(duration: 0.6), value: accent)
        }
        .ignoresSafeArea()
    }
}

/// The cover of what's playing, washed across the background. Its own view, keyed by the image,
/// so it only redraws when the song changes — not on every navigation or stats update.
struct CoverWash: View, Equatable {
    let cover: NSImage?
    static func == (a: CoverWash, b: CoverWash) -> Bool { a.cover === b.cover }

    var body: some View {
        GeometryReader { geometry in
            if let c = cover {
                Image(nsImage: c).resizable().aspectRatio(contentMode: .fill)
                    // Artwork arrives after playback starts. Keep it constrained to the existing
                    // full-screen background so its intrinsic size/safe area cannot resize the layout.
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .opacity(0.22)
                    .overlay(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

/// A small rounded pill for status in the header
struct GlassPill<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack(spacing: 8) { content() }
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(BigStyle.glass))
            .overlay(Capsule().stroke(BigStyle.hairline, lineWidth: 1))
    }
}

struct BigScreenView: View {
    @ObservedObject var model: BigScreenModel
    @ObservedObject var art = NowPlayingArt.shared
    @ObservedObject var music = MusicWatcher.shared
    @ObservedObject var store = ConfigStore.shared   // so switching the theme re-renders the screen live
    var activate: (Int, Int) -> Void

    private var accent: Color { model.focused?.tint ?? Color(red: 0.92, green: 0.26, blue: 0.45) }

    var body: some View {
        // Force the content to the full window size, measured ignoring the safe area, so nothing — not a
        // late safe-area recompute, not the menu bar hiding — can shrink the layout and clip top or bottom.
        GeometryReader { geo in
            ZStack {
                // The background and rows don't observe the frequently-updating stats/clock, so those
                // updates can't make the whole screen (or the heavy glow) redraw while you navigate.
                AmbientBackground(accent: accent)
                CoverWash(cover: music.app != nil ? art.cover : nil).equatable()
                // The background fills the whole screen (including behind the notch); the header, rows and
                // footer are pushed down by the measured notch height so the top is never hidden by it.
                VStack(alignment: .leading, spacing: 0) {
                    BigHeader(model: model)
                    BigRows(model: model, activate: activate)
                    BigFooter(model: model)
                }
                .padding(.top, model.topInset)
                if let j = model.jump { JumpStripView(jump: j) }
                if let m = model.menu { BigMenuView(menu: m).transition(.opacity) }
                if model.nowPlayingOpen { NowPlayingFullView().transition(.opacity) }
                if let d = model.widgetDetail, let k = BigWidget(rawValue: d) {
                    WidgetDetailView(kind: k, scroll: model.detailScroll).id(d).transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }
}

/// The top bar: greeting/title on the left, live status pills and clock on the right.
/// This is the only part that observes the fast-updating stats, so a battery or clock tick
/// redraws just this strip.
struct BigHeader: View {
    @ObservedObject var model: BigScreenModel
    @ObservedObject var engine = Engine.shared
    @ObservedObject var widgets = Widgets.shared
    @ObservedObject var sys = SystemInfo.shared

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            if model.depth > 0 {
                Image(systemName: "chevron.left").font(.system(size: 20, weight: .bold))
                    .frame(width: 46, height: 46).background(Circle().fill(BigStyle.glass))
                    .overlay(Circle().stroke(BigStyle.hairline, lineWidth: 1))
                Text(model.pageTitle).font(.system(size: 34, weight: .heavy, design: .rounded)).lineLimit(1)
            } else {
                Image(systemName: "appletvremote.gen1.fill").font(.system(size: 22, weight: .semibold))
                    .frame(width: 50, height: 50)
                    .background(RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.95, green: 0.3, blue: 0.5), Color(red: 0.45, green: 0.25, blue: 0.95)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)))
                VStack(alignment: .leading, spacing: 0) {
                    Text(greeting).font(.system(size: 32, weight: .heavy, design: .rounded))
                    Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.system(size: 16, weight: .medium)).foregroundStyle(Color.white.opacity(0.6))
                }
            }
            Spacer()
            if let f = widgets.forecast {
                GlassPill { Image(systemName: f.symbol).renderingMode(.original); Text("\(f.temp)°") }
            }
            if let b = sys.battery {
                GlassPill {
                    Image(systemName: batterySymbol(b.percent, charging: b.charging))
                        .foregroundStyle(b.percent < 20 && !b.charging ? Color.red : Color.white)
                    Text("\(b.percent)%")
                }
            }
            GlassPill {
                Circle().fill(engine.connected ? Color.green : Color.orange).frame(width: 9, height: 9)
                Image(systemName: "appletvremote.gen1")
                if let b = engine.battery { Text("\(b)%") }
            }
            TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                Text(ctx.date, style: .time).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
            }
            .padding(.leading, 6)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 60).padding(.top, 10).padding(.bottom, 4)
    }
}

/// The scrolling rows. Observes the model (and music.playing for the Now Playing bars), but not the
/// stats, so navigation stays smooth. The scroll animation is a quick ease, so fast swipes keep up.
struct BigRows: View {
    @ObservedObject var model: BigScreenModel
    @ObservedObject var music = MusicWatcher.shared
    var activate: (Int, Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                // Lazy, so a library with thousands of songs only draws what's on screen
                LazyVStack(alignment: .leading, spacing: 10) {
                    // A reliable top anchor. Scrolling to a real row in a LazyVStack can overshoot (it can't
                    // measure rows it hasn't drawn yet), which cut the top row in half. This never moves, so
                    // landing on the top row is exact, and its height leaves a little breathing room.
                    Color.clear.frame(height: 44).id("big.top")
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { r, row in
                        BigRowView(row: row, rowIndex: r, model: model, playing: music.playing, activate: activate)
                            .id(row.id)
                    }
                }
                .padding(.bottom, 20)
            }
            .onChange(of: model.focusToken) { _ in
                guard model.rows.indices.contains(model.row) else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    // Pin the first row to the top (via the fixed anchor) and the last to the bottom so neither
                    // gets cut off; centre the ones in between.
                    if model.row == 0 { proxy.scrollTo("big.top", anchor: .top) }
                    else if model.row == model.rows.count - 1 { proxy.scrollTo(model.rows[model.row].id, anchor: .bottom) }
                    else { proxy.scrollTo(model.rows[model.row].id, anchor: .center) }
                }
            }
        }
    }
}

struct BigFooter: View {
    @ObservedObject var model: BigScreenModel

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 22) {
                hint("hand.draw.fill", "Swipe to move")
                hint("cursorarrow.click", "Click to open")
                if model.moving != nil { hint("arrow.left.and.right", "Swipe to move · click to drop") }
                else if BigScreen.shared.focusedHasMenu { hint("hand.tap.fill", "Hold click: options") }
                else if let alt = model.focused?.altLabel { hint("hand.tap.fill", "Hold click: \(alt)") }
                hint("playpause.fill", "Play/Pause")
                hint("arrow.uturn.backward", model.depth > 0 ? "Menu: back" : "Menu: close")
                if model.depth > 0 { hint("tv", "TV: close") }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Capsule().fill(BigStyle.glass))
            .overlay(Capsule().stroke(BigStyle.hairline, lineWidth: 1))
            Spacer()
            if !model.toast.isEmpty {
                Text(model.toast).font(.system(size: 18, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .foregroundStyle(Color.white.opacity(0.75))
        .padding(.horizontal, 60).padding(.top, 8).padding(.bottom, 34)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.toast)
    }

    private func hint(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 15, weight: .medium)).lineLimit(1)
    }
}

struct BigRowView: View {
    let row: BigRow
    let rowIndex: Int
    @ObservedObject var model: BigScreenModel
    let playing: Bool
    var activate: (Int, Int) -> Void

    // keyboard rows sit closer together
    private var compact: Bool { row.tiles.contains { $0.small } }
    private var current: Bool { rowIndex == model.row }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !row.title.isEmpty {
                HStack(spacing: 10) {
                    Capsule().fill(Color.white).frame(width: 4, height: current ? 22 : 0).opacity(current ? 1 : 0)
                    Text(row.title)
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(current ? 1 : 0.5))
                }
                .padding(.leading, current ? 56 : 60)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: current)
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: compact ? 14 : 26) {
                        ForEach(Array(row.tiles.enumerated()), id: \.element.id) { c, tile in
                            BigTileView(tile: tile, focused: current && c == model.col(rowIndex), playing: playing,
                                        moving: model.moving == tile.id)
                                .id(tile.id)
                                .onTapGesture { activate(rowIndex, c) }
                        }
                    }
                    // Top padding has to clear the focused tile's grow-and-lift (it scales up and casts a big
                    // soft shadow); 26 was a touch too tight, so the top of the Now Playing tile got clipped.
                    .padding(.horizontal, 60).padding(.top, compact ? 24 : 48).padding(.bottom, compact ? 12 : 44)
                }
                .onChange(of: model.focusToken) { _ in
                    let c = model.col(rowIndex)
                    guard current, row.tiles.indices.contains(c) else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(row.tiles[c].id, anchor: .center) }
                }
            }
        }
        .opacity(current || model.row < 0 ? 1 : 0.92)
    }
}

struct BigTileView: View {
    let tile: BigTile
    let focused: Bool
    let playing: Bool
    var moving = false

    /// How much bigger the tile gets when it's selected (or being moved)
    private var grow: CGFloat { moving ? 1.14 : (focused ? (tile.small ? 1.16 : 1.09) : 1) }
    private var isWidget: Bool { tile.widget != nil }
    private var showsLabels: Bool { !tile.wide && !tile.small && !isWidget }
    private var tv: Bool { BigStyle.tv }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                if isWidget {
                    // Widgets are solid cards (a dark base with a gentle colour tint), never see‑through
                    shape.fill(BigStyle.panel)
                    shape.fill(LinearGradient(colors: [tile.tint.opacity(0.55), tile.tint.opacity(0.12)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    shape.fill(LinearGradient(colors: [tile.tint, tile.tint.opacity(0.55)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                content
                // A soft shine across the top, brighter when selected (brightest in the Apple TV theme, for that specular lift)
                shape.fill(LinearGradient(colors: [Color.white.opacity(focused ? (tv ? 0.32 : 0.26) : (tv ? 0.10 : 0.13)), Color.white.opacity(0)],
                                          startPoint: .top, endPoint: .center))
                    .allowsHitTesting(false)
            }
            .frame(width: width, height: height)
            .background { if isWidget { BigStyle.base.clipShape(shape) } }   // fully opaque behind the card
            .clipShape(shape)
            .overlay(
                Group {
                    if moving {
                        shape.stroke(Color.yellow, style: StrokeStyle(lineWidth: 5, dash: [14, 8]))
                    } else {
                        // tvOS edges a focused tile with just a faint bright rim; Midnight uses a bold white border
                        shape.strokeBorder(Color.white.opacity(focused ? (tv ? 0.3 : 0.95) : 0.10),
                                           lineWidth: focused ? (tv ? 2 : (tile.small ? 3 : 4)) : 1)
                    }
                }
            )
            // tvOS: a large, soft, neutral drop shadow so the focused tile floats. Midnight: a coloured glow.
            .shadow(color: focused ? (tv ? Color.black.opacity(0.75) : tile.tint.opacity(0.7)) : Color.black.opacity(0.45),
                    radius: focused ? (tv ? 44 : 34) : 10, y: focused ? (tv ? 26 : 18) : 6)
            // Only the picture grows; the name underneath stays full size and just moves down out of its way,
            // so it never runs past the bottom of the row
            .scaleEffect(grow)
            .zIndex(1)
            if showsLabels {
                VStack(spacing: 4) {
                    Text(tile.title).font(.system(size: 18, weight: .semibold, design: .rounded)).lineLimit(1).frame(width: width * grow)
                    Text(tile.subtitle.isEmpty ? " " : tile.subtitle).font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(focused ? 0.8 : 0.5)).lineLimit(1).minimumScaleFactor(0.8).frame(width: width * grow)
                }
                .offset(y: height * (grow - 1) / 2)
            }
        }
        .foregroundStyle(Color.white)
        .offset(y: moving ? -12 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: focused)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: tile.small ? 14 : 26, style: .continuous) }
    private var width: CGFloat { isWidget ? 320 : (tile.wide ? 560 : (tile.small ? (tile.title.count > 1 ? 110 : 72) : 190)) }
    private var height: CGFloat { tile.small ? 72 : 170 }
    private var isNowPlaying: Bool { tile.id.hasSuffix("now.card") }

    @ViewBuilder private var content: some View {
        if let w = tile.widget, let k = BigWidget(rawValue: w) {
            WidgetTileView(kind: k)
        } else if tile.small {
            Text(tile.title).font(.system(size: tile.title.count > 1 ? 20 : 30, weight: .bold, design: .rounded))
        } else if tile.wide {
            HStack(spacing: 22) {
                if let img = tile.icon {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: 118, height: 118)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                } else if let sym = tile.symbol {
                    Image(systemName: sym).font(.system(size: 44, weight: .semibold)).frame(width: 70)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if isNowPlaying {
                        HStack(spacing: 6) {
                            if playing { EqualizerBars().frame(width: 18, height: 13) }
                            Text(playing ? "NOW PLAYING" : "PAUSED").font(.system(size: 13, weight: .heavy)).tracking(0.8)
                        }
                        .foregroundStyle(Color.white.opacity(0.75))
                    }
                    // Long song and artist names shrink a little and wrap, rather than being cut off
                    Text(tile.title).font(.system(size: 26, weight: .bold, design: .rounded))
                        .lineLimit(2).minimumScaleFactor(0.7)
                    if !tile.subtitle.isEmpty {
                        Text(tile.subtitle).font(.system(size: 17)).foregroundStyle(Color.white.opacity(0.75))
                            .lineLimit(2).minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: height - 28, alignment: .leading)   // always fits inside the card
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 26)
        } else if let art = tile.art {
            // Album art and posters from Apple's catalogue, kept once loaded so refreshing the screen
            // doesn't start them again; the symbol shows while it loads
            PosterImage(url: art, symbol: tile.symbol ?? "photo")
                .frame(width: width, height: height)
        } else if let img = tile.icon {
            Image(nsImage: img).resizable().frame(width: 104, height: 104)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        } else if let sym = tile.symbol {
            Image(systemName: sym).font(.system(size: 56, weight: .semibold))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        } else {
            Text(String(tile.title.prefix(1))).font(.system(size: 78, weight: .black, design: .rounded))
        }
    }
}

/// Three little bouncing bars, shown while music is playing
struct EqualizerBars: View {
    private static let heights: [[CGFloat]] = [[13, 6, 10], [5, 12, 7], [9, 4, 13], [6, 13, 5]]
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 0.32)) { ctx in
            let step = Int(ctx.date.timeIntervalSinceReferenceDate / 0.32) % Self.heights.count
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().frame(width: 4, height: Self.heights[step][i])
                }
            }
            .animation(.easeInOut(duration: 0.3), value: step)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

/// A tile's hold-click menu (Play next, Add to playlist, Move…), styled like Apple TV:
/// the chosen row is solid white with dark text
struct BigMenuView: View {
    let menu: BigMenuState

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    if menu.stack.count > 1 { Image(systemName: "chevron.left").opacity(0.6) }
                    Text(menu.title).font(.system(size: 26, weight: .heavy, design: .rounded)).lineLimit(1)
                }
                .padding(.bottom, 10).padding(.horizontal, 6)
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(menu.items.enumerated()), id: \.element.id) { i, item in
                                let on = i == menu.index
                                HStack(spacing: 16) {
                                    Image(systemName: item.symbol).font(.system(size: 20, weight: .semibold)).frame(width: 30)
                                    Text(item.title).font(.system(size: 21, weight: .semibold, design: .rounded)).lineLimit(1)
                                    Spacer()
                                }
                                .foregroundStyle(on ? Color.black : Color.white)
                                .padding(.horizontal, 18).padding(.vertical, 13)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? Color.white : Color.white.opacity(0.0001)))
                                .scaleEffect(on ? 1.03 : 1)
                                .shadow(color: on ? Color.black.opacity(0.3) : .clear, radius: 10, y: 4)
                                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: on)
                                .id(item.id)
                            }
                        }
                        .padding(4)
                    }
                    .frame(maxHeight: 520)
                    .onChange(of: menu.index) { i in
                        guard menu.items.indices.contains(i) else { return }
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(menu.items[i].id, anchor: .center) }
                    }
                }
                Text("Swipe ↑↓ · click or swipe → to choose · Menu or swipe ← to go back")
                    .font(.system(size: 14)).foregroundStyle(Color.white.opacity(0.55)).padding(.top, 10).padding(.horizontal, 6)
            }
            .padding(26)
            .frame(width: 540)
            .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(BigStyle.panel.opacity(0.97)))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(BigStyle.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 50, y: 20)
        }
        .foregroundStyle(Color.white)
    }
}

/// The A–Z strip for jumping through long lists
struct JumpStripView: View {
    let jump: JumpState

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                Text("Jump to").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.white.opacity(0.7))
                HStack(spacing: 6) {
                    ForEach(Array(jump.letters.enumerated()), id: \.offset) { i, l in
                        let on = i == jump.index
                        Text(l)
                            .font(.system(size: on ? 34 : 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(on ? Color.black : Color.white)
                            .frame(minWidth: 36, minHeight: 52)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Color.white : Color.clear))
                            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: on)
                    }
                }
                Text("Swipe ← → to pick a letter, click to jump, Menu to close · or type a letter")
                    .font(.system(size: 14)).foregroundStyle(Color.white.opacity(0.6))
            }
            .padding(.horizontal, 30).padding(.vertical, 20)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(BigStyle.panel.opacity(0.97)))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(BigStyle.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 30)
            .padding(.bottom, 110)
        }
        .foregroundStyle(Color.white)
    }
}

/// Loads a picture from the web once and remembers it, so the Big Screen redrawing doesn't restart it.
final class PosterCache: ObservableObject {
    static let shared = PosterCache()
    private var images: [URL: NSImage] = [:]
    private var loading: Set<URL> = []
    @Published private(set) var version = 0

    func image(_ url: URL) -> NSImage? {
        if let img = images[url] { return img }
        guard !loading.contains(url) else { return nil }
        loading.insert(url)
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 20)) { [weak self] data, _, _ in
            let img = data.flatMap { NSImage(data: $0) }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loading.remove(url)
                if let img = img { self.images[url] = img; self.version += 1 }
            }
        }.resume()
        return nil
    }
}

struct PosterImage: View {
    let url: URL
    let symbol: String
    @ObservedObject private var cache = PosterCache.shared

    var body: some View {
        let _ = cache.version
        if let img = cache.image(url) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
        } else {
            Image(systemName: symbol).font(.system(size: 56, weight: .semibold))
        }
    }
}
