// MusicWatcher.swift — knows what's playing, and where.
// Music and Spotify broadcast a notification whenever playback changes, so they're instant
// (a slow AppleScript check every 15s keeps them honest). Everything else — browsers, Podcasts,
// IINA, VLC, Tidal… — comes from macOS's own Now Playing info, when macOS shares it.
import AppKit
import Combine

final class MusicWatcher: ObservableObject {
    static let shared = MusicWatcher()
    static let players: [(name: String, bundleID: String)] = [("Spotify", "com.spotify.client"), ("Music", "com.apple.Music")]
    /// Apps where swiping left/right should change the song (not e.g. YouTube in a browser, where arrows seek)
    static let musicApps: Set<String> = ["com.apple.Music", "com.spotify.client", "com.apple.podcasts", "com.tidal.desktop",
                                         "com.deezer.deezer-desktop", "com.coppertino.Vox", "com.swinsian.Swinsian",
                                         "com.audirvana.Audirvana-Studio", "com.roon.Roon", "com.apple.Music.Classical",
                                         "com.amazon.music", "com.pocketcasts.mac", "fm.overcast.overcast"]

    @Published private(set) var playing = false
    @Published private(set) var app: String?        // "Music", "Spotify", or another app's name
    @Published private(set) var track = ""
    @Published private(set) var artist = ""
    @Published private(set) var otherBundleID: String?   // set when the info came from macOS Now Playing

    private struct State { var playing: Bool; var track: String; var artist: String; var at: Date }
    private var states: [String: State] = [:]
    private var timer: Timer?
    private var lastTrack = ""
    var onTrackChange: (() -> Void)?

    var bundleID: String? {
        guard let a = app else { return nil }
        return Self.players.first { $0.name == a }?.bundleID ?? otherBundleID
    }

    /// Music is playing in a music app (used for swipe-to-skip)
    var musicPlaying: Bool { playing && Self.musicApps.contains(bundleID ?? "") }

    var summary: String {
        guard let a = app else { return "Nothing playing" }
        let what = track.isEmpty ? a : track + (artist.isEmpty ? "" : " — \(artist)")
        return (playing ? "♪ " : "Paused: ") + what
    }

    func start() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] n in
            self?.update("Music", n.userInfo)
        }
        dnc.addObserver(forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] n in
            self?.update("Spotify", n.userInfo)
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let a = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let p = Self.players.first(where: { $0.bundleID == a.bundleIdentifier }) else { return }
            self?.states[p.name] = nil
            self?.recompute()
        }
        NowPlaying.shared.onChange = { [weak self] in self?.recompute() }
        NowPlaying.shared.start()
        poll()
        timer = Timer.common(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func isRunning(_ bid: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bid).isEmpty
    }

    private func update(_ name: String, _ info: [AnyHashable: Any]?) {
        let state = (info?["Player State"] as? String ?? "").lowercased()
        if state == "stopped" { states[name] = nil; recompute(); return }
        var s = states[name] ?? State(playing: false, track: "", artist: "", at: Date())
        s.playing = (state == "playing")
        if let t = info?["Name"] as? String { s.track = t }
        if let a = info?["Artist"] as? String { s.artist = a }
        s.at = Date()
        states[name] = s
        recompute()
    }

    /// Asks the apps directly. Only talks to apps that are already open, so it never launches them.
    func poll() {
        for p in Self.players {
            guard isRunning(p.bundleID) else { states[p.name] = nil; continue }
            let src = """
            tell application "\(p.name)"
                if player state is playing then
                    set s to "playing"
                else if player state is paused then
                    set s to "paused"
                else
                    set s to "stopped"
                end if
                set n to ""
                set a to ""
                try
                    set n to name of current track
                    set a to artist of current track
                end try
                return s & "|" & n & "|" & a
            end tell
            """
            guard let r = Runner.appleScript(src), !r.hasPrefix("Script error") else { continue }
            let parts = r.components(separatedBy: "|")
            let st = parts.first ?? ""
            if st == "stopped" { states[p.name] = nil; continue }
            let old = states[p.name]
            let isPlaying = (st == "playing")
            states[p.name] = State(playing: isPlaying,
                                   track: parts.count > 1 ? parts[1] : "",
                                   artist: parts.count > 2 ? parts[2] : "",
                                   at: (old?.playing == isPlaying ? old?.at : nil) ?? Date())
        }
        NowPlaying.shared.refresh()
        recompute()
    }

    private static let otherKey = "__nowplaying__"

    private func recompute() {
        // Another app from macOS Now Playing (Music and Spotify are read directly, which is more reliable)
        let np = NowPlaying.shared
        if ConfigStore.shared.settings.systemNowPlaying, np.hasInfo, let bid = np.bundleID,
           !Self.players.contains(where: { $0.bundleID == bid }) {
            let old = states[Self.otherKey]
            states[Self.otherKey] = State(playing: np.playing, track: np.title, artist: np.artist,
                                          at: (old?.playing == np.playing && old?.track == np.title ? old?.at : nil) ?? Date())
        } else {
            states[Self.otherKey] = nil
        }
        // Prefer whichever app is playing; otherwise the one that changed most recently
        let playingStates = states.filter { $0.value.playing }
        let pick = playingStates.max { $0.value.at < $1.value.at } ?? states.max { $0.value.at < $1.value.at }
        playing = pick?.value.playing ?? false
        if pick?.key == Self.otherKey {
            app = np.appName; otherBundleID = np.bundleID
        } else {
            app = pick?.key; otherBundleID = nil
        }
        track = pick?.value.track ?? ""
        artist = pick?.value.artist ?? ""
        if track != lastTrack { lastTrack = track; onTrackChange?() }
    }

    private var isOther: Bool { app != nil && otherBundleID != nil }

    // MARK: control

    func playPause() {
        if isOther, NowPlaying.shared.send(.toggle) { return }
        guard let name = app else { Input.media(.play); return }
        Runner.appleScript("tell application \"\(name)\" to playpause")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.poll() }
    }

    @discardableResult
    func skip(forward: Bool) -> String {
        let label = forward ? "Next song" : "Previous song"
        let symbol = forward ? "forward.fill" : "backward.fill"
        // Couch Remote's own Up Next queue plays before Music's next song
        if forward, app == "Music", UpNext.shared.playNextNow() {
            HUD.shared.show("Up Next", symbol: symbol, kind: .playback)
            return "Up Next"
        }
        if isOther {
            if !NowPlaying.shared.send(forward ? .next : .previous) { Input.media(forward ? .next : .previous) }
            HUD.shared.show(label, symbol: symbol, kind: .playback)
            return label
        }
        guard let name = app else { Input.media(forward ? .next : .previous); return label }
        Runner.appleScript("tell application \"\(name)\" to \(forward ? "next track" : "previous track")")
        HUD.shared.show(label, symbol: symbol, kind: .playback)
        // Then show the new song's name once the app has switched
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self = self else { return }
            self.poll()
            if !self.track.isEmpty {
                HUD.shared.show(self.track + (self.artist.isEmpty ? "" : " — \(self.artist)"), symbol: symbol, kind: .songChange)
            }
        }
        return label
    }
}
