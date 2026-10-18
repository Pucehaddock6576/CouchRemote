// UpNext.swift — Couch Remote's own "Up Next" queue for Apple Music.
// Music doesn't let other apps see or change its own Up Next list, so Couch Remote keeps a queue
// and starts the next queued song itself just before the current one ends (or when you press Next).
import Foundation

final class UpNext {
    static let shared = UpNext()
    var onChange: (() -> Void)?

    private(set) var items: [LibItem] = []
    private var timer: Timer?
    private var pending: DispatchWorkItem?
    private var checking = false
    private let key = "upNextQueue"

    private init() {
        if let raw = UserDefaults.standard.array(forKey: key) as? [[String]] {
            items = raw.compactMap { $0.count == 3 ? LibItem(id: $0[0], title: $0[1], subtitle: $0[2]) : nil }
        }
        timer = Timer.common(withTimeInterval: 2.5, repeats: true) { [weak self] _ in self?.check() }
    }

    private func save() {
        UserDefaults.standard.set(items.map { [$0.id, $0.title, $0.subtitle] }, forKey: key)
        onChange?()
    }

    private var musicBusy: Bool { MusicWatcher.shared.app == "Music" && MusicWatcher.shared.playing }

    /// Plays straight away if Music isn't playing; otherwise goes to the front of the queue.
    @discardableResult
    func playNext(_ it: LibItem) -> String {
        guard musicBusy else { MediaLibrary.play(app: "Music", trackID: it.id); return "Playing \(it.title)" }
        items.removeAll { $0.id == it.id }
        items.insert(it, at: 0); save()
        return "Next: \(it.title)"
    }

    /// Plays straight away if Music isn't playing; otherwise goes to the end of the queue.
    @discardableResult
    func playLater(_ it: LibItem) -> String {
        guard musicBusy else { MediaLibrary.play(app: "Music", trackID: it.id); return "Playing \(it.title)" }
        items.removeAll { $0.id == it.id }
        items.append(it); save()
        return "Later: \(it.title)"
    }

    func remove(_ id: String) { items.removeAll { $0.id == id }; save() }
    func clear() { items = []; save() }

    /// New order after rearranging (ids in order)
    func reorder(_ ids: [String]) {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        items = ids.compactMap { byID[$0] }
        save()
    }

    func playNow(_ id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let it = items.remove(at: i); save()
        MediaLibrary.play(app: "Music", trackID: it.id)
    }

    /// Starts the first queued song. Returns false if the queue is empty.
    @discardableResult
    func playNextNow() -> Bool {
        pending?.cancel(); pending = nil
        guard !items.isEmpty else { return false }
        let it = items.removeFirst(); save()
        MediaLibrary.play(app: "Music", trackID: it.id)
        return true
    }

    /// Every few seconds while Music plays: when the song is nearly over, line up the next queued one.
    private func check() {
        guard !items.isEmpty, musicBusy, !checking, pending == nil else { return }
        checking = true
        Script.run("tell application \"Music\" to return ((duration of current track) - player position) as text") { [weak self] r in
            guard let self = self else { return }
            self.checking = false
            guard case .success(let text) = r,
                  let remaining = Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)),
                  remaining < 4 else { return }
            let w = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.pending = nil
                if self.musicBusy { self.playNextNow() }
            }
            self.pending = w
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, remaining - 0.6), execute: w)
        }
    }
}
