// MediaLibrary.swift — reads your Music and TV libraries (via AppleScript, in the background)
// and searches Apple's public catalogue (the free iTunes Search API, no account needed).
import AppKit

// MARK: - Background AppleScript

enum Script {
    // Several can run at once, so one slow app (TV opening, a big library) never holds up the rest
    private static let queue = DispatchQueue(label: "couchremote.script", qos: .userInitiated, attributes: .concurrent)

    /// Runs AppleScript with /usr/bin/osascript off the main thread, so the screen never freezes.
    /// If the app doesn't answer within `timeout` seconds (stuck on a welcome screen or a sign-in box),
    /// it gives up and reports that instead of loading forever.
    static func run(_ source: String, javaScript: Bool = false, timeout: TimeInterval = 15,
                    completion: @escaping (Result<String, ScriptError>) -> Void) {
        queue.async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = javaScript ? ["-l", "JavaScript", "-"] : ["-"]
            let input = Pipe(), output = Pipe(), errors = Pipe()
            p.standardInput = input; p.standardOutput = output; p.standardError = errors
            do { try p.run() } catch {
                DispatchQueue.main.async { completion(.failure(ScriptError(message: error.localizedDescription))) }
                return
            }
            var timedOut = false
            let killer = DispatchWorkItem { if p.isRunning { timedOut = true; p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
            input.fileHandleForWriting.write(source.data(using: .utf8) ?? Data())
            try? input.fileHandleForWriting.close()
            // Read errors alongside the output, so a lot of either can't jam the other
            var err = Data()
            let errDone = DispatchSemaphore(value: 0)
            DispatchQueue.global().async { err = errors.fileHandleForReading.readDataToEndOfFile(); errDone.signal() }
            let out = output.fileHandleForReading.readDataToEndOfFile()
            errDone.wait()
            p.waitUntilExit()
            killer.cancel()
            let text = String(data: out, encoding: .utf8) ?? ""
            let errText = timedOut ? ScriptError.timeoutMessage : (String(data: err, encoding: .utf8) ?? "")
            DispatchQueue.main.async {
                if p.terminationStatus == 0 && !timedOut { completion(.success(text.trimmingCharacters(in: .newlines))) }
                else { completion(.failure(ScriptError(message: errText))) }
            }
        }
    }

    /// Makes a value safe to put inside an AppleScript string.
    static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static let joinHandler = """
    on joinList(L)
        set AppleScript's text item delimiters to linefeed
        try
            set s to L as text
        on error
            set s to ""
            repeat with x in L
                try
                    set s to s & (x as text) & linefeed
                on error
                    set s to s & linefeed
                end try
            end repeat
        end try
        set AppleScript's text item delimiters to ""
        return s
    end joinList
    """
}

struct ScriptError: Error {
    var message: String
    static let timeoutMessage = "The app didn’t answer in time"
    var notAllowed: Bool { message.contains("-1743") || message.lowercased().contains("not authori") }
    var timedOut: Bool { message == Self.timeoutMessage }
    /// A short, readable reason to show on a tile
    var short: String {
        if timedOut { return "Open the app once, close any welcome screen, then try again" }
        if message.contains("-600") || message.contains("isn’t running") { return "The app isn’t open" }
        if message.contains("-1728") { return "The library couldn’t be read" }
        let line = message.split(separator: "\n").first.map(String.init) ?? ""
        // osascript errors look like “0:12: execution error: …”; keep the part after it
        let text = line.components(separatedBy: "execution error: ").last ?? line
        return text.isEmpty ? "Click to try again" : String(text.prefix(80))
    }
}

// MARK: - Items

struct LibItem: Hashable {
    var id: String          // persistent ID (or name for artists/albums/shows)
    var title: String
    var subtitle: String
}

struct CatalogItem: Hashable {
    var title: String
    var subtitle: String
    var art: URL?
    var url: URL?
}

enum Load<T> {
    case idle, loading, done(T), failed(ScriptError)
}

// MARK: - Library

final class MediaLibrary {
    static let shared = MediaLibrary()
    var onChange: (() -> Void)?

    private(set) var musicPlaylists: Load<[LibItem]> = .idle
    private(set) var musicSongs: Load<[LibItem]> = .idle
    private(set) var musicArtists: Load<[LibItem]> = .idle
    private(set) var musicAlbums: Load<[LibItem]> = .idle
    private(set) var tvItems: Load<[LibItem]> = .idle        // subtitle = show name ("" for movies)
    private(set) var lists: [String: Load<[LibItem]>] = [:]   // tracks of a playlist / artist / album / show

    static func installed(_ bid: String) -> Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) != nil }

    func refreshAll() {
        musicPlaylists = .idle; musicSongs = .idle; musicArtists = .idle; musicAlbums = .idle; tvItems = .idle
        lists = [:]
        onChange?()
    }

    private func changed() { onChange?() }

    // Splits "count|||SEP|||list1|||SEP|||list2…" into aligned rows
    private static func columns(_ text: String) -> [[String]] {
        let blocks = text.components(separatedBy: "|||SEP|||")
        guard let n = Int(blocks.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""), n > 0 else { return [] }
        let cols = blocks.dropFirst().map { b -> [String] in
            var parts = b.components(separatedBy: "\n")
            if parts.count > n { parts = Array(parts.prefix(n)) }
            while parts.count < n { parts.append("") }
            return parts.map { $0 == "missing value" ? "" : $0 }
        }
        return (0..<n).map { i in cols.map { $0[i] } }
    }

    /// name / artist / persistent ID of every track matched by `expr`, in the given app.
    private static func trackScript(app: String, expr: String, second: String = "artist") -> String {
        """
        \(Script.joinHandler)
        tell application "\(app)"
            set ns to name of (\(expr))
            set ars to {}
            try
                set ars to \(second) of (\(expr))
            end try
            set ids to persistent ID of (\(expr))
        end tell
        return ((count of ns) as text) & "|||SEP|||" & my joinList(ns) & "|||SEP|||" & my joinList(ars) & "|||SEP|||" & my joinList(ids)
        """
    }

    private func loadTracks(app: String, expr: String, second: String = "artist", limit: Int,
                            done: @escaping (Load<[LibItem]>) -> Void) {
        Script.run(Self.trackScript(app: app, expr: expr, second: second), timeout: 60) { r in
            switch r {
            case .success(let text):
                let rows = Self.columns(text).prefix(limit)
                done(.done(rows.map { LibItem(id: $0.count > 2 ? $0[2] : "", title: $0[0], subtitle: $0.count > 1 ? $0[1] : "") }))
            case .failure(let e): done(.failed(e))
            }
        }
    }

    // MARK: Music

    func ensureMusicPlaylists() {
        guard case .idle = musicPlaylists else { return }
        musicPlaylists = .loading
        let src = """
        set out to ""
        tell application "Music"
            repeat with p in (every user playlist)
                set sk to "none"
                try
                    set sk to (special kind of p) as text
                end try
                if sk is "none" then
                    try
                        set out to out & (name of p) & tab & (persistent ID of p) & tab & ((count of tracks of p) as text) & linefeed
                    end try
                end if
            end repeat
        end tell
        return out
        """
        Script.run(src) { [weak self] r in
            switch r {
            case .success(let text):
                let items = text.split(separator: "\n").compactMap { line -> LibItem? in
                    let f = line.components(separatedBy: "\t")
                    guard f.count >= 2 else { return nil }
                    return LibItem(id: f[1], title: f[0], subtitle: f.count > 2 ? "\(f[2]) songs" : "")
                }
                self?.musicPlaylists = .done(items)
            case .failure(let e): self?.musicPlaylists = .failed(e)
            }
            self?.changed()
        }
    }

    func ensureMusicSongs() {
        guard case .idle = musicSongs else { return }
        musicSongs = .loading
        loadTracks(app: "Music", expr: "every track of library playlist 1", limit: 4000) { [weak self] l in
            if case .done(let items) = l {
                self?.musicSongs = .done(items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
            } else { self?.musicSongs = l }
            self?.changed()
        }
    }

    func ensureMusicArtistsAndAlbums() {
        guard case .idle = musicArtists else { return }
        musicArtists = .loading; musicAlbums = .loading
        let src = """
        \(Script.joinHandler)
        tell application "Music"
            set ars to artist of every track of library playlist 1
            set als to album of every track of library playlist 1
        end tell
        return ((count of ars) as text) & "|||SEP|||" & my joinList(ars) & "|||SEP|||" & my joinList(als)
        """
        Script.run(src) { [weak self] r in
            switch r {
            case .success(let text):
                let rows = Self.columns(text)
                var artistCounts: [String: Int] = [:]
                var albums: [String: String] = [:]
                for row in rows {
                    let artist = row[0], album = row.count > 1 ? row[1] : ""
                    if !artist.isEmpty { artistCounts[artist, default: 0] += 1 }
                    if !album.isEmpty && albums[album] == nil { albums[album] = artist }
                }
                self?.musicArtists = .done(artistCounts.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                    .map { LibItem(id: $0, title: $0, subtitle: "\(artistCounts[$0] ?? 0) songs") })
                self?.musicAlbums = .done(albums.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                    .map { LibItem(id: $0, title: $0, subtitle: albums[$0] ?? "") })
            case .failure(let e):
                self?.musicArtists = .failed(e); self?.musicAlbums = .failed(e)
            }
            self?.changed()
        }
    }

    /// Tracks inside a playlist, by an artist, or on an album
    func ensureList(_ key: String) {
        if let existing = lists[key] {
            if case .idle = existing {} else { return }
        }
        lists[key] = .loading
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        let (kind, value) = (parts[0], parts[1])
        let app = kind.hasPrefix("tv") ? "TV" : "Music"
        let expr: String
        var second = "artist"
        switch kind {
        case "playlist": expr = "every track of (first playlist whose persistent ID is \(Script.quote(value)))"
        case "artist": expr = "every track of library playlist 1 whose artist is \(Script.quote(value))"
        case "album": expr = "every track of library playlist 1 whose album is \(Script.quote(value))"
        case "tvshow": expr = "every track of library playlist 1 whose show is \(Script.quote(value))"; second = "show"
        default: return
        }
        loadTracks(app: app, expr: expr, second: second, limit: 1500) { [weak self] l in
            self?.lists[key] = l
            self?.changed()
        }
    }

    func list(_ key: String) -> Load<[LibItem]> { lists[key] ?? .idle }

    // MARK: TV

    func ensureTV() {
        guard case .idle = tvItems else { return }
        tvItems = .loading
        loadTracks(app: "TV", expr: "every track of library playlist 1", second: "show", limit: 4000) { [weak self] l in
            self?.tvItems = l
            self?.changed()
        }
    }

    // MARK: Playing

    static func play(app: String, trackID: String, inPlaylist playlistID: String? = nil) {
        let container = playlistID.map { "(first playlist whose persistent ID is \(Script.quote($0)))" } ?? "library playlist 1"
        Script.run("tell application \"\(app)\" to play (first track of \(container) whose persistent ID is \(Script.quote(trackID)))") { _ in
            MusicWatcher.shared.poll()
        }
    }

    static func playPlaylist(_ id: String, shuffle: Bool) {
        Script.run("""
        tell application "Music"
            set shuffle enabled to \(shuffle ? "true" : "false")
            play (first playlist whose persistent ID is \(Script.quote(id)))
        end tell
        """) { _ in MusicWatcher.shared.poll() }
    }

    static func shuffleLibrary() {
        Script.run("""
        tell application "Music"
            set shuffle enabled to true
            play library playlist 1
        end tell
        """) { _ in MusicWatcher.shared.poll() }
    }

    // MARK: Library search

    static func searchLibrary(app: String, query: String, completion: @escaping (Load<[LibItem]>) -> Void) {
        let second = app == "TV" ? "show" : "artist"
        let src = """
        set out to ""
        tell application "\(app)"
            set R to (search library playlist 1 for \(Script.quote(query)))
            set c to count of R
            if c > 30 then set c to 30
            repeat with i from 1 to c
                set t to item i of R
                try
                    set s2 to ""
                    try
                        set s2 to (\(second) of t) as text
                    end try
                    set out to out & (name of t) & tab & s2 & tab & (persistent ID of t) & linefeed
                end try
            end repeat
        end tell
        return out
        """
        Script.run(src) { r in
            switch r {
            case .success(let text):
                completion(.done(text.split(separator: "\n").compactMap { line in
                    let f = line.components(separatedBy: "\t")
                    guard f.count >= 3 else { return nil }
                    return LibItem(id: f[2], title: f[0], subtitle: f[1])
                }))
            case .failure(let e): completion(.failed(e))
            }
        }
    }
}

// MARK: - Apple's public catalogue

enum Catalog {
    static var country: String { Locale.current.region?.identifier ?? "US" }

    private struct Response: Decodable { let results: [Item] }
    private struct Item: Decodable {
        let trackName: String?
        let collectionName: String?
        let artistName: String?
        let artworkUrl100: String?
        let trackViewUrl: String?
        let collectionViewUrl: String?
    }

    /// media/entity examples: music/song, music/album, movie/movie, tvShow/tvSeason, podcast/podcast
    static func search(_ term: String, media: String, entity: String, limit: Int = 20,
                       completion: @escaping (Load<[CatalogItem]>) -> Void) {
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [URLQueryItem(name: "term", value: term), URLQueryItem(name: "media", value: media),
                        URLQueryItem(name: "entity", value: entity), URLQueryItem(name: "country", value: country),
                        URLQueryItem(name: "limit", value: String(limit))]
        guard let url = c.url else { return }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("CouchRemote/1.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let result: Load<[CatalogItem]>
            if let data = data, let r = try? JSONDecoder().decode(Response.self, from: data) {
                let trackish = entity == "song" || entity == "movie"
                result = .done(r.results.map { i in
                    CatalogItem(title: (trackish ? i.trackName : i.collectionName) ?? i.trackName ?? i.collectionName ?? "",
                                subtitle: i.artistName ?? "",
                                art: i.artworkUrl100.flatMap { URL(string: $0.replacingOccurrences(of: "100x100", with: "400x400")) },
                                url: (trackish ? i.trackViewUrl : i.collectionViewUrl).flatMap { URL(string: $0) })
                })
            } else {
                let why = error?.localizedDescription ?? (status == 403 || status == 429 ? "Apple is limiting searches for a minute" : (status > 0 ? "Apple’s search answered with error \(status)" : "No connection"))
                result = .failed(ScriptError(message: why))
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    /// Opens a store link in the right Apple app (Music, TV or Podcasts), or the browser if it isn't installed.
    static func open(_ url: URL, inApp bundleID: String) {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// Apple Music sections (Home, New, Radio…), opened in the Music app
    static func musicSection(_ path: String) -> URL? {
        URL(string: "https://music.apple.com/\(country.lowercased())/\(path)")
    }
}

// MARK: - Search state (one search box shared by all search pages)

enum SearchScope: String { case all, music, tv, podcasts }

final class SearchStore {
    static let shared = SearchStore()
    var onChange: (() -> Void)?

    private(set) var query = ""
    private(set) var scope: SearchScope = .all
    private(set) var results: [String: Any] = [:]     // section id -> Load<[LibItem]> or Load<[CatalogItem]>
    private var work: DispatchWorkItem?
    private var generation = 0

    func begin(_ scope: SearchScope) {
        self.scope = scope
        if !query.isEmpty { schedule(now: true) }
    }

    func type(_ s: String) { query += s; schedule() }
    func backspace() { if !query.isEmpty { query.removeLast(); schedule() } }
    func clear() { query = ""; results = [:]; suggestionsFromStore = []; work?.cancel(); onChange?() }
    /// Replace the whole search (picking a suggestion or a recent search)
    func set(_ q: String) { query = q; schedule(now: true); remember(q) }

    // MARK: recent searches and suggestions

    var recent: [String] { ConfigStore.shared.settings.recentSearches }

    /// Saves a search you've used (when you open a result, pick a suggestion, or pause on it)
    func remember(_ q: String? = nil) {
        let s = (q ?? query).trimmingCharacters(in: .whitespaces)
        guard ConfigStore.shared.settings.rememberSearches, s.count >= 2 else { return }
        var list = ConfigStore.shared.settings.recentSearches.filter { $0.caseInsensitiveCompare(s) != .orderedSame }
        list.insert(s, at: 0)
        ConfigStore.shared.config.settings.recentSearches = Array(list.prefix(12))
    }

    func forgetRecent() { ConfigStore.shared.config.settings.recentSearches = [] }

    private var suggestionsFromStore: [String] = []

    /// Things you might be typing: your recent searches, artists and albums in your library, and artists in Apple Music
    var suggestions: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 1 else { return [] }
        var out: [String] = []
        func add(_ s: String) {
            if !out.contains(where: { $0.caseInsensitiveCompare(s) == .orderedSame }) && s.lowercased() != q { out.append(s) }
        }
        recent.filter { $0.lowercased().hasPrefix(q) }.forEach(add)
        let lib = MediaLibrary.shared
        for load in [lib.musicArtists, lib.musicAlbums] {
            if case .done(let items) = load {
                items.lazy.map(\.title).filter { $0.lowercased().hasPrefix(q) }.prefix(6).forEach(add)
            }
        }
        suggestionsFromStore.forEach(add)
        return Array(out.prefix(10))
    }

    private func fetchSuggestions(_ q: String, gen: Int) {
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [URLQueryItem(name: "term", value: q), URLQueryItem(name: "entity", value: "musicArtist"),
                        URLQueryItem(name: "country", value: Catalog.country), URLQueryItem(name: "limit", value: "6")]
        guard let url = c.url else { return }
        struct R: Decodable { struct A: Decodable { let artistName: String? }; let results: [A] }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let names = (data.flatMap { try? JSONDecoder().decode(R.self, from: $0) }?.results ?? []).compactMap(\.artistName)
            DispatchQueue.main.async {
                guard let self = self, gen == self.generation else { return }
                self.suggestionsFromStore = names
                self.onChange?()
            }
        }.resume()
    }

    func lib(_ id: String) -> Load<[LibItem]> { results[id] as? Load<[LibItem]> ?? .idle }
    func cat(_ id: String) -> Load<[CatalogItem]> { results[id] as? Load<[CatalogItem]> ?? .idle }

    private func schedule(now: Bool = false) {
        onChange?()
        work?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = [:]; onChange?(); return }
        let w = DispatchWorkItem { [weak self] in self?.run(q) }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + (now ? 0 : 0.6), execute: w)
    }

    private func run(_ q: String) {
        generation += 1
        let gen = generation
        results = [:]
        fetchSuggestions(q, gen: gen)
        // If you stay on this search for a few seconds, remember it
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self = self, gen == self.generation, self.query.trimmingCharacters(in: .whitespaces) == q else { return }
            self.remember(q)
        }
        func store(_ id: String, _ value: Any) {
            guard gen == self.generation else { return }    // a newer search replaced this one
            results[id] = value
            onChange?()
        }
        let music = MediaLibrary.installed("com.apple.Music")
        let tv = MediaLibrary.installed("com.apple.TV")
        if (scope == .all || scope == .music) && music {
            results["lib.music"] = Load<[LibItem]>.loading
            MediaLibrary.searchLibrary(app: "Music", query: q) { store("lib.music", $0) }
        }
        if scope == .all || scope == .music {
            results["cat.songs"] = Load<[CatalogItem]>.loading
            Catalog.search(q, media: "music", entity: "song") { store("cat.songs", $0) }
            results["cat.albums"] = Load<[CatalogItem]>.loading
            Catalog.search(q, media: "music", entity: "album", limit: 15) { store("cat.albums", $0) }
        }
        if (scope == .all || scope == .tv) && tv {
            results["lib.tv"] = Load<[LibItem]>.loading
            MediaLibrary.searchLibrary(app: "TV", query: q) { store("lib.tv", $0) }
        }
        if scope == .all || scope == .tv {
            results["cat.movies"] = Load<[CatalogItem]>.loading
            Catalog.search(q, media: "movie", entity: "movie") { store("cat.movies", $0) }
            results["cat.shows"] = Load<[CatalogItem]>.loading
            Catalog.search(q, media: "tvShow", entity: "tvSeason") { store("cat.shows", $0) }
        }
        if scope == .all || scope == .podcasts {
            results["cat.podcasts"] = Load<[CatalogItem]>.loading
            Catalog.search(q, media: "podcast", entity: "podcast", limit: 15) { store("cat.podcasts", $0) }
        }
        onChange?()
    }
}
