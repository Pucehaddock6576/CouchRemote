// MusicExtras.swift — more Apple Music: recently played / added, EQ presets, Love, add to playlist
import Foundation

final class MusicExtras {
    static let shared = MusicExtras()
    var onChange: (() -> Void)?

    private(set) var recentlyPlayed: Load<[LibItem]> = .idle
    private(set) var recentlyAdded: Load<[LibItem]> = .idle
    private(set) var eqPresets: Load<[String]> = .idle
    private(set) var eqCurrent: String?            // nil = EQ off
    private var recentLoadedAt = Date.distantPast

    private func changed() { onChange?() }

    // MARK: Recently played / added

    /// Uses JavaScript for Automation, which can read whole columns of a big library quickly.
    func ensureRecent() {
        let stale = Date().timeIntervalSince(recentLoadedAt) > 120
        if case .loading = recentlyPlayed { return }
        if case .done = recentlyPlayed, !stale { return }
        recentlyPlayed = .loading; recentlyAdded = .loading
        let js = """
        var M = Application('Music');
        var T = M.libraryPlaylists[0].tracks;
        var n = T.name(), a = T.artist(), id = T.persistentID(), pd = T.playedDate(), da = T.dateAdded();
        function top(d) {
          var idx = [];
          for (var i = 0; i < n.length; i++) { if (d[i]) idx.push(i); }
          idx.sort(function (x, y) { return d[y] - d[x]; });
          var seen = {}, out = [];
          for (var k = 0; k < idx.length && out.length < 30; k++) {
            var i = idx[k];
            if (seen[id[i]]) continue;
            seen[id[i]] = 1;
            out.push([id[i], n[i] || '', a[i] || '']);
          }
          return out;
        }
        JSON.stringify({ played: top(pd), added: top(da) });
        """
        Script.run(js, javaScript: true) { [weak self] r in
            guard let self = self else { return }
            self.recentLoadedAt = Date()
            switch r {
            case .success(let text):
                struct R: Decodable { let played: [[String]]; let added: [[String]] }
                if let data = text.data(using: .utf8), let parsed = try? JSONDecoder().decode(R.self, from: data) {
                    func items(_ rows: [[String]]) -> [LibItem] {
                        rows.compactMap { $0.count == 3 ? LibItem(id: $0[0], title: $0[1], subtitle: $0[2]) : nil }
                    }
                    self.recentlyPlayed = .done(items(parsed.played))
                    self.recentlyAdded = .done(items(parsed.added))
                } else {
                    let e = ScriptError(message: "Couldn't read the library")
                    self.recentlyPlayed = .failed(e); self.recentlyAdded = .failed(e)
                }
            case .failure(let e):
                self.recentlyPlayed = .failed(e); self.recentlyAdded = .failed(e)
            }
            self.changed()
        }
    }

    // MARK: EQ

    func ensureEQ(force: Bool = false) {
        if !force, case .done = eqPresets { return }
        if case .loading = eqPresets { return }
        eqPresets = .loading
        let src = """
        tell application "Music"
            set out to ""
            if EQ enabled then
                try
                    set out to name of current EQ preset
                end try
            end if
            set out to out & linefeed
            repeat with p in (every EQ preset)
                set out to out & (name of p) & linefeed
            end repeat
            return out
        end tell
        """
        Script.run(src) { [weak self] r in
            guard let self = self else { return }
            switch r {
            case .success(let text):
                var lines = text.components(separatedBy: "\n")
                let current = lines.isEmpty ? "" : lines.removeFirst()
                self.eqCurrent = current.isEmpty ? nil : current
                self.eqPresets = .done(lines.filter { !$0.isEmpty })
            case .failure(let e):
                self.eqPresets = .failed(e)
            }
            self.changed()
        }
    }

    /// nil turns the EQ off
    func setEQ(_ name: String?) {
        let src: String
        if let n = name {
            src = """
            tell application "Music"
                set current EQ preset to EQ preset \(Script.quote(n))
                set EQ enabled to true
            end tell
            """
        } else {
            src = "tell application \"Music\" to set EQ enabled to false"
        }
        eqCurrent = name
        changed()
        Script.run(src) { [weak self] _ in self?.ensureEQ(force: true) }
    }

    // MARK: Track actions

    private static func track(_ id: String) -> String {
        "(first track of library playlist 1 whose persistent ID is \(Script.quote(id)))"
    }

    /// Marks a song as a favourite (called "Love" on older macOS)
    static func love(_ id: String, done: @escaping (Bool) -> Void) {
        let src = """
        tell application "Music"
            set t to \(track(id))
            try
                set favorited of t to true
            on error
                set loved of t to true
            end try
        end tell
        """
        Script.run(src) { r in if case .success = r { done(true) } else { done(false) } }
    }

    static func add(_ id: String, toPlaylist playlistID: String, done: @escaping (Bool) -> Void) {
        let src = """
        tell application "Music"
            duplicate \(track(id)) to (first user playlist whose persistent ID is \(Script.quote(playlistID)))
        end tell
        """
        Script.run(src) { r in if case .success = r { done(true) } else { done(false) } }
    }

    /// Artist and album of a song in your library
    static func info(_ id: String, done: @escaping (_ artist: String, _ album: String) -> Void) {
        let src = """
        tell application "Music"
            set t to \(track(id))
            return (artist of t) & linefeed & (album of t)
        end tell
        """
        Script.run(src) { r in
            guard case .success(let text) = r else { done("", ""); return }
            let parts = text.components(separatedBy: "\n")
            done(parts.first ?? "", parts.count > 1 ? parts[1] : "")
        }
    }
}
