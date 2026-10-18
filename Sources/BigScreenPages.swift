// BigScreenPages.swift — the pages inside Big Screen: Apple Music, TV, Search, Files
import AppKit
import SwiftUI

extension BigScreen {
    static let musicPink = Color(red: 0.98, green: 0.24, blue: 0.36)
    static let tvBlue = Color(red: 0.16, green: 0.36, blue: 0.86)
    static let searchTeal = Color(red: 0.08, green: 0.55, blue: 0.60)

    func homePage() -> BigPage {
        BigPage(id: "home", title: "") { [weak self] in self?.buildRows() ?? [] }
    }

    // MARK: Home: Browse row

    func browseRow() -> BigRow {
        var tiles: [BigTile] = []
        if MediaLibrary.installed("com.apple.Music") {
            tiles.append(BigTile.page("b.music", "Apple Music", subtitle: "Home, New, Radio, Library", icon: appIcon("com.apple.Music"),
                               tint: Self.musicPink) { [unowned self] in self.musicPage() })
        }
        if MediaLibrary.installed("com.apple.TV") {
            tiles.append(BigTile.page("b.tv", "TV", subtitle: "Movies, shows, your library", icon: appIcon("com.apple.TV"),
                               tint: Self.tvBlue) { [unowned self] in self.tvPage() })
        }
        tiles.append(BigTile.page("b.search", "Search", subtitle: "Songs, movies, shows, podcasts", symbol: "magnifyingglass",
                           tint: Self.searchTeal) { [unowned self] in self.searchPage(.all) })
        if let podcasts = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.podcasts") {
            tiles.append(BigTile(id: "b.podcasts", title: "Podcasts", icon: appIcon("com.apple.podcasts"), closes: true, run: {
                NSWorkspace.shared.openApplication(at: podcasts, configuration: NSWorkspace.OpenConfiguration()); return nil
            }))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        tiles.append(BigTile.page("b.movies", "Movies folder", subtitle: "Your video files", symbol: "film.stack",
                           tint: Color(red: 0.45, green: 0.30, blue: 0.20)) { [unowned self] in
            self.filesPage(home.appendingPathComponent("Movies"))
        })
        tiles.append(BigTile.page("b.files", "Files", subtitle: "Your Home folder", symbol: "folder.fill",
                           tint: Color(red: 0.25, green: 0.45, blue: 0.75)) { [unowned self] in self.filesPage(home) })
        return BigRow(id: "browse", title: "Browse", tiles: tiles)
    }

    // MARK: Shared helpers

    /// A one-tile row explaining a loading or error state (with a fix-it action for permissions).
    func statusRow<T>(_ id: String, _ title: String, _ load: Load<T>, app: String, retry: @escaping () -> Void) -> BigRow? {
        switch load {
        case .idle, .loading:
            return BigRow(id: id, title: title, tiles: [BigTile(id: id + ".wait", title: "Loading…", symbol: "hourglass", tint: Color(white: 0.25))])
        case .failed(let e):
            if e.notAllowed {
                return BigRow(id: id, title: title, tiles: [BigTile(id: id + ".perm", title: "Allow access to \(app)",
                    subtitle: "Click to open Privacy settings", symbol: "lock.open.fill", tint: .orange, closes: true, run: {
                        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"); return nil
                    })])
            }
            return BigRow(id: id, title: title, tiles: [BigTile(id: id + ".err", title: "Couldn’t load · click to try again", subtitle: e.short,
                                                              symbol: "arrow.clockwise", tint: Color(white: 0.3), run: { retry(); return nil })])
        case .done:
            return nil
        }
    }

    /// Splits a long list into one row per starting letter (A, B, C… #) so it's quick to jump through.
    func letterRows(_ items: [LibItem], id: String, make: (LibItem, Int) -> BigTile) -> [BigRow] {
        var groups: [String: [(LibItem, Int)]] = [:]
        for (i, it) in items.enumerated() {
            var k = String(it.title.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
            if !(k.first?.isLetter ?? false) { k = "#" }
            groups[k, default: []].append((it, i))
        }
        let keys = groups.keys.sorted { a, b in a == "#" ? false : (b == "#" ? true : a < b) }
        return keys.map { k in BigRow(id: "\(id).\(k)", title: k, tiles: groups[k]!.map { make($0.0, $0.1) }) }
    }

    /// Splits a list into rows of a fixed size (for playlists and albums, which keep their order).
    func chunkRows(_ tiles: [BigTile], id: String, title: String, size: Int = 12) -> [BigRow] {
        stride(from: 0, to: tiles.count, by: size).map { start in
            let end = min(start + size, tiles.count)
            return BigRow(id: "\(id).\(start)", title: start == 0 ? title : "\(start + 1)–\(end)", tiles: Array(tiles[start..<end]))
        }
    }

    func tint(for s: String) -> Color {
        let h = abs(s.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) })
        return Self.palette[h % Self.palette.count].opacity(0.85)
    }

    func songTile(_ it: LibItem, _ i: Int, idPrefix: String, playlistID: String? = nil) -> BigTile {
        var t = BigTile(id: "\(idPrefix).\(i).\(it.id)", title: it.title, subtitle: it.subtitle, symbol: "music.note",
                        tint: tint(for: it.subtitle + it.title), run: {
            MediaLibrary.play(app: "Music", trackID: it.id, inPlaylist: playlistID)
            return "Playing \(it.title)"
        })
        t.menu = { [unowned self] in self.songMenu(it, playlistID: playlistID) }
        return t
    }

    /// Hold-click menu for a song in your library
    func songMenu(_ it: LibItem, playlistID: String? = nil) -> [BigMenuItem] {
        let lib = MediaLibrary.shared
        lib.ensureMusicPlaylists()          // so "Add to playlist" is ready by the time you get there
        return [
            BigMenuItem(title: "Play now", symbol: "play.fill") {
                MediaLibrary.play(app: "Music", trackID: it.id, inPlaylist: playlistID); return .done("Playing \(it.title)")
            },
            BigMenuItem(title: "Play next", symbol: "text.insert") { .done(UpNext.shared.playNext(it)) },
            BigMenuItem(title: "Play later", symbol: "text.append") { .done(UpNext.shared.playLater(it)) },
            BigMenuItem(title: "Add to playlist…", symbol: "music.note.list") { [unowned self] in
                guard case .done(let pls) = lib.musicPlaylists else {
                    lib.ensureMusicPlaylists()
                    return .submenu("Add to playlist", [BigMenuItem(title: "Still loading your playlists… go back and try again", symbol: "hourglass") { .done(nil) }])
                }
                return .submenu("Add to playlist", pls.map { p in
                    BigMenuItem(title: p.title, symbol: "music.note.list") { [unowned self] in
                        MusicExtras.add(it.id, toPlaylist: p.id) { ok in
                            self.showToast(ok ? "Added to \(p.title)" : "Couldn't add to \(p.title)")
                        }
                        return .done(nil)
                    }
                })
            },
            BigMenuItem(title: "Love", symbol: "heart.fill") { [unowned self] in
                MusicExtras.love(it.id) { ok in self.showToast(ok ? "Loved \(it.title)" : "Couldn't love this song") }
                return .done(nil)
            },
            BigMenuItem(title: "Go to artist", symbol: "music.mic") { [unowned self] in
                MusicExtras.info(it.id) { artist, _ in
                    let name = artist.isEmpty ? it.subtitle : artist
                    guard !name.isEmpty else { self.showToast("No artist for this song"); return }
                    self.push(self.trackListPage(key: "artist:\(name)", title: name))
                }
                return .done(nil)
            },
            BigMenuItem(title: "Go to album", symbol: "square.stack.fill") { [unowned self] in
                MusicExtras.info(it.id) { _, album in
                    guard !album.isEmpty else { self.showToast("No album for this song"); return }
                    self.push(self.trackListPage(key: "album:\(album)", title: album))
                }
                return .done(nil)
            },
        ]
    }

    /// Hold-click menu for an Apple Music catalogue result (not in your library)
    func catalogMenu(_ it: CatalogItem, bundleID: String) -> [BigMenuItem] {
        var items: [BigMenuItem] = []
        if let u = it.url {
            items.append(BigMenuItem(title: "Open", symbol: "arrow.up.forward.app") { Catalog.open(u, inApp: bundleID); return .closeScreen })
            items.append(BigMenuItem(title: "Copy link", symbol: "link") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(u.absoluteString, forType: .string)
                return .done("Link copied")
            })
        }
        if !it.subtitle.isEmpty {
            items.append(BigMenuItem(title: "Search for \(it.subtitle)", symbol: "magnifyingglass") {
                SearchStore.shared.set(it.subtitle); return .done(nil)
            })
        }
        return items
    }

    // MARK: Apple Music

    func musicPage() -> BigPage {
        let lib = MediaLibrary.shared
        return BigPage(id: "music", title: "Apple Music") { [unowned self] in
            var rows: [BigRow] = []
            let music = MusicWatcher.shared
            if music.app == "Music" {
                rows.append(BigRow(id: "m.now", title: music.playing ? "Now Playing" : "Paused", tiles: [
                    BigTile(id: "m.now.card", title: music.track.isEmpty ? "Music" : music.track, subtitle: music.artist,
                            icon: appIcon("com.apple.Music"), tint: Self.musicPink, wide: true, run: { music.playPause(); return nil }),
                    BigTile(id: "m.now.prev", title: "Previous", symbol: "backward.fill", tint: Self.musicPink.opacity(0.7),
                            run: { music.skip(forward: false); return nil }),
                    BigTile(id: "m.now.play", title: music.playing ? "Pause" : "Play", symbol: music.playing ? "pause.fill" : "play.fill",
                            tint: Self.musicPink.opacity(0.7), run: { music.playPause(); return nil }),
                    BigTile(id: "m.now.next", title: "Next", symbol: "forward.fill", tint: Self.musicPink.opacity(0.7),
                            run: { music.skip(forward: true); return nil }),
                ]))
            }
            // Apple Music sections open in the Music app (they need the app's own screens)
            let sections: [(String, String, String, String)] = [
                ("Home", "house.fill", "listen-now", "Picks for you"), ("New", "sparkles", "new", "New releases"),
                ("Radio", "dot.radiowaves.left.and.right", "radio", "Live radio & stations"),
                ("Charts", "chart.bar.fill", "charts", "Top songs"),
            ]
            var apple: [BigTile] = sections.map { name, sym, path, sub in
                BigTile(id: "m.am.\(path)", title: name, subtitle: sub, symbol: sym, tint: Self.musicPink, closes: true, run: {
                    if let u = Catalog.musicSection(path) { Catalog.open(u, inApp: "com.apple.Music") }
                    return nil
                })
            }
            apple.insert(BigTile.page("m.search", "Search", subtitle: "Library + Apple Music", symbol: "magnifyingglass",
                               tint: Self.searchTeal) { [unowned self] in self.searchPage(.music) }, at: 0)
            rows.append(BigRow(id: "m.apple", title: "Apple Music", tiles: apple))

            // Up Next: Couch Remote's own queue, played before Music's next song
            let queue = UpNext.shared.items
            if !queue.isEmpty {
                var qTiles: [BigTile] = queue.enumerated().map { i, it -> BigTile in
                    var t = BigTile(id: "q.\(it.id)", title: it.title, subtitle: i == 0 ? "Next · \(it.subtitle)" : it.subtitle,
                                    symbol: "music.note", tint: self.tint(for: it.subtitle + it.title),
                                    run: { UpNext.shared.playNow(it.id); return "Playing \(it.title)" })
                    t.menu = {
                        [BigMenuItem(title: "Play now", symbol: "play.fill") { UpNext.shared.playNow(it.id); return .done("Playing \(it.title)") },
                         BigMenuItem(title: "Remove from Up Next", symbol: "minus.circle") { UpNext.shared.remove(it.id); return .done("Removed") }]
                    }
                    return t
                }
                qTiles.append(BigTile(id: "q.clear", title: "Clear Up Next", symbol: "xmark.circle", tint: Color(white: 0.3),
                                      run: { UpNext.shared.clear(); return "Up Next cleared" }))
                rows.append(BigRow(id: "m.upnext", title: "Up Next", tiles: qTiles, reorder: { ids in
                    UpNext.shared.reorder(ids.filter { $0.hasPrefix("q.") && $0 != "q.clear" }.map { String($0.dropFirst(2)) })
                }))
            }

            // Recently played / added
            if ConfigStore.shared.settings.recentRows {
                let extras = MusicExtras.shared
                extras.ensureRecent()
                if let s = self.statusRow("m.recent", "Recently played", extras.recentlyPlayed, app: "Music", retry: { extras.ensureRecent() }) {
                    rows.append(s)
                } else {
                    if case .done(let played) = extras.recentlyPlayed, !played.isEmpty {
                        rows.append(BigRow(id: "m.recent", title: "Recently played",
                                           tiles: played.enumerated().map { self.songTile($1, $0, idPrefix: "rp") }))
                    }
                    if case .done(let added) = extras.recentlyAdded, !added.isEmpty {
                        rows.append(BigRow(id: "m.added", title: "Recently added",
                                           tiles: added.enumerated().map { self.songTile($1, $0, idPrefix: "ra") }))
                    }
                }
            }

            rows.append(BigRow(id: "m.lib", title: "Library", tiles: [
                BigTile.page("m.playlists", "Playlists", symbol: "music.note.list", tint: Color(red: 0.55, green: 0.25, blue: 0.75)) { [unowned self] in self.playlistsPage() },
                BigTile.page("m.artists", "Artists", symbol: "music.mic", tint: Color(red: 0.85, green: 0.35, blue: 0.25)) { [unowned self] in self.artistsPage() },
                BigTile.page("m.albums", "Albums", symbol: "square.stack.fill", tint: Color(red: 0.20, green: 0.55, blue: 0.85)) { [unowned self] in self.albumsPage() },
                BigTile.page("m.songs", "Songs", symbol: "music.note", tint: Color(red: 0.15, green: 0.60, blue: 0.45)) { [unowned self] in self.songsPage() },
                BigTile(id: "m.shuffle", title: "Shuffle all", subtitle: "Your whole library", symbol: "shuffle",
                        tint: Self.musicPink.opacity(0.8), run: { MediaLibrary.shuffleLibrary(); return "Shuffling your library" }),
                BigTile(id: "m.refresh", title: "Refresh", subtitle: "Reload your library", symbol: "arrow.clockwise",
                        tint: Color(white: 0.3), run: { lib.refreshAll(); return "Reloading library" }),
            ]))

            // Sound
            let eqName = MusicExtras.shared.eqCurrent
            rows.append(BigRow(id: "m.sound", title: "Sound", tiles: [
                BigTile.page("m.eq", "Equaliser", subtitle: eqName ?? "Off", symbol: "slider.vertical.3",
                             tint: Color(red: 0.35, green: 0.30, blue: 0.70)) { [unowned self] in self.eqPage() },
                BigTile(id: "m.eq.off", title: "EQ off", symbol: "speaker.wave.2", tint: Color(white: 0.3),
                        run: { MusicExtras.shared.setEQ(nil); return "Equaliser off" }),
            ]))

            // Quick look at the playlists right here
            lib.ensureMusicPlaylists()
            if let s = self.statusRow("m.pl", "Your playlists", lib.musicPlaylists, app: "Music", retry: { lib.refreshAll() }) {
                rows.append(s)
            } else if case .done(let pls) = lib.musicPlaylists, !pls.isEmpty {
                rows.append(BigRow(id: "m.pl", title: "Your playlists", tiles: pls.prefix(30).enumerated().map { i, p in
                    self.playlistTile(p, id: "m.pl.\(i).\(p.id)")
                }))
            }
            return rows
        }
    }

    /// The Music app's equaliser presets
    func eqPage() -> BigPage {
        let extras = MusicExtras.shared
        return BigPage(id: "m.eqpage", title: "Equaliser") { [unowned self] in
            extras.ensureEQ()
            if let s = self.statusRow("eq", "Presets", extras.eqPresets, app: "Music", retry: { extras.ensureEQ(force: true) }) { return [s] }
            guard case .done(let presets) = extras.eqPresets else { return [] }
            let current = extras.eqCurrent
            var tiles = [BigTile(id: "eq.off", title: "Off", subtitle: current == nil ? "On now" : "", symbol: "speaker.wave.2",
                                 tint: current == nil ? Self.musicPink : Color(white: 0.3),
                                 run: { extras.setEQ(nil); return "Equaliser off" })]
            tiles += presets.enumerated().map { i, name in
                BigTile(id: "eq.\(i)", title: name, subtitle: current == name ? "On now" : "", symbol: "slider.vertical.3",
                        tint: current == name ? Self.musicPink : self.tint(for: name),
                        run: { extras.setEQ(name); return "EQ: \(name)" })
            }
            return self.chunkRows(tiles, id: "eq", title: "Presets", size: 8)
        }
    }

    /// A playlist tile: click to open it, hold-click to play or shuffle straight away
    func playlistTile(_ p: LibItem, id: String) -> BigTile {
        var t = BigTile.page(id, p.title, subtitle: p.subtitle, symbol: "music.note.list", tint: tint(for: p.title)) { [unowned self] in
            self.playlistPage(p)
        }
        t.menu = {
            [BigMenuItem(title: "Play", symbol: "play.fill") { MediaLibrary.playPlaylist(p.id, shuffle: false); return .done("Playing \(p.title)") },
             BigMenuItem(title: "Shuffle", symbol: "shuffle") { MediaLibrary.playPlaylist(p.id, shuffle: true); return .done("Shuffling \(p.title)") }]
        }
        return t
    }

    func playlistsPage() -> BigPage {
        let lib = MediaLibrary.shared
        return BigPage(id: "m.playlists", title: "Playlists") { [unowned self] in
            lib.ensureMusicPlaylists()
            if let s = self.statusRow("pl", "Playlists", lib.musicPlaylists, app: "Music", retry: { lib.refreshAll() }) { return [s] }
            guard case .done(let pls) = lib.musicPlaylists else { return [] }
            let tiles = pls.enumerated().map { i, p in
                self.playlistTile(p, id: "pl.\(i).\(p.id)")
            }
            return tiles.isEmpty ? [BigRow(id: "pl.none", title: "Playlists", tiles: [BigTile(id: "pl.none.t", title: "No playlists yet", symbol: "music.note.list")])]
                                 : self.chunkRows(tiles, id: "pl", title: "Your playlists", size: 10)
        }
    }

    func playlistPage(_ p: LibItem) -> BigPage {
        let lib = MediaLibrary.shared
        let key = "playlist:\(p.id)"
        return BigPage(id: key, title: p.title) { [unowned self] in
            var rows = [BigRow(id: "plp.actions", title: p.subtitle, tiles: [
                BigTile(id: "plp.play", title: "Play", symbol: "play.fill", tint: Self.musicPink,
                        run: { MediaLibrary.playPlaylist(p.id, shuffle: false); return "Playing \(p.title)" }),
                BigTile(id: "plp.shuffle", title: "Shuffle", symbol: "shuffle", tint: Self.musicPink.opacity(0.8),
                        run: { MediaLibrary.playPlaylist(p.id, shuffle: true); return "Shuffling \(p.title)" }),
            ])]
            lib.ensureList(key)
            if let s = self.statusRow("plp.s", "Songs", lib.list(key), app: "Music", retry: { lib.refreshAll() }) { rows.append(s) }
            else if case .done(let songs) = lib.list(key) {
                rows += self.chunkRows(songs.enumerated().map { self.songTile($1, $0, idPrefix: "plp", playlistID: p.id) }, id: "plp", title: "Songs")
            }
            return rows
        }
    }

    func songsPage() -> BigPage {
        let lib = MediaLibrary.shared
        return BigPage(id: "m.songs", title: "Songs") { [unowned self] in
            lib.ensureMusicSongs()
            if let s = self.statusRow("songs", "Songs", lib.musicSongs, app: "Music", retry: { lib.refreshAll() }) { return [s] }
            guard case .done(let songs) = lib.musicSongs else { return [] }
            return self.letterRows(songs, id: "songs") { self.songTile($0, $1, idPrefix: "songs") }
        }
    }

    func artistsPage() -> BigPage {
        let lib = MediaLibrary.shared
        return BigPage(id: "m.artists", title: "Artists") { [unowned self] in
            lib.ensureMusicArtistsAndAlbums()
            if let s = self.statusRow("artists", "Artists", lib.musicArtists, app: "Music", retry: { lib.refreshAll() }) { return [s] }
            guard case .done(let artists) = lib.musicArtists else { return [] }
            return self.letterRows(artists, id: "artists") { a, i in
                BigTile.page("artists.\(i)", a.title, subtitle: a.subtitle, symbol: "music.mic", tint: self.tint(for: a.title)) { [unowned self] in
                    self.trackListPage(key: "artist:\(a.id)", title: a.title)
                }
            }
        }
    }

    func albumsPage() -> BigPage {
        let lib = MediaLibrary.shared
        return BigPage(id: "m.albums", title: "Albums") { [unowned self] in
            lib.ensureMusicArtistsAndAlbums()
            if let s = self.statusRow("albums", "Albums", lib.musicAlbums, app: "Music", retry: { lib.refreshAll() }) { return [s] }
            guard case .done(let albums) = lib.musicAlbums else { return [] }
            return self.letterRows(albums, id: "albums") { a, i in
                BigTile.page("albums.\(i)", a.title, subtitle: a.subtitle, symbol: "square.stack.fill", tint: self.tint(for: a.title)) { [unowned self] in
                    self.trackListPage(key: "album:\(a.id)", title: a.title)
                }
            }
        }
    }

    /// Songs by an artist or on an album
    func trackListPage(key: String, title: String) -> BigPage {
        let lib = MediaLibrary.shared
        return BigPage(id: key, title: title) { [unowned self] in
            lib.ensureList(key)
            if let s = self.statusRow("tl", "Songs", lib.list(key), app: "Music", retry: { lib.refreshAll() }) { return [s] }
            guard case .done(let songs) = lib.list(key) else { return [] }
            return self.chunkRows(songs.enumerated().map { self.songTile($1, $0, idPrefix: "tl") }, id: "tl", title: "Songs")
        }
    }

    // MARK: TV

    func tvTile(_ it: LibItem, _ i: Int, prefix: String) -> BigTile {
        BigTile(id: "\(prefix).\(i).\(it.id)", title: it.title, subtitle: it.subtitle.isEmpty ? "Movie" : it.subtitle,
                symbol: it.subtitle.isEmpty ? "film.fill" : "tv.fill", tint: tint(for: it.title), closes: true, run: {
            Script.run("""
            tell application "TV"
                activate
                play (first track of library playlist 1 whose persistent ID is \(Script.quote(it.id)))
            end tell
            """) { _ in }
            return nil
        })
    }

    func tvPage() -> BigPage {
        let lib = MediaLibrary.shared
        return BigPage(id: "tv", title: "TV") { [unowned self] in
            var rows: [BigRow] = []
            let store: [(String, String, String, String)] = [
                ("Watch Now", "play.tv.fill", "https://tv.apple.com", "Up next & picks"),
                ("Apple TV+", "appletv.fill", "https://tv.apple.com/channel/tvs.sbd.4000", "Apple Originals"),
                ("Store", "bag.fill", "https://tv.apple.com/store", "Buy or rent movies"),
            ]
            var top: [BigTile] = [.page("tv.search", "Search", subtitle: "Movies & shows", symbol: "magnifyingglass",
                                        tint: Self.searchTeal) { [unowned self] in self.searchPage(.tv) }]
            top += store.map { name, sym, url, sub in
                BigTile(id: "tv.s.\(name)", title: name, subtitle: sub, symbol: sym, tint: Self.tvBlue, closes: true, run: {
                    if let u = URL(string: url) { Catalog.open(u, inApp: "com.apple.TV") }
                    return nil
                })
            }
            rows.append(BigRow(id: "tv.top", title: "Apple TV", tiles: top))

            lib.ensureTV()
            if let s = self.statusRow("tv.lib", "Your library", lib.tvItems, app: "TV", retry: { lib.refreshAll() }) {
                rows.append(s); return rows
            }
            guard case .done(let items) = lib.tvItems else { return rows }
            let movies = items.filter { $0.subtitle.isEmpty }
            var shows: [String: Int] = [:]
            for it in items where !it.subtitle.isEmpty { shows[it.subtitle, default: 0] += 1 }
            if !movies.isEmpty {
                rows += self.chunkRows(movies.enumerated().map { self.tvTile($1, $0, prefix: "tv.m") }, id: "tv.movies", title: "Your movies")
            }
            if !shows.isEmpty {
                let showTiles = shows.keys.sorted().enumerated().map { i, name in
                    BigTile.page("tv.show.\(i)", name, subtitle: "\(shows[name] ?? 0) episodes", symbol: "tv.fill", tint: self.tint(for: name)) { [unowned self] in
                        self.showPage(name)
                    }
                }
                rows += self.chunkRows(showTiles, id: "tv.shows", title: "Your TV shows")
            }
            if movies.isEmpty && shows.isEmpty {
                rows.append(BigRow(id: "tv.empty", title: "Your library", tiles: [BigTile(id: "tv.empty.t", title: "Nothing downloaded or bought yet",
                    subtitle: "Use Search or Watch Now", symbol: "tray", tint: Color(white: 0.25))]))
            }
            return rows
        }
    }

    func showPage(_ name: String) -> BigPage {
        let lib = MediaLibrary.shared
        let key = "tvshow:\(name)"
        return BigPage(id: key, title: name) { [unowned self] in
            lib.ensureList(key)
            if let s = self.statusRow("ep", "Episodes", lib.list(key), app: "TV", retry: { lib.refreshAll() }) { return [s] }
            guard case .done(let eps) = lib.list(key) else { return [] }
            return self.chunkRows(eps.enumerated().map { i, e -> BigTile in
                var t = self.tvTile(LibItem(id: e.id, title: e.title, subtitle: name), i, prefix: "ep")
                t.symbol = "play.rectangle.fill"
                return t
            }, id: "ep", title: "Episodes")
        }
    }

    // MARK: Search

    func searchPage(_ scope: SearchScope) -> BigPage {
        let search = SearchStore.shared
        let title: String
        switch scope {
        case .all: title = "Search"
        case .music: title = "Search music"
        case .tv: title = "Search movies & shows"
        case .podcasts: title = "Search podcasts"
        }
        DispatchQueue.main.async { search.begin(scope) }
        return BigPage(id: "search.\(scope.rawValue)", title: title, isSearch: true) { [unowned self] in
            var rows: [BigRow] = []
            let q = search.query
            // the search box
            rows.append(BigRow(id: "s.box", title: "", tiles: [
                BigTile(id: "s.query", title: q.isEmpty ? "Type with the keys below" : q + "▏",
                        subtitle: q.isEmpty ? "or use your keyboard" : "Results update as you type",
                        symbol: "magnifyingglass", tint: Self.searchTeal, wide: true),
                { () -> BigTile in var t = BigTile(id: "s.del", title: "⌫", tint: Color(white: 0.3), run: { search.backspace(); return nil }); t.small = true; return t }(),
                { () -> BigTile in var t = BigTile(id: "s.space", title: "space", tint: Color(white: 0.3), run: { search.type(" "); return nil }); t.small = true; return t }(),
                { () -> BigTile in var t = BigTile(id: "s.clear", title: "clear", tint: Color(white: 0.3), run: { search.clear(); return nil }); t.small = true; return t }(),
            ]))
            // on-screen keys (swipe to a letter, click to type)
            for (r, keys) in ["abcdefghij", "klmnopqrst", "uvwxyz'-.&", "1234567890"].enumerated() {
                rows.append(BigRow(id: "s.k\(r)", title: "", tiles: keys.map { ch -> BigTile in
                    var t = BigTile(id: "s.k\(r).\(ch)", title: String(ch), tint: Color(white: 0.22), run: {
                        search.type(String(ch)); return nil
                    })
                    t.small = true
                    return t
                }))
            }
            // Recent searches (empty box) or suggestions (while typing), placed below the keys so the keys never move
            if q.trimmingCharacters(in: .whitespaces).isEmpty {
                let recent = search.recent
                if !recent.isEmpty {
                    var tiles: [BigTile] = recent.enumerated().map { i, r in
                        BigTile(id: "s.r.\(i)", title: r, symbol: "clock.arrow.circlepath", tint: Color(white: 0.24),
                                run: { search.set(r); return nil })
                    }
                    tiles.append(BigTile(id: "s.r.clear", title: "Clear history", symbol: "xmark.circle", tint: Color(white: 0.3),
                                         run: { search.forgetRecent(); return "Search history cleared" }))
                    rows.append(BigRow(id: "s.recent", title: "Recent searches", tiles: tiles))
                }
            } else {
                let sug = search.suggestions
                if !sug.isEmpty {
                    rows.append(BigRow(id: "s.sug", title: "Suggestions", tiles: sug.enumerated().map { i, sgt in
                        BigTile(id: "s.g.\(i).\(sgt)", title: sgt, symbol: "magnifyingglass", tint: Self.searchTeal.opacity(0.7),
                                run: { search.set(sgt); return nil })
                    }))
                }
            }
            if q.trimmingCharacters(in: .whitespaces).count >= 2 { rows += self.searchResultRows(q) }
            return rows
        }
    }

    private func searchResultRows(_ q: String) -> [BigRow] {
        let search = SearchStore.shared
        var rows: [BigRow] = []

        func libRow(_ id: String, _ title: String, app: String, make: @escaping (LibItem, Int) -> BigTile) {
            let l = search.lib(id)
            if case .idle = l { return }
            if let s = statusRow(id, title, l, app: app, retry: { search.begin(.all) }) { rows.append(s); return }
            if case .done(let items) = l, !items.isEmpty { rows.append(BigRow(id: id, title: title, tiles: items.enumerated().map { make($1, $0) })) }
        }
        func catRow(_ id: String, _ title: String, bundleID: String, symbol: String) {
            let l = search.cat(id)
            if case .idle = l { return }
            if case .loading = l {
                rows.append(BigRow(id: id, title: title, tiles: [BigTile(id: id + ".wait", title: "Searching…", symbol: "hourglass", tint: Color(white: 0.25))]))
                return
            }
            if case .failed(let e) = l {
                // Say so instead of leaving the row out, so it doesn't look like nothing exists
                rows.append(BigRow(id: id, title: title, tiles: [BigTile(id: id + ".err", title: "Couldn’t reach Apple · click to try again",
                    subtitle: e.message, symbol: "wifi.exclamationmark", tint: Color(white: 0.3), run: { search.begin(search.scope); return nil })]))
                return
            }
            guard case .done(let items) = l, !items.isEmpty else { return }
            rows.append(BigRow(id: id, title: title, tiles: items.enumerated().map { i, it -> BigTile in
                var t = BigTile(id: "\(id).\(i)", title: it.title, subtitle: it.subtitle, symbol: symbol, tint: tint(for: it.title),
                                closes: true, run: {
                    SearchStore.shared.remember()
                    if let u = it.url { Catalog.open(u, inApp: bundleID) }
                    return nil
                })
                t.art = it.art
                t.menu = { [unowned self] in self.catalogMenu(it, bundleID: bundleID) }
                return t
            }))
        }

        libRow("lib.music", "In your music library", app: "Music") { self.songTile($0, $1, idPrefix: "sr.m") }
        catRow("cat.songs", "Apple Music songs", bundleID: "com.apple.Music", symbol: "music.note")
        catRow("cat.albums", "Albums", bundleID: "com.apple.Music", symbol: "square.stack.fill")
        libRow("lib.tv", "In your TV library", app: "TV") { self.tvTile($0, $1, prefix: "sr.tv") }
        catRow("cat.movies", "Movies", bundleID: "com.apple.TV", symbol: "film.fill")
        catRow("cat.shows", "TV shows", bundleID: "com.apple.TV", symbol: "tv.fill")
        catRow("cat.podcasts", "Podcasts", bundleID: "com.apple.podcasts", symbol: "mic.fill")

        // Search the same words on your streaming services
        var elsewhere: [BigTile] = ConfigStore.shared.settings.bigScreenShortcuts.compactMap { sc in
            guard let u = sc.searchURL(q) else { return nil }
            return BigTile(id: "sr.web.\(sc.id)", title: sc.name, subtitle: "Search for “\(q)”", symbol: "magnifyingglass",
                           tint: tint(for: sc.name), closes: true, run: { NSWorkspace.shared.open(u); return nil })
        }
        if MediaLibrary.installed("com.spotify.client"),
           let enc = q.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), let u = URL(string: "spotify:search:\(enc)") {
            elsewhere.insert(BigTile(id: "sr.spotify", title: "Spotify", subtitle: "Search for “\(q)”", icon: appIcon("com.spotify.client"),
                                     closes: true, run: { NSWorkspace.shared.open(u); return nil }), at: 0)
        }
        if !elsewhere.isEmpty { rows.append(BigRow(id: "sr.web", title: "Search on…", tiles: elsewhere)) }
        return rows
    }

    // MARK: Files

    func filesPage(_ dir: URL) -> BigPage {
        BigPage(id: "files.\(dir.path)", title: dir.lastPathComponent) { [unowned self] in
            let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
            let urls = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? [])
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            if urls.isEmpty {
                return [BigRow(id: "f.empty", title: "", tiles: [BigTile(id: "f.empty.t", title: "This folder is empty", symbol: "tray", tint: Color(white: 0.25))])]
            }
            let video: Set<String> = ["mp4", "m4v", "mov", "mkv", "avi", "webm", "wmv", "mpg", "mpeg", "ts"]
            let tiles: [BigTile] = urls.prefix(600).enumerated().map { i, url -> BigTile in
                let v = try? url.resourceValues(forKeys: Set(keys))
                let isDir = (v?.isDirectory ?? false) && !(v?.isPackage ?? false)
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                if isDir {
                    return BigTile.page("f.\(i)", url.lastPathComponent, subtitle: "Folder", icon: icon, tint: Color(white: 0.22)) { [unowned self] in
                        self.filesPage(url)
                    }
                }
                let isVideo = video.contains(url.pathExtension.lowercased())
                return BigTile(id: "f.\(i)", title: url.lastPathComponent, subtitle: isVideo ? "Video" : url.pathExtension.uppercased(),
                               icon: icon, tint: Color(white: 0.22), closes: true, run: { NSWorkspace.shared.open(url); return nil })
            }
            return self.chunkRows(tiles, id: "f", title: "", size: 10)
        }
    }
}
