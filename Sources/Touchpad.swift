// Touchpad.swift — reads the Siri Remote's touch surface through MultitouchSupport
import Foundation
import AppKit
import Darwin

/// One touch frame, copied off the touch thread.
struct TouchFrame {
    var points: [CGPoint]          // normalised 0…1, y grows upwards
    var time: TimeInterval
}

struct TouchDeviceInfo: Identifiable, Hashable {
    var id: Int                    // index in the system list
    var family: Int32
    var width: Int32
    var height: Int32
    var builtIn: Bool
    var label: String { builtIn ? "Built‑in trackpad" : "Touch device \(id + 1) (family \(family), \(width)×\(height))" }
}

private struct MT {
    let createList: MTDeviceCreateListFn
    let isBuiltIn: MTDeviceIsBuiltInFn
    let isRunning: MTDeviceIsRunningFn
    let start: MTDeviceStartFn
    let stop: MTDeviceStopFn
    let register: MTRegisterCallbackFn
    let unregister: MTUnregisterCallbackFn
    let family: MTDeviceGetFamilyIDFn?
    let dims: MTDeviceGetSensorSurfaceDimensionsFn?

    static let shared: MT? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW) else { return nil }
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: type)
        }
        guard let a = sym("MTDeviceCreateList", MTDeviceCreateListFn.self),
              let b = sym("MTDeviceIsBuiltIn", MTDeviceIsBuiltInFn.self),
              let c = sym("MTDeviceIsRunning", MTDeviceIsRunningFn.self),
              let d = sym("MTDeviceStart", MTDeviceStartFn.self),
              let e = sym("MTDeviceStop", MTDeviceStopFn.self),
              let f = sym("MTRegisterContactFrameCallbackWithRefcon", MTRegisterCallbackFn.self),
              let g = sym("MTUnregisterContactFrameCallback", MTUnregisterCallbackFn.self) else { return nil }
        return MT(createList: a, isBuiltIn: b, isRunning: c, start: d, stop: e, register: f, unregister: g,
                  family: sym("MTDeviceGetFamilyID", MTDeviceGetFamilyIDFn.self),
                  dims: sym("MTDeviceGetSensorSurfaceDimensions", MTDeviceGetSensorSurfaceDimensionsFn.self))
    }()
}

/// C callback: runs on the multitouch thread, so copy the data and hop to the main thread.
private let frameCallback: MTFrameCallbackRefcon = { _, touches, count, timestamp, _, refcon in
    var pts: [CGPoint] = []
    if let touches = touches {
        for i in 0..<Int(count) {
            let t = touches[i]
            if t.state == 3 || t.state == 4 {   // make-touch or touching
                pts.append(CGPoint(x: CGFloat(t.normalizedVector.position.x), y: CGFloat(t.normalizedVector.position.y)))
            }
        }
    }
    let frame = TouchFrame(points: pts, time: timestamp)
    DispatchQueue.main.async { TouchSurface.shared.handle(frame) }
}

final class TouchSurface {
    static let shared = TouchSurface()

    var onTouchingChanged: ((Bool) -> Void)?
    var onVisual: ((CGPoint?) -> Void)?          // live dot in the settings window
    private(set) var available = MT.shared != nil
    private(set) var attached = false
    private(set) var lastPoint: CGPoint?         // last known finger position (for edge clicks)

    private var device: AnyObject?
    private var monitor: Timer?
    private var lastFrameAt = Date.distantPast

    // per-gesture state
    private var touching = false
    private var startPoint = CGPoint.zero
    private var startTime: TimeInterval = 0
    private var prev: CGPoint?
    private var prevCount = 0
    private var maxFingers = 0
    private var travelled: CGFloat = 0
    private var suppressTap = false
    var isTouching: Bool { touching }

    func start() {
        attach()
        monitor = Timer.common(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.check() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.detach(); self?.attach()
        }
    }

    // MARK: device handling

    func listDevices() -> [TouchDeviceInfo] {
        guard let mt = MT.shared, let arr = mt.createList()?.takeRetainedValue() else { return [] }
        let list = (arr as NSArray).map { $0 as AnyObject }
        return list.enumerated().map { (i, dev) in
            var fam: Int32 = 0, w: Int32 = 0, h: Int32 = 0
            _ = mt.family?(dev, &fam)
            _ = mt.dims?(dev, &w, &h)
            return TouchDeviceInfo(id: i, family: fam, width: w, height: h, builtIn: mt.isBuiltIn(dev))
        }
    }

    /// Picks the Siri Remote: the smallest touch surface that isn't built in
    /// (so a Magic Trackpad isn't mistaken for the remote). Can be overridden in Settings.
    private func pickDevice(from list: [AnyObject], mt: MT) -> AnyObject? {
        let chosen = UserDefaults.standard.integer(forKey: "touchDeviceIndex") - 1   // 0 = automatic
        if chosen >= 0 && chosen < list.count { return list[chosen] }
        var best: (AnyObject, Int64)?
        for dev in list where !mt.isBuiltIn(dev) {
            var w: Int32 = 0, h: Int32 = 0
            _ = mt.dims?(dev, &w, &h)
            let area = Int64(w) * Int64(h)
            if best == nil || area < best!.1 { best = (dev, area) }
        }
        return best?.0
    }

    func attach() {
        guard let mt = MT.shared, device == nil, let arr = mt.createList()?.takeRetainedValue() else { return }
        let list = (arr as NSArray).map { $0 as AnyObject }
        guard let dev = pickDevice(from: list, mt: mt) else { attached = false; return }
        mt.register(dev, frameCallback, nil)
        _ = mt.start(dev, 0)
        device = dev
        attached = true
        lastFrameAt = Date()
    }

    func detach() {
        guard let mt = MT.shared, let dev = device else { return }
        mt.unregister(dev, frameCallback)
        _ = mt.stop(dev)
        device = nil
        attached = false
        endGesture(cancelled: true)
    }

    func reattach() { detach(); attach() }

    /// Called when a button is pressed: the remote may have just woken up.
    func wakeIfNeeded() {
        if device == nil { attach() }
        else if Date().timeIntervalSince(lastFrameAt) > 20 { reattach() }
    }

    private func check() {
        guard let mt = MT.shared else { return }
        if let dev = device, !mt.isRunning(dev) { reattach(); return }
        if device == nil { attach() }
    }

    // MARK: gestures

    func handle(_ f: TouchFrame) {
        lastFrameAt = Date()
        RemoteHID.shared.noteActivity()
        let s = ConfigStore.shared.settings
        guard !f.points.isEmpty else { endGesture(cancelled: false); return }
        lastFrameTime = f.time

        let n = f.points.count
        let c = CGPoint(x: f.points.map(\.x).reduce(0, +) / CGFloat(n), y: f.points.map(\.y).reduce(0, +) / CGFloat(n))
        lastPoint = c
        onVisual?(c)

        if !touching {
            touching = true
            startPoint = c; startTime = f.time; prev = c; prevCount = n
            maxFingers = n; travelled = 0; suppressTap = false
            navAccum = .zero; navMoved = false; sideUsed = false
            smooth = .zero
            holdAnchor = c; holdCheck?.cancel(); holdCheck = nil
            liveSteps = 0; liveAnchorY = c.y
            stopMomentum()
            // Tap, then touch again straight away and slide = drag (like a Mac trackpad's tap-to-drag)
            let soon = Date().timeIntervalSince(lastTapAt) < s.tapDragWindow
            tapDragArmed = s.tapDrag && n == 1 && soon && Engine.shared.mode == .trackpad && !anyPanelOpen && !Calibration.shared.active
                && hypot(c.x - lastTapPoint.x, c.y - lastTapPoint.y) < 0.3
            tapDragging = false
            edge = (tapDragArmed || Calibration.shared.active) ? .idle : beginEdge(at: c, fingers: n, s: s)
            onTouchingChanged?(true)
            return
        }
        maxFingers = max(maxFingers, n)
        defer { prev = c; prevCount = n }
        guard let p = prev, prevCount == n else { return }   // finger count changed: re-anchor

        let dx = c.x - p.x, dy = c.y - p.y
        travelled += hypot(dx, dy)

        // Big Screen’s full-screen Now Playing: a swipe changes song when you lift, swipe and hold seeks
        if BigScreen.shared.seeksOnSwipe {
            if n == 1 && (s.holdToSeek || Scrubber.shared.active || ListRepeater.shared.active) { trackSeekHold(c, s: s) }
            return
        }
        // While an overlay is open, gliding your thumb steps through it (like Apple TV)
        if anyPanelOpen {
            navAccum.x += dx; navAccum.y += dy
            let step = CGFloat(s.navStep)
            // In the Couch Menu, sideways means "open" and "back", so it needs a clearer, longer sideways glide
            let sideStep = CouchMenu.shared.isOpen ? step * 1.5 : step
            if abs(navAccum.x) >= sideStep && abs(navAccum.x) > abs(navAccum.y) * 1.3 {
                // one open/back per touch in the Couch Menu: lift your finger to go again
                if CouchMenu.shared.isOpen { if sideUsed { navAccum.x = 0; return }; sideUsed = true }
                Engine.shared.fire(navAccum.x > 0 ? .swipeRight : .swipeLeft)
                navAccum = .zero; navMoved = true
            } else if abs(navAccum.y) >= step && abs(navAccum.y) >= abs(navAccum.x) {
                Engine.shared.fire(navAccum.y > 0 ? .swipeUp : .swipeDown)
                navAccum = .zero; navMoved = true
            }
            return
        }

        let mode = Engine.shared.mode
        if mode != .trackpad && n == 1 && edge != .idle && edgeMoved(to: c, dx: dx, dy: dy, time: f.time, s: s) { return }
        if mode == .remote && n == 1 && s.instantListSwipe && edge == .idle && !Scrubber.shared.active && !ListRepeater.shared.active { liveListStep(c, s: s) }
        if mode == .remote && n == 1 && (s.holdToSeek || s.holdToRepeat || Scrubber.shared.active || ListRepeater.shared.active) { trackSeekHold(c, s: s) }
        if n != 1, edge != .idle { finishSpaceSwipe(edge); edge = .idle }        // a second finger: normal two-finger scrolling takes over
        // Glass pressed and held: keep the pointer still until you slide, then drag from where you pressed
        if mode == .trackpad && clickHeld && s.dragOnLongClick && !Input.dragging && !refused {
            if edge != .idle { finishSpaceSwipe(edge); edge = .idle }
            pressTravel += hypot(dx, dy)
            if pressTravel > 0.02 { Engine.shared.beginHeldDrag(moved: true) }
            return
        }
        if mode == .trackpad && n == 1 && !clickHeld && edgeMoved(to: c, dx: dx, dy: dy, time: f.time, s: s) { return }
        if mode == .trackpad && n == 1 && tapDragArmed && !tapDragging && travelled > 0.012 {
            tapDragging = true; suppressTap = true
            Input.mouseDown()
        }
        if mode == .trackpad && n == 1 {
            movePointer(dx: dx, dy: dy, time: f.time, s: s)
        } else if (mode == .trackpad && n >= 2) || mode == .scroll {
            let sign: CGFloat = s.naturalScroll ? 1 : -1
            let k = 1600 * CGFloat(s.scrollSpeed) * sign
            Input.scroll(dx: Int32(-dx * k), dy: Int32(dy * k))
            if travelled > CGFloat(s.tapMaxTravel) { suppressTap = true }
        }
    }

    // MARK: pointer feel

    private var smooth = CGPoint.zero
    private var freezeUntil = Date.distantPast
    private var history: [(t: Date, dx: CGFloat, dy: CGFloat)] = []

    private func movePointer(dx: CGFloat, dy: CGFloat, time: TimeInterval, s: Settings) {
        // Ignore the first moment after a finger lands (the contact patch settles and "jumps")
        if time - startTime < 0.035 { return }
        // Hold the pointer still around a click, so pressing down doesn't nudge it off target
        if Date() < freezeUntil { smooth = .zero; return }

        // Smoothing: a light low-pass filter removes jitter without adding much lag
        let a = CGFloat(1 - 0.75 * min(max(s.smoothing, 0), 1))
        smooth.x += a * (dx - smooth.x)
        smooth.y += a * (dy - smooth.y)
        let v = hypot(smooth.x, smooth.y)
        if v < 0.00035 { return }                       // tiny tremors: ignore

        // Precision curve: slow movements are scaled right down for fine control,
        // fast flicks get the full speed plus acceleration to cross the screen.
        let t = min(v / 0.018, 1)
        let minGain = 1 - 0.85 * CGFloat(min(max(s.precision, 0), 1))
        let curve = minGain + (1 - minGain) * pow(t, 1.5)
        let gain = 1300 * CGFloat(s.cursorSpeed) * curve * (1 + CGFloat(s.acceleration) * 1.6 * t * t)
        let mx = smooth.x * gain, my = -smooth.y * gain
        Input.move(dx: mx, dy: my)

        let now = Date()
        history.append((now, mx, my))
        history.removeAll { now.timeIntervalSince($0.t) > 0.25 }
    }

    /// The glass was pressed down: undo the last split-second of movement
    /// (your thumb rolls as you press) and hold the pointer still briefly.
    /// True while the glass is pressed down in Trackpad mode
    private(set) var clickHeld = false
    private var pressTravel: CGFloat = 0

    /// The drag has started: the pointer follows your finger again straight away
    func dragBegan() { freezeUntil = .distantPast; smooth = .zero; history.removeAll() }

    /// Pressed and slid somewhere that isn't a title bar: no drag, the pointer just moves while pressed
    private var refused = false
    func dragRefused() { refused = true; dragBegan() }

    func clickBegan() {
        clickHeld = true; pressTravel = 0; refused = false
        if edge != .idle { finishSpaceSwipe(edge); edge = .idle }   // pressing the glass isn't an edge gesture
        guard ConfigStore.shared.settings.clickStabiliser else { return }
        let now = Date()
        let recent = history.filter { now.timeIntervalSince($0.t) < 0.12 }
        let bx = recent.reduce(0) { $0 + $1.dx }, by = recent.reduce(0) { $0 + $1.dy }
        if abs(bx) + abs(by) > 0.5 { Input.move(dx: -bx, dy: -by) }
        history.removeAll()
        smooth = .zero
        freezeUntil = now.addingTimeInterval(0.3)      // after this, moving while held = drag
    }

    func clickEnded() {
        clickHeld = false
        guard ConfigStore.shared.settings.clickStabiliser else { return }
        smooth = .zero
        freezeUntil = Date().addingTimeInterval(0.15)  // lifting off shouldn't move it either
    }

    /// Called by the Engine when the surface is physically clicked, so a click isn't also a tap.
    func noteClicked() { suppressTap = true }

    private func endGesture(cancelled: Bool) {
        guard touching else { return }
        clickHeld = false                               // the finger lifted, so the glass can't still be pressed
        touching = false
        // How long the finger was off the glass before this touch (the calibration wizard uses it)
        let gapBefore = prevEndTime > 0 ? startTime - prevEndTime : 99
        prevEndTime = lastFrameTime
        onTouchingChanged?(false)
        onVisual?(nil)
        defer { prev = nil }
        let edgeState = edge
        finishSpaceSwipe(edgeState)          // a Spaces swipe always has to be finished, even if cancelled
        edge = .idle
        if tapDragging { tapDragging = false; tapDragArmed = false; Input.mouseUp(); return }   // end of a tap-drag
        tapDragArmed = false
        holdCheck?.cancel(); holdCheck = nil
        if Scrubber.shared.active { Scrubber.shared.stop(); return }   // a held swipe was seeking: don't also swipe
        if ListRepeater.shared.active { ListRepeater.shared.stop(); return }
        if liveSteps > 0 { liveSteps = 0; return }     // up/down already stepped while the finger moved: lifting does nothing more
        if cancelled || navMoved { return }   // overlay navigation already handled this gesture
        let s = ConfigStore.shared.settings
        let end = lastPoint ?? startPoint
        let vx = end.x - startPoint.x, vy = end.y - startPoint.y
        let dist = hypot(vx, vy)
        let elapsed = max(0, lastFrameTime - startTime)

        // The calibration wizard is measuring how you tap and swipe: report it and do nothing else
        if Calibration.shared.active {
            Calibration.shared.touch(TouchSample(distance: Double(dist), travelled: Double(travelled), duration: elapsed,
                                                 fingers: maxFingers, dx: Double(vx), dy: Double(vy),
                                                 gapBefore: gapBefore))
            return
        }

        // Edge and corner gestures
        switch edgeState {
        case .swipe(let g):
            if dist >= max(0.08, CGFloat(s.swipeDistance) * 0.7) && elapsed < 1.2 { Engine.shared.runGesture(g) }
            return
        case .slider(let g):
            if (g.motion == .scrollVertical || g.motion == .scrollHorizontal) && s.edgeScrollMomentum { startMomentum() }
            return
        case .done:
            return
        case .pending(let candidates):
            if travelled < 0.03 && elapsed < 0.25, let g = candidates.first(where: { $0.motion == .tap }) {
                Engine.shared.runGesture(g)
                return
            }
        case .idle:
            break
        }

        // Swipes → menu / keyboard navigation or Remote-mode triggers
        if dist >= CGFloat(s.swipeDistance) && elapsed < 0.8 {
            let t: Trigger = abs(vx) > abs(vy) ? (vx > 0 ? .swipeRight : .swipeLeft) : (vy > 0 ? .swipeUp : .swipeDown)
            Engine.shared.swipe(t)
            return
        }
        // Taps (only clean, quick, still touches count, so resting your thumb doesn't click).
        // Two fingers never land at exactly the same moment, so they get a little more leeway.
        let two = maxFingers >= 2
        let maxTravel = CGFloat(s.tapMaxTravel) * (two ? 1.8 : 1)
        let maxTime = s.tapMaxTime + (two ? 0.1 : 0)
        if !suppressTap && travelled < maxTravel && elapsed < maxTime {
            if !two { lastTapAt = Date(); lastTapPoint = end }
            // Remote mode: a single-finger tap acts like the Apple TV clickpad (centre selects, around it navigates)
            if !two && Engine.shared.mode == .remote && s.remoteTapZones {
                Engine.shared.tapZone(end)
            } else {
                Engine.shared.tap(fingers: maxFingers)
            }
        }
    }

    // tap-to-drag
    private var lastTapAt = Date.distantPast
    private var lastTapPoint = CGPoint.zero
    private var tapDragArmed = false
    private var tapDragging = false

    // MARK: swipe and hold to seek (Remote mode)

    private var holdAnchor = CGPoint.zero
    private var holdCheck: DispatchWorkItem?

    // Up/down in Remote mode steps straight away as you slide, instead of waiting for you to lift
    private var liveSteps = 0
    private var liveAnchorY: CGFloat = 0

    /// One step (the Swipe up / Swipe down action) as soon as the finger has slid far enough,
    /// then another for each further bit of slide, like turning a scroll wheel.
    private func liveListStep(_ c: CGPoint, s: Settings) {
        let vxTotal = c.x - startPoint.x, vyTotal = c.y - startPoint.y
        guard abs(vyTotal) > abs(vxTotal) * 1.3, !anyPanelOpen else { return }   // sideways swipes are left alone
        let needed = CGFloat(s.swipeDistance) * 0.7
        let step = liveSteps == 0 ? needed : needed * CGFloat(s.listStepSpacing)
        let vy = c.y - liveAnchorY
        guard abs(vy) >= step else { return }
        Engine.shared.fire(vy > 0 ? .swipeUp : .swipeDown, repeating: liveSteps > 0)
        liveSteps += 1
        liveAnchorY = c.y
        suppressTap = true
        holdAnchor = c
    }

    /// Each time the finger moves, restart the wait. If it then rests after a clear swipe, keep going:
    /// sideways = fast-forward / rewind, up/down = keep moving through a list. How far the finger is
    /// from where it started sets the speed; back to the middle pauses, past it reverses.
    private func trackSeekHold(_ c: CGPoint, s: Settings) {
        let vx = c.x - startPoint.x, vy = c.y - startPoint.y
        let needed = CGFloat(s.swipeDistance) * 0.7
        if Scrubber.shared.active {
            Scrubber.shared.push = holdPush(vx, deadZone: needed * 0.5)
            return
        }
        if ListRepeater.shared.active {
            ListRepeater.shared.push = holdPush(vy, deadZone: needed * 0.5)
            return
        }
        guard hypot(c.x - holdAnchor.x, c.y - holdAnchor.y) > 0.012 else { return }
        holdAnchor = c
        holdCheck?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self = self, self.touching, self.maxFingers == 1,
                  (Engine.shared.mode == .remote && !anyPanelOpen) || BigScreen.shared.seeksOnSwipe,
                  let p = self.lastPoint else { return }
            let vx = p.x - self.startPoint.x, vy = p.y - self.startPoint.y
            if s.holdToSeek, abs(vx) >= needed, abs(vx) > abs(vy) * 1.5 {
                self.suppressTap = true
                Scrubber.shared.start(push: holdPush(vx, deadZone: needed * 0.5))
            } else if s.holdToRepeat, abs(vy) >= needed, abs(vy) > abs(vx) * 1.5 {
                self.suppressTap = true
                ListRepeater.shared.start(push: holdPush(vy, deadZone: needed * 0.5))
            }
        }
        holdCheck = w
        // Already stepping up/down as you slide: carry straight on when you rest, without the usual wait
        let delay = liveSteps > 0 ? 0.15 : max(0.15, s.seekHoldDelay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    private var lastFrameTime: TimeInterval = 0
    private var prevEndTime: TimeInterval = 0     // when the previous touch lifted (frame time)
    private var navAccum = CGPoint.zero
    private var navMoved = false
    private var sideUsed = false

    // MARK: edge and corner gestures (Trackpad mode; the Spaces swipe works in every mode)

    private enum EdgeState: Equatable {
        case idle
        case pending([EdgeGesture])     // finger landed in a gesture area: waiting to see which way it moves
        case slider(EdgeGesture)        // scrolling / volume with one finger, until you lift
        case swipe(EdgeGesture)         // runs its action when you lift
        case done                       // already ran (rest-your-finger): ignore the rest of this touch
    }
    private var edge: EdgeState = .idle
    private var sliderAccum: CGFloat = 0
    private var scrollRemainder = CGPoint.zero
    private var velocity = CGPoint.zero           // recent scroll speed, for momentum
    private var momentum: Timer?

    private func beginEdge(at c: CGPoint, fingers: Int, s: Settings) -> EdgeState {
        guard fingers == 1, !anyPanelOpen else { return .idle }
        // Only the Spaces swipe works in Remote and Scroll mode; the other edge gestures are for Trackpad mode
        let trackpad = Engine.shared.mode == .trackpad
        let size = CGFloat(s.edgeZoneSize)
        var hits: [EdgeGesture] = !s.edgeGesturesOn ? [] : s.edgeGestures.filter { $0.enabled && (trackpad || $0.motion == .spaceSwipe) && $0.zone.contains(c, size: $0.zoneSize(size)) }
        // Remote mode: slide up and down the left edge for the volume
        if Engine.shared.mode == .remote && s.remoteVolumeEdge && c.x < CGFloat(s.remoteVolumeEdgeWidth)
            && c.y <= 1 - (s.edgeGestures.first(where: { $0.enabled && $0.motion == .spaceSwipe })?.zoneSize(size) ?? 0) {   // leave the Spaces strip alone
            hits.append(EdgeGesture(zone: .leftEdge, motion: .volumeSlider, reversed: s.remoteVolumeReverse))
        }
        guard !hits.isEmpty else { return .idle }
        // corners first, then list order
        return .pending(hits.filter { $0.zone.isCorner } + hits.filter { !$0.zone.isCorner })
    }

    /// Returns true when an edge gesture is using this movement (so the pointer stays put).
    private func edgeMoved(to c: CGPoint, dx: CGFloat, dy: CGFloat, time: TimeInterval, s: Settings) -> Bool {
        switch edge {
        case .idle: return false
        case .done, .swipe: return true
        case .slider(let g):
            slide(g, dx: dx, dy: dy, s: s)
            return true
        case .pending(let candidates):
            let v = CGPoint(x: c.x - startPoint.x, y: c.y - startPoint.y)
            // A sideways or up/down slide is recognised after a very short movement, so sliders respond straight away
            if hypot(v.x, v.y) < 0.016 {
                if time - startTime >= s.holdTime, let g = candidates.first(where: { $0.motion == .hold }) {
                    edge = .done; suppressTap = true
                    Engine.shared.runGesture(g)
                    return true
                }
                // Only wait (hold the pointer still) if a movement or rest gesture could still start here
                return candidates.contains { $0.motion != .tap }
            }
            if let g = candidates.first(where: { $0.motion.matches(v) }) {
                suppressTap = true
                if g.motion.isSlider {
                    edge = .slider(g); sliderAccum = 0; scrollRemainder = .zero; velocity = .zero
                    if g.motion == .spaceSwipe { DockSwipe.begin() }
                    if g.motion == .volumeSlider { SmoothVolume.begin() }
                    slide(g, dx: v.x, dy: v.y, s: s)
                } else {
                    edge = .swipe(g)
                }
                return true
            }
            if candidates.contains(where: { $0.motion == .tap }) { return false }   // keep a tap possible
            edge = .idle                                                           // ordinary pointer movement
            return false
        }
    }

    private func slide(_ g: EdgeGesture, dx rawDX: CGFloat, dy rawDY: CGFloat, s: Settings) {
        // "Reverse direction" on this gesture flips the movement
        let flip: CGFloat = g.reversed == true ? -1 : 1
        let dx = rawDX * flip, dy = rawDY * flip
        switch g.motion {
        case .spaceSwipe:
            DockSwipe.move(dx)
        case .scrollVertical, .scrollHorizontal:
            let sign: CGFloat = s.naturalScroll ? 1 : -1
            let k = 2400 * CGFloat(s.edgeScrollSpeed) * CGFloat(s.scrollSpeed) * sign
            let px = g.motion == .scrollHorizontal ? -dx * k : 0
            let py = g.motion == .scrollVertical ? dy * k : 0
            velocity = CGPoint(x: velocity.x * 0.6 + px * 0.4, y: velocity.y * 0.6 + py * 0.4)
            emitScroll(px, py)
        case .volumeSlider:
            // Smooth: the whole height of the glass is about 60% (less or more with the sensitivity setting)
            SmoothVolume.change(by: Double(dy) * 60 * s.edgeVolumeSpeed)
        default:
            break
        }
    }

    /// Scroll by fractional pixels, carrying the leftover so slow slides still scroll smoothly.
    private func emitScroll(_ px: CGFloat, _ py: CGFloat) {
        scrollRemainder.x += px; scrollRemainder.y += py
        let ix = scrollRemainder.x.rounded(.towardZero), iy = scrollRemainder.y.rounded(.towardZero)
        scrollRemainder.x -= ix; scrollRemainder.y -= iy
        if ix != 0 || iy != 0 { Input.scroll(dx: Int32(ix), dy: Int32(iy)) }
    }

    /// After a quick edge scroll, keep gliding and slow down, like a real trackpad.
    private func startMomentum() {
        stopMomentum()
        guard hypot(velocity.x, velocity.y) > 4 else { return }
        momentum = Timer.common(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            self.velocity.x *= 0.93; self.velocity.y *= 0.93
            if hypot(self.velocity.x, self.velocity.y) < 0.6 { self.stopMomentum(); return }
            self.emitScroll(self.velocity.x, self.velocity.y)
        }
    }

    private func stopMomentum() { momentum?.invalidate(); momentum = nil }

    private func finishSpaceSwipe(_ state: EdgeState) {
        if case .slider(let g) = state, g.motion == .spaceSwipe { DockSwipe.end() }
    }
}
