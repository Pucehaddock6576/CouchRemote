// RemoteHID.swift — finds the paired Siri Remote and reads its buttons (press / double / hold)
import Foundation
import IOKit
import IOKit.hid

final class RemoteHID {
    static let shared = RemoteHID()

    // Outputs
    var onTrigger: ((Trigger) -> Void)?
    var onSelect: ((Bool) -> Void)?                 // touch-surface click down/up
    var onButtonVisual: ((String, Bool) -> Void)?   // for the live remote picture
    var onConnection: ((Bool, String) -> Void)?
    var isMapped: ((Trigger) -> Bool) = { _ in true }

    private(set) var connected = false
    private(set) var deviceName = ""
    private(set) var openFailed = false
    private var manager: IOHIDManager?
    private var devices: [IOHIDDevice] = []
    private var down: [String: Date] = [:]
    private var held: Set<String> = []
    private var holdTimers: [String: DispatchWorkItem] = [:]
    private var pendingTap: [String: DispatchWorkItem] = [:]
    private var repeatTimer: Timer?

    private let appleVendor = 0x004C
    private let knownProducts: Set<Int> = [0x0221, 0x0255, 0x0266, 0x0267, 0x0269, 0x0C4E, 0x0C4F, 0x030D, 0x030E, 0x0314, 0x0315]

    // MARK: stay awake
    // The remote decides when to doze off itself, and macOS can't change that timer.
    // What we can do is gently talk to it every so often, which keeps the Bluetooth link
    // busy so it stays connected for longer after you put it down.
    private(set) var lastActivity = Date()
    private var keepAliveTimer: Timer?
    private let pingQueue = DispatchQueue(label: "couchremote.keepalive")

    func noteActivity() { lastActivity = Date() }

    private func startKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = Timer.common(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.keepAliveTick() }
    }

    private func keepAliveTick() {
        let minutes = ConfigStore.shared.settings.remoteStayAwakeMinutes
        guard minutes != 0, connected, !devices.isEmpty else { return }
        if minutes > 0 && Date().timeIntervalSince(lastActivity) > Double(minutes * 60) { return }
        let devs = devices
        pingQueue.async { devs.forEach(RemoteHID.ping) }
    }

    /// Asks the remote for a small status report. Harmless if it doesn't have one.
    private static func ping(_ d: IOHIDDevice) {
        guard let arr = IOHIDDeviceCopyMatchingElements(d, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as NSArray? else { return }
        var ids: [UInt32] = []
        for obj in arr {
            let e = obj as! IOHIDElement
            if IOHIDElementGetType(e) == kIOHIDElementTypeFeature {
                let id = IOHIDElementGetReportID(e)
                if !ids.contains(id) { ids.append(id) }
            }
        }
        for id in ids.prefix(2) {
            var buf = [UInt8](repeating: 0, count: 64)
            var len = CFIndex(buf.count)
            _ = IOHIDDeviceGetReport(d, kIOHIDReportTypeFeature, CFIndex(id), &buf, &len)
        }
    }

    func start() {
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = m
        IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey: appleVendor] as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, _, _, dev in
            guard let ctx = ctx else { return }
            Unmanaged<RemoteHID>.fromOpaque(ctx).takeUnretainedValue().added(dev)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { ctx, _, _, dev in
            guard let ctx = ctx else { return }
            Unmanaged<RemoteHID>.fromOpaque(ctx).takeUnretainedValue().removed(dev)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let r = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        openFailed = (r != kIOReturnSuccess)
        startKeepAlive()
    }

    func restart() {
        if let m = manager {
            for d in devices { IOHIDDeviceClose(d, IOOptionBits(kIOHIDOptionsTypeNone)) }
            devices.removeAll()
            IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
            manager = nil
        }
        start()
    }

    private func isRemote(_ d: IOHIDDevice) -> Bool {
        if let pid = IOHIDDeviceGetProperty(d, kIOHIDProductIDKey as CFString) as? Int, knownProducts.contains(pid) { return true }
        let name = (IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String ?? "").lowercased()
        return name.contains("remote") || name.contains("siri")
    }

    private func added(_ d: IOHIDDevice) {
        guard isRemote(d), !devices.contains(where: { $0 == d }) else { return }
        // Seize so macOS doesn't also act on the buttons; fall back to shared access.
        var ok = IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) == kIOReturnSuccess
        if !ok { ok = IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess }
        guard ok else { openFailed = true; return }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputValueCallback(d, { ctx, _, _, value in
            guard let ctx = ctx else { return }
            Unmanaged<RemoteHID>.fromOpaque(ctx).takeUnretainedValue().input(value)
        }, ctx)
        IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        devices.append(d)
        deviceName = IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String ?? "Siri Remote"
        if !connected {
            connected = true
            onConnection?(true, deviceName)
        }
    }

    private func removed(_ d: IOHIDDevice) {
        devices.removeAll { $0 == d }
        if devices.isEmpty && connected {
            connected = false
            onConnection?(false, deviceName)
        }
    }

    var batteryPercent: Int? {
        for d in devices {
            for key in ["BatteryPercent", "BatteryLevel"] {
                if let v = IOHIDDeviceGetProperty(d, key as CFString) as? Int { return v }
            }
        }
        return nil
    }

    // MARK: input decoding

    private func buttonName(page: UInt32, usage: UInt32) -> String? {
        switch (page, usage) {
        case (0x01, 0x86), (0x01, 0x40), (0x0C, 0x40), (0x0C, 0x224): return "menu"
        case (0x0C, 0x60), (0x0C, 0x223): return "home"
        case (0x0C, 0x04), (0x0B, 0x21), (0x0B, 0x2F): return "siri"
        case (0xFF00, _): return "siri"
        case (0x0C, 0x80), (0x0C, 0x41), (0x09, 0x01): return "select"
        case (0x0C, 0xCD): return "play"
        case (0x0C, 0xE9): return "vol.up"
        case (0x0C, 0xEA): return "vol.down"
        default: return nil
        }
    }

    private func input(_ value: IOHIDValue) {
        let el = IOHIDValueGetElement(value)
        guard let name = buttonName(page: IOHIDElementGetUsagePage(el), usage: IOHIDElementGetUsage(el)) else {
            MotionLab.shared.record(value)      // anything that isn't a button: maybe motion (experimental air mouse)
            return
        }
        let pressed = IOHIDValueGetIntegerValue(value) != 0
        // the remote mirrors buttons across several interfaces: ignore duplicates
        if pressed == (down[name] != nil) { return }
        if pressed { down[name] = Date() } else { down[name] = nil }
        onButtonVisual?(name, pressed)
        noteActivity()
        TouchSurface.shared.wakeIfNeeded()

        if name == "select" { onSelect?(pressed); return }
        if name == "vol.up" || name == "vol.down" { if pressed { Engine.shared.noteVolumeButton() }; volume(name == "vol.up" ? .volUp : .volDown, pressed: pressed); return }
        if name == "play" { Engine.shared.notePlayButton() }
        gesture(name, pressed: pressed)
    }

    private func volume(_ t: Trigger, pressed: Bool) {
        repeatTimer?.invalidate(); repeatTimer = nil
        guard pressed else { return }
        onTrigger?(t)
        guard ConfigStore.shared.settings.repeatVolumeWhileHeld else { return }
        repeatTimer = Timer.common(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.repeatTimer = Timer.common(withTimeInterval: 0.12, repeats: true) { _ in Engine.shared.noteVolumeButton(); self?.onTrigger?(t) }
        }
    }

    private func trig(_ button: String, _ variant: String) -> Trigger? { Trigger(rawValue: "\(button).\(variant)") }

    private func gesture(_ b: String, pressed: Bool) {
        let s = ConfigStore.shared.settings
        if pressed {
            held.remove(b)
            holdTimers[b]?.cancel()
            if let hold = trig(b, "hold"), isMapped(hold) {
                let w = DispatchWorkItem { [weak self] in
                    guard let self = self, self.down[b] != nil else { return }
                    self.held.insert(b)
                    self.pendingTap[b]?.cancel(); self.pendingTap[b] = nil
                    self.onTrigger?(hold)
                }
                holdTimers[b] = w
                DispatchQueue.main.asyncAfter(deadline: .now() + s.holdTime, execute: w)
            }
            return
        }
        holdTimers[b]?.cancel(); holdTimers[b] = nil
        if held.contains(b) { held.remove(b); return }
        guard let tap = trig(b, "tap") else { return }
        if let dbl = trig(b, "double"), isMapped(dbl) {
            if let pending = pendingTap[b] {
                pending.cancel(); pendingTap[b] = nil
                onTrigger?(dbl)
            } else {
                let w = DispatchWorkItem { [weak self] in self?.pendingTap[b] = nil; self?.onTrigger?(tap) }
                pendingTap[b] = w
                DispatchQueue.main.asyncAfter(deadline: .now() + s.doubleTapWindow, execute: w)
            }
        } else {
            onTrigger?(tap)
        }
    }
}
