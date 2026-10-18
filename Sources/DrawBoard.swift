// DrawBoard.swift — draw on top of everything, like a presenter's pen.
// Turn it on with the “Draw on screen” action. Then, in Trackpad mode, press the glass and slide to
// draw a line; lift to end it. Menu clears the drawing. Press the Draw button again to put it away.
// It follows the system pointer, so it works whatever is on screen underneath.
import AppKit

final class DrawView: NSView {
    var strokes: [(color: NSColor, width: CGFloat, points: [NSPoint])] = []
    var live: [NSPoint] = []
    var liveColor = NSColor.systemYellow
    var liveWidth: CGFloat = 6

    override func draw(_ dirtyRect: NSRect) {
        func drawStroke(_ pts: [NSPoint], _ color: NSColor, _ w: CGFloat) {
            guard pts.count > 1 else {
                // a tap leaves a dot
                if let p = pts.first { color.setFill(); NSBezierPath(ovalIn: NSRect(x: p.x - w/2, y: p.y - w/2, width: w, height: w)).fill() }
                return
            }
            let path = NSBezierPath()
            path.lineWidth = w; path.lineCapStyle = .round; path.lineJoinStyle = .round
            path.move(to: pts[0])
            for p in pts.dropFirst() { path.line(to: p) }
            color.setStroke(); path.stroke()
        }
        for s in strokes { drawStroke(s.points, s.color, s.width) }
        drawStroke(live, liveColor, liveWidth)
    }
}

final class DrawBoard {
    static let shared = DrawBoard()
    private(set) var active = false
    private var drawing = false
    private var windows: [(NSWindow, DrawView)] = []
    private var timer: Timer?

    @discardableResult
    func toggle() -> Bool {
        active ? hide() : show()
        return active
    }

    private func show() {
        active = true
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false; w.backgroundColor = .clear; w.ignoresMouseEvents = true   // we drive it from the pointer ourselves
            w.level = .screenSaver; w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let v = DrawView(frame: NSRect(origin: .zero, size: screen.frame.size))
            v.liveColor = SpotPalette.color(ConfigStore.shared.settings.spotColor)
            w.contentView = v
            w.setFrame(screen.frame, display: false)
            w.orderFrontRegardless()
            windows.append((w, v))
        }
        // Sample the pointer often, so lines are smooth
        timer = Timer.common(withTimeInterval: 1.0 / 90, repeats: true) { [weak self] _ in self?.sample() }
    }

    private func hide() {
        active = false; drawing = false
        timer?.invalidate(); timer = nil
        windows.forEach { $0.0.orderOut(nil) }
        windows.removeAll()
    }

    func penDown() {
        drawing = true
        let color = SpotPalette.color(ConfigStore.shared.settings.spotColor)
        for (_, v) in windows { v.live = []; v.liveColor = color }
        sample()
    }

    func penUp() {
        drawing = false
        for (_, v) in windows where !v.live.isEmpty {
            v.strokes.append((v.liveColor, v.liveWidth, v.live)); v.live = []; v.needsDisplay = true
        }
    }

    func clear() { for (_, v) in windows { v.strokes.removeAll(); v.live = []; v.needsDisplay = true } }

    private func sample() {
        guard drawing else { return }
        let m = NSEvent.mouseLocation
        for (w, v) in windows where w.frame.contains(m) {
            v.live.append(NSPoint(x: m.x - w.frame.minX, y: m.y - w.frame.minY))
            v.needsDisplay = true
        }
    }
}
