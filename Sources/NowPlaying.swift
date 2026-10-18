// NowPlaying.swift — reads macOS's own "Now Playing" info (the same thing Control Centre shows),
// so the remote knows what's playing in any app: browsers, Podcasts, IINA, VLC and more.
// This uses a hidden part of macOS (MediaRemote). Apple has been locking it down: on some
// newer macOS versions other apps can still send play/pause/skip, but can no longer read the info.
import AppKit

final class NowPlaying {
    static let shared = NowPlaying()

    private(set) var title = ""
    private(set) var artist = ""
    private(set) var album = ""
    private(set) var playing = false
    private(set) var bundleID: String?
    private(set) var appName: String?
    private(set) var artwork: NSImage?
    private(set) var everWorked = false      // has macOS ever given us any info?
    var onChange: (() -> Void)?

    var hasInfo: Bool { appName != nil && (!title.isEmpty || playing) }

    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping @convention(block) (NSDictionary?) -> Void) -> Void
    private typealias GetPIDFn = @convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void
    private typealias GetIsPlayingFn = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
    private typealias SendCommandFn = @convention(c) (UInt32, NSDictionary?) -> Bool
    private typealias RegisterFn = @convention(c) (DispatchQueue) -> Void

    private var getInfo: GetInfoFn?
    private var getPID: GetPIDFn?
    private var getIsPlaying: GetIsPlayingFn?
    private var sendCommand: SendCommandFn?
    private var timer: Timer?
    private var started = false

    enum Command: UInt32 { case play = 0, pause = 1, toggle = 2, stop = 3, next = 4, previous = 5 }

    var available: Bool { getInfo != nil }

    private init() {
        guard let h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) else { return }
        func sym<T>(_ name: String, _ t: T.Type) -> T? { dlsym(h, name).map { unsafeBitCast($0, to: t) } }
        getInfo = sym("MRMediaRemoteGetNowPlayingInfo", GetInfoFn.self)
        getPID = sym("MRMediaRemoteGetNowPlayingApplicationPID", GetPIDFn.self)
        getIsPlaying = sym("MRMediaRemoteGetNowPlayingApplicationIsPlaying", GetIsPlayingFn.self)
        sendCommand = sym("MRMediaRemoteSendCommand", SendCommandFn.self)
        if let register = sym("MRMediaRemoteRegisterForNowPlayingNotifications", RegisterFn.self) { register(.main) }
    }

    func start() {
        guard !started, available else { return }
        started = true
        for name in ["kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                     "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                     "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"] {
            NotificationCenter.default.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
        }
        refresh()
        timer = Timer.common(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        guard ConfigStore.shared.settings.systemNowPlaying, let getInfo = getInfo else {
            if appName != nil { clear() }
            return
        }
        getInfo(.main) { [weak self] info in
            guard let self = self else { return }
            let d = info as? [String: Any] ?? [:]
            self.title = d["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
            self.artist = d["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
            self.album = d["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
            if let data = d["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data { self.artwork = NSImage(data: data) } else { self.artwork = nil }
            let rate = (d["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue
            if !d.isEmpty { self.everWorked = true }
            if let rate = rate { self.playing = rate > 0 }
            self.getIsPlaying?(.main) { p in self.playing = p || (rate ?? 0) > 0; self.findApp() }
            if self.getIsPlaying == nil { self.findApp() }
        }
    }

    private func findApp() {
        guard let getPID = getPID else { publish(); return }
        getPID(.main) { [weak self] pid in
            guard let self = self else { return }
            let app = pid > 0 ? NSRunningApplication(processIdentifier: pid) : nil
            self.bundleID = app?.bundleIdentifier
            self.appName = app?.localizedName
            if self.title.isEmpty && !self.playing { self.appName = nil }
            self.publish()
        }
    }

    private func clear() {
        title = ""; artist = ""; album = ""; playing = false; bundleID = nil; appName = nil; artwork = nil
        publish()
    }

    private func publish() { onChange?() }

    /// Sends play/pause/skip to whatever app is playing. Returns false if macOS didn't accept it.
    @discardableResult
    func send(_ c: Command) -> Bool {
        guard let send = sendCommand else { return false }
        let ok = send(c.rawValue, nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
        return ok
    }
}
