// NowPlayingFull.swift — Big Screen: the full-screen Now Playing view.
// Shows the album cover big, and plays Apple Music's moving album art (the looping video some albums have)
// when it can find one. Neither needs an account: the cover comes from Apple's public search, and the
// moving art from the album's public page on music.apple.com.
import AppKit
import SwiftUI
import AVFoundation

final class NowPlayingArt: ObservableObject {
    static let shared = NowPlayingArt()

    @Published private(set) var cover: NSImage?
    @Published private(set) var video: URL?
    @Published private(set) var album = ""
    private var key = ""
    private var videoCache: [String: URL?] = [:]      // album page → moving art (nil = it has none)

    /// Looks up art for the current song. Cheap to call often: it only works when the song changes.
    func update() {
        let m = MusicWatcher.shared
        let np = NowPlaying.shared
        let k = m.track + "|" + m.artist
        guard k != key else { return }
        key = k
        video = nil; album = ""
        // Start with what macOS already has (other apps), so there's something to show straight away
        cover = m.otherBundleID != nil ? np.artwork : nil
        if m.otherBundleID != nil { album = np.album }
        guard !m.track.isEmpty else { return }

        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [URLQueryItem(name: "term", value: m.track + " " + m.artist), URLQueryItem(name: "media", value: "music"),
                        URLQueryItem(name: "entity", value: "song"), URLQueryItem(name: "country", value: Catalog.country),
                        URLQueryItem(name: "limit", value: "5")]
        guard let url = c.url else { return }
        struct R: Decodable {
            struct S: Decodable { let trackName: String?; let artistName: String?; let collectionName: String?
                                  let artworkUrl100: String?; let collectionViewUrl: String? }
            let results: [S]
        }
        let wantTrack = m.track.lowercased(), wantArtist = m.artist.lowercased()
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 15)) { [weak self] data, _, _ in
            let results = (data.flatMap { try? JSONDecoder().decode(R.self, from: $0) }?.results) ?? []
            // Prefer the result that really is this song by this artist
            let best = results.first(where: { ($0.trackName ?? "").lowercased() == wantTrack && (($0.artistName ?? "").lowercased().contains(wantArtist) || wantArtist.isEmpty) })
                ?? results.first(where: { ($0.trackName ?? "").lowercased().hasPrefix(wantTrack) })
                ?? results.first
            DispatchQueue.main.async {
                guard let self = self, self.key == k, let s = best else { return }
                if self.album.isEmpty { self.album = s.collectionName ?? "" }
                if let a = s.artworkUrl100, let big = URL(string: a.replacingOccurrences(of: "100x100", with: "1200x1200")) {
                    self.loadCover(big, key: k)
                }
                if ConfigStore.shared.settings.liveAlbumArt, let page = s.collectionViewUrl { self.findVideo(page, key: k) }
            }
        }.resume()
    }

    private func loadCover(_ url: URL, key k: String) {
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 20)) { [weak self] data, _, _ in
            guard let img = data.flatMap({ NSImage(data: $0) }) else { return }
            DispatchQueue.main.async { if self?.key == k { self?.cover = img } }
        }.resume()
    }

    /// Album pages on music.apple.com list the moving art as a video stream (an .m3u8 link). Not every album has one.
    private func findVideo(_ page: String, key k: String) {
        let pageKey = page.components(separatedBy: "?").first ?? page
        if let cached = videoCache[pageKey] { video = cached; return }
        guard let url = URL(string: pageKey) else { return }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            let html = (data.flatMap { String(data: $0, encoding: .utf8) } ?? "")
                .replacingOccurrences(of: "\\u002F", with: "/").replacingOccurrences(of: "\\/", with: "/")
            var found: URL?
            if let r = html.range(of: #"https://mvod\.itunes\.apple\.com/[^"'\s<>]+?\.m3u8"#, options: .regularExpression) {
                found = URL(string: String(html[r]))
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.videoCache[pageKey] = found
                if self.key == k { self.video = found }
            }
        }.resume()
    }
}

// MARK: - Looping, muted video (the moving album art)

final class LoopingVideoNSView: NSView {
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private let layerView = AVPlayerLayer()
    private(set) var url: URL?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerView.player = player
        layerView.videoGravity = .resizeAspectFill
        layer?.addSublayer(layerView)
        player.isMuted = true                    // the song is already playing; the video is just for looks
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() { super.layout(); layerView.frame = bounds }

    func play(_ u: URL?) {
        guard u != url else { return }
        url = u
        player.pause(); looper = nil; player.removeAllItems()
        guard let u = u else { return }
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: u))
        player.play()
    }

    func stop() { player.pause(); looper = nil; player.removeAllItems(); url = nil }
}

struct LoopingVideo: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> LoopingVideoNSView { let v = LoopingVideoNSView(); v.play(url); return v }
    func updateNSView(_ v: LoopingVideoNSView, context: Context) { v.play(url) }
    static func dismantleNSView(_ v: LoopingVideoNSView, coordinator: ()) { v.stop() }
}

// MARK: - The view

struct NowPlayingFullView: View {
    @ObservedObject var music = MusicWatcher.shared
    @ObservedObject var art = NowPlayingArt.shared

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.height * 0.62, geo.size.width * 0.42)
            ZStack {
                Color.black
                // A soft, blurred copy of the cover fills the background
                if let c = art.cover {
                    Image(nsImage: c).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                        .blur(radius: 60).opacity(0.55)
                }
                LinearGradient(colors: [Color.black.opacity(0.1), Color.black.opacity(0.65)], startPoint: .top, endPoint: .bottom)

                HStack(spacing: 60) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.08))
                        if let c = art.cover {
                            Image(nsImage: c).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "music.note").font(.system(size: side * 0.3, weight: .semibold)).foregroundStyle(Color.white.opacity(0.5))
                        }
                        if let v = art.video { LoopingVideo(url: v) }
                    }
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.6), radius: 40, y: 20)

                    VStack(alignment: .leading, spacing: 14) {
                        Text(music.playing ? "NOW PLAYING" : "PAUSED")
                            .font(.system(size: 18, weight: .heavy)).foregroundStyle(Color.white.opacity(0.6))
                        Text(music.track.isEmpty ? (music.app ?? "") : music.track)
                            .font(.system(size: 54, weight: .heavy, design: .rounded))
                            .lineLimit(3).minimumScaleFactor(0.5).fixedSize(horizontal: false, vertical: true)
                        if !music.artist.isEmpty {
                            Text(music.artist).font(.system(size: 32, weight: .semibold)).foregroundStyle(Color.white.opacity(0.85)).lineLimit(2)
                        }
                        if !art.album.isEmpty {
                            Text(art.album).font(.system(size: 24)).foregroundStyle(Color.white.opacity(0.6)).lineLimit(2)
                        }
                        Spacer().frame(height: 20)
                        HStack(spacing: 26) {
                            hint("arrow.left.and.right", "Swipe: previous / next · hold: rewind / fast‑forward")
                            hint(music.playing ? "pause.fill" : "play.fill", music.playing ? "Click: pause" : "Click: play")
                            hint("arrow.uturn.backward", "Menu: back")
                        }
                    }
                    .frame(maxWidth: geo.size.width * 0.42, alignment: .leading)
                }
                .padding(.horizontal, 80)
            }
            .foregroundStyle(Color.white)
        }
        .ignoresSafeArea()
        .onAppear { art.update() }
        .onChange(of: music.track) { _ in art.update() }
    }

    private func hint(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(Color.white.opacity(0.7))
    }
}
