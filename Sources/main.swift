// main.swift — app start-up, menu bar icon and main window
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ note: Notification) {
        _ = ConfigStore.shared
        Engine.shared.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "appletvremote.gen1.fill", accessibilityDescription: "Couch Remote")
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Keep the remote's battery % showing next to the menu bar icon
        Engine.shared.onStatusChange = { [weak self] in self?.updateStatusTitle() }
        updateStatusTitle()

        // First launch, or permissions missing: show the window with the setup checklist
        Engine.shared.refreshStatus()
        if !UserDefaults.standard.bool(forKey: "launchedBefore") || !Engine.shared.axGranted || !Engine.shared.inputGranted {
            UserDefaults.standard.set(true, forKey: "launchedBefore")
            showWindow()
        }
        // Show the interactive tour the first time (once permissions are sorted)
        if !ConfigStore.shared.settings.tutorialDone && Engine.shared.axGranted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { Tutorial.shared.show() }
        }
        // Restart the phone remote if it was on last time
        if ConfigStore.shared.settings.phoneRemoteEnabled {
            _ = PhoneServer.shared.start()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(); return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        ConfigStore.shared.saveNow()
        Runner.stopKeepAwake()
    }

    @objc func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Couch Remote"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: MainView())
            w.center()
            w.setFrameAutosaveName("CouchRemoteMain")
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func cycleMode() { _ = Engine.shared.cycleMode() }
    @objc private func toggleSpot() { _ = Spotlight.shared.toggle() }
    @objc private func toggleMenu() { CouchMenu.shared.toggle() }

    /// Show the remote's battery % next to the menu bar icon (if turned on and the remote reports it)
    func updateStatusTitle() {
        let e = Engine.shared
        if ConfigStore.shared.settings.menuBarBattery, e.connected, let b = e.battery {
            statusItem.button?.title = " \(b)%"
        } else {
            statusItem.button?.title = ""
        }
    }
    @objc private func openBigScreen() { BigScreen.shared.open() }
    @objc private func toggleYouTube() { YouTubeApp.shared.toggle() }
    @objc private func toggleKeyboard() { KeyboardPanel.shared.toggle() }
    @objc private func reconnect() { RemoteHID.shared.restart(); TouchSurface.shared.reattach() }
    @objc private func togglePhone() { PhoneServer.shared.running ? PhoneServer.shared.disable() : PhoneServer.shared.enable() }
    @objc private func phoneSetup() { PhoneSetup.shared.show() }
    @objc private func sleepTimer() { HUD.shared.show(SleepTimer.shared.cycle(), symbol: "timer", kind: .sleepTimer) }
    @objc private func setMode(_ sender: NSMenuItem) {
        if let m = TouchMode(rawValue: sender.representedObject as? String ?? "") { Engine.shared.setMode(m, announce: true) }
    }
}

extension AppDelegate: NSMenuDelegate {
    // Rebuilt each time it opens so the status is current
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let e = Engine.shared
        e.refreshStatus()
        let status = NSMenuItem(title: e.connected ? "● \(e.deviceName)" + (e.battery.map { " — \($0)%" } ?? "") : "○ Remote not connected", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        let prof = NSMenuItem(title: "Profile: \(e.activeProfile)", action: nil, keyEquivalent: ""); prof.isEnabled = false
        menu.addItem(prof)
        menu.addItem(.separator())

        let modeMenu = NSMenu()
        for m in TouchMode.allCases {
            let it = NSMenuItem(title: m.title, action: #selector(setMode(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = m.rawValue; it.state = (e.mode == m) ? .on : .off
            modeMenu.addItem(it)
        }
        let modeItem = NSMenuItem(title: "Touch mode: \(e.mode.short)", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        func add(_ title: String, _ sel: Selector, _ key: String = "") {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: key); it.target = self; menu.addItem(it)
        }
        add("Open Big Screen", #selector(openBigScreen))
        add(YouTubeApp.shared.isOpen ? "Close YouTube" : "Open YouTube", #selector(toggleYouTube))
        add("Open Couch Menu", #selector(toggleMenu))
        add("On‑screen keyboard", #selector(toggleKeyboard))
        add(Spotlight.shared.on ? "Turn Mousespot off" : "Mousespot", #selector(toggleSpot))
        add(SleepTimer.shared.fireAt == nil ? "Start sleep timer" : "Sleep timer: next step", #selector(sleepTimer))
        menu.addItem(.separator())
        let phone = NSMenuItem(title: PhoneServer.shared.running ? "Phone remote: On" : "Phone remote: Off", action: #selector(togglePhone), keyEquivalent: "")
        phone.target = self; phone.state = PhoneServer.shared.running ? .on : .off
        menu.addItem(phone)
        add("Phone remote setup…", #selector(phoneSetup))
        menu.addItem(.separator())
        add("Settings…", #selector(showWindow), ",")
        add("Reconnect remote", #selector(reconnect))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Couch Remote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
