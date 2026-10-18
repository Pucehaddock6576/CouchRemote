// AppSwitcher.swift — the ⌘Tab app switcher, held open so you can browse it with the remote
import AppKit

/// macOS only shows the app switcher while ⌘ is held down. This holds ⌘ for you: swipe or glide
/// left/right to move through the apps, click (or press Play) to switch, Menu to cancel.
/// If you do nothing for a few seconds it switches to the highlighted app by itself.
final class AppSwitcher {
    static let shared = AppSwitcher()

    private(set) var active = false
    private var idle: DispatchWorkItem?
    private let src = CGEventSource(stateID: .hidSystemState)

    private func post(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
        guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down) else { return }
        e.flags = flags
        e.setIntegerValueField(.eventSourceUserData, value: kCouchEventMarker)
        e.post(tap: .cghidEventTap)
    }

    private func tab(backwards: Bool) {
        var f: CGEventFlags = .maskCommand
        if backwards {
            f.insert(.maskShift)
            post(56, down: true, flags: f)                       // ⇧ down
        }
        post(CGKeyCode(KeyCode.tab), down: true, flags: f)
        post(CGKeyCode(KeyCode.tab), down: false, flags: f)
        if backwards { post(56, down: false, flags: .maskCommand) }
        armTimeout()
    }

    private func arrow(_ code: Int) {
        let f: CGEventFlags = [.maskCommand, .maskSecondaryFn, .maskNumericPad]
        post(CGKeyCode(code), down: true, flags: f)
        post(CGKeyCode(code), down: false, flags: f)
        armTimeout()
    }

    /// Opens the switcher, or moves to the next app if it's already open.
    func openOrNext() {
        if active { tab(backwards: false); return }
        Input.releaseIfHeld()
        active = true
        post(55, down: true, flags: .maskCommand)                // ⌘ down, and keep it held
        tab(backwards: false)
    }

    /// Switch to the highlighted app.
    func commit() {
        guard active else { return }
        active = false
        idle?.cancel(); idle = nil
        post(55, down: false, flags: [])                         // let go of ⌘
    }

    /// Close the switcher without switching.
    func cancel() {
        guard active else { return }
        post(53, down: true, flags: .maskCommand)                // Esc while ⌘ is held closes it
        post(53, down: false, flags: .maskCommand)
        commit()
    }

    private func armTimeout() {
        idle?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.commit() }
        idle = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: w)
    }

    /// Remote input while the switcher is open. Returns true if handled.
    func handle(_ t: Trigger) -> Bool {
        guard active else { return false }
        switch t {
        case .swipeRight, .clickRight: tab(backwards: false)
        case .swipeLeft, .clickLeft: tab(backwards: true)
        case .swipeUp, .clickUp: arrow(KeyCode.up)                // move between an app's windows
        case .swipeDown, .clickDown: arrow(KeyCode.down)
        case .select, .playTap, .selectHold: commit()
        case .menuTap, .menuHold, .homeTap: cancel()
        default: return false
        }
        return true
    }
}
