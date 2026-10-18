// YouTubeApp.swift — a built-in, remote-friendly YouTube.
//
// It opens YouTube's TV interface (youtube.com/tv) in a clean full-screen window using WebKit, and
// pretends to be a smart TV so YouTube serves the D-pad layout you can drive from the couch. The remote
// then just sends the arrow keys / Return / Escape the TV UI already understands: swipes and edge clicks
// move the highlight, the touch surface click chooses, Play/Pause plays and pauses, and Menu goes back.
//
// There's nothing to install — WebKit ships with macOS. If YouTube ever stops serving the TV page to this
// user agent, the address and the "pretend to be a TV" switch are both in Settings → Big Screen, so it can
// be pointed at m.youtube.com or the full site instead.
import AppKit
import WebKit

final class YouTubeApp: NSObject {
    static let shared = YouTubeApp()

    private var window: NSWindow?
    private var web: WKWebView?
    private weak var previousApp: NSRunningApplication?

    var isOpen: Bool { window?.isVisible == true }

    func toggle() { isOpen ? close() : open() }

    func open() {
        guard !isOpen else { return }
        Input.releaseIfHeld()
        BigScreen.shared.close(restore: false)      // one full-screen app at a time
        CouchMenu.shared.close()
        KeyboardPanel.shared.close()
        if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]

        if window == nil {
            let cfg = WKWebViewConfiguration()
            cfg.mediaTypesRequiringUserActionForPlayback = []       // videos may autoplay, like a TV
            cfg.allowsAirPlayForMediaPlayback = true
            let web = WKWebView(frame: screen.frame, configuration: cfg)
            web.underPageBackgroundColor = .black                   // no white flash before the page paints
            web.navigationDelegate = self
            self.web = web

            let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.level = .floating
            w.isOpaque = true
            w.backgroundColor = .black
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.isReleasedWhenClosed = false
            w.contentView = web
            window = w
        }
        guard let w = window, let web = web else { return }
        web.customUserAgent = ConfigStore.shared.settings.youtubeTVUserAgent ? Self.tvUserAgent : nil
        w.setFrame(screen.frame, display: true)
        load()

        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = [.autoHideDock, .autoHideMenuBar]
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(web)
        NSCursor.setHiddenUntilMouseMoves(true)
        Engine.shared.lastEvent = "YouTube opened"
    }

    func load() {
        guard let web = web else { return }
        let typed = ConfigStore.shared.settings.youtubeURL.trimmingCharacters(in: .whitespaces)
        let str = typed.isEmpty ? "https://www.youtube.com/tv" : typed
        if let url = URL(string: str) { web.load(URLRequest(url: url)) }
    }

    func reload() { web?.reload() }

    func close() {
        guard let w = window else { return }
        // Stop any sound before it goes away
        web?.evaluateJavaScript("document.querySelectorAll('video').forEach(function(v){v.pause()})", completionHandler: nil)
        NSApp.presentationOptions = []
        w.orderOut(nil)
        if let prev = previousApp, prev.bundleIdentifier != Bundle.main.bundleIdentifier {
            prev.activate()
        }
        Engine.shared.lastEvent = "YouTube closed"
    }

    /// Drive the TV interface with the keys it already understands. Because this window is key and the web
    /// view is first responder, a real key event posted here lands straight in the page.
    func handle(_ t: Trigger) -> Bool {
        switch t {
        case .swipeUp, .clickUp:       Input.key(KeyCode.up)
        case .swipeDown, .clickDown:   Input.key(KeyCode.down)
        case .swipeLeft, .clickLeft:   Input.key(KeyCode.left)
        case .swipeRight, .clickRight: Input.key(KeyCode.right)
        case .select:                  Input.key(KeyCode.ret)
        case .selectHold:              Input.key(KeyCode.ret)
        case .playTap:                 Input.key(KeyCode.space)   // the TV player plays/pauses on space
        case .menuTap:                 Input.key(KeyCode.escape)  // Escape steps back in the TV UI
        case .homeTap:                 close()
        default: return false
        }
        return true
    }

    /// A smart‑TV user agent, so YouTube serves the big D‑pad interface instead of the desktop site.
    static let tvUserAgent =
        "Mozilla/5.0 (Web0S; Linux/SmartTV) AppleWebKit/537.36 (KHTML, like Gecko) " +
        "Chrome/94.0.4606.31 Safari/537.36 CrKey/1.54.250320"
}

extension YouTubeApp: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Engine.shared.lastEvent = "YouTube couldn't load — try a different address in Settings"
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Engine.shared.lastEvent = "YouTube couldn't load — check your connection or the address in Settings"
    }
}
