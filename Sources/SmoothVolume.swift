// SmoothVolume.swift — slide a finger along an edge of the glass to set the volume precisely
import AppKit
import CoreAudio
import AudioToolbox

/// Sets the output volume directly through Core Audio, so it can follow your finger in fine steps
/// with no lag. Some outputs (HDMI, some USB devices) don't allow that; those fall back to AppleScript.
enum SmoothVolume {
    private static var level: Double = 0.5          // 0…1
    private static var scriptBusy = false
    private static var scriptPending = false
    private static var lastShown = -1

    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)

    private static func outputDevice() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    private static func read() -> Double? {
        guard let d = outputDevice(), AudioObjectHasProperty(d, &volumeAddress) else { return nil }
        var v = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(d, &volumeAddress, 0, nil, &size, &v) == noErr else { return nil }
        return Double(v)
    }

    private static func write(_ x: Double) -> Bool {
        guard let d = outputDevice(), AudioObjectHasProperty(d, &volumeAddress) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(d, &volumeAddress, &settable) == noErr, settable.boolValue else { return false }
        var v = Float32(x)
        guard AudioObjectSetPropertyData(d, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr else { return false }
        if x > 0 {   // turning it up also unmutes, like the volume keys
            var muteAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                      mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            if AudioObjectHasProperty(d, &muteAddr) {
                var off = UInt32(0)
                _ = AudioObjectSetPropertyData(d, &muteAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &off)
            }
        }
        return true
    }

    /// Where the finger wants the volume to be; `level` glides towards it many times a second,
    /// so the volume changes continuously while you slide instead of in steps.
    private static var target: Double = 0.5
    private static var glide: Timer?
    private static var direct = true                // false: this output only takes AppleScript

    /// Call when the finger starts sliding, so we start from the real current volume.
    static func begin() {
        if let v = read() { level = v; direct = true }
        else {
            direct = false
            if let s = Runner.appleScript("output volume of (get volume settings)"), let v = Double(s) { level = v / 100 }
        }
        target = level
        lastShown = -1
    }

    /// percent: how much to change the volume by (can be fractional; it's applied smoothly)
    static func change(by percent: Double) {
        target = min(1, max(0, target + percent / 100))
        Runner.volumeTarget = (target * 100, Date())    // so the volume buttons carry on from here
        show()
        startGlide()
    }

    /// About 120 times a second, move the real volume a good part of the way to where the finger is.
    /// Finger movement arrives in small jumps; this smooths them into one continuous change.
    private static func startGlide() {
        guard glide == nil else { return }
        let t = Timer(timeInterval: 1.0 / 120, repeats: true) { _ in SmoothVolume.step() }
        RunLoop.main.add(t, forMode: .common)           // keeps running while menus or windows are tracking
        glide = t
        step()
    }

    private static func step() {
        let gap = target - level
        if abs(gap) < 0.0008 {
            level = target
            apply()
            glide?.invalidate(); glide = nil
            return
        }
        level += gap * 0.35
        apply()
    }

    private static func apply() {
        if direct, write(level) { return }
        direct = false
        sendScript()
    }

    /// AppleScript fallback: only one at a time, always sending the newest level.
    private static func sendScript() {
        if scriptBusy { scriptPending = true; return }
        scriptBusy = true
        Script.run("set volume output volume \(Int((target * 100).rounded())) without output muted") { _ in
            SmoothVolume.scriptBusy = false
            if SmoothVolume.scriptPending { SmoothVolume.scriptPending = false; SmoothVolume.sendScript() }
        }
    }

    private static func show() {
        let pct = Int((target * 100).rounded())
        guard pct != lastShown else { return }
        lastShown = pct
        Engine.shared.lastEvent = "Edge slide → Volume \(pct)%"
        guard ConfigStore.shared.settings.showHUD else { return }

        HUD.shared.show("Volume \(pct)%",
                        symbol: pct == 0 ? "speaker.slash.fill" : (pct < 34 ? "speaker.wave.1.fill" : (pct < 67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")),
                        kind: .volume, level: target)
    }
}
