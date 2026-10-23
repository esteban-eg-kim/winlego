import AppKit
import WinlegoCore

/// Translucent zone outlines over every display while a window is dragged.
@MainActor
final class ZoneOverlay {
    private var windows: [String: (window: NSWindow, view: ZoneOverlayView, screen: ScreenInfo, zones: [CGRect])] = [:]
    private(set) var isVisible = false
    private(set) var highlighted: Placement?
    /// How far apart two zones may be and still count as neighbours: the configured gap
    /// plus a little, so zones separated only by spacing can be merged.
    var adjacencyTolerance: CGFloat = 2

    /// Shows the zones of every display. `zones(screen)` gives absolute Quartz frames.
    func show(screens: [ScreenInfo], zones: (ScreenInfo) -> [CGRect], names: (ScreenInfo) -> [String]) {
        let wanted = Set(screens.map(\.id))
        for id in windows.keys where !wanted.contains(id) {
            windows.removeValue(forKey: id)?.window.orderOut(nil)
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        for screen in screens {
            let frames = zones(screen)
            let cocoaFrame = Geometry.flip(screen.frame, primaryHeight: primaryHeight)
            let entry = windows[screen.id] ?? makeWindow()
            entry.window.setFrame(cocoaFrame, display: false)
            entry.view.zones = frames.map { $0.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY) }
            entry.view.names = names(screen)
            entry.view.highlighted = []
            entry.window.orderFrontRegardless()
            windows[screen.id] = (entry.window, entry.view, screen, frames)
        }
        isVisible = true
        highlighted = nil
    }

    /// Lights up the zone under the cursor and remembers it as the drop target. With
    /// `span`, zones the cursor visits accumulate (on one display, each touching the
    /// selection so far) and the drop target becomes their union. A merged selection
    /// survives letting go of the key while the cursor stays inside it, so releasing the
    /// modifier a moment before the mouse button does not lose it.
    func highlight(at point: CGPoint, span: Bool = false) {
        guard let (id, entry) = windows.first(where: { $0.value.screen.frame.contains(point) }),
              let index = Geometry.zoneIndex(containing: point, in: entry.zones) else {
            if !span { clearHighlight() }
            return
        }
        var selection: Set<Int> = [index]
        if let current = highlighted, current.displayID == id {
            if span {
                let union = current.zones.map { entry.zones[$0] }.reduce(entry.zones[current.zone]) { $0.union($1) }
                selection = Set(current.zones)
                if Geometry.areAdjacent(union, entry.zones[index], tolerance: adjacencyTolerance) { selection.insert(index) }
            } else if current.isSpan, current.zones.contains(index) {
                selection = Set(current.zones)
            }
        }
        for (otherID, other) in windows where otherID != id && !other.view.highlighted.isEmpty {
            other.view.highlighted = []
        }
        if entry.view.highlighted != selection { entry.view.highlighted = selection }
        highlighted = Placement(displayID: id, zones: selection)
    }

    private func clearHighlight() {
        for entry in windows.values where !entry.view.highlighted.isEmpty { entry.view.highlighted = [] }
        highlighted = nil
    }

    func hide() {
        guard isVisible else { return }
        for entry in windows.values { entry.window.orderOut(nil) }
        isVisible = false
        highlighted = nil
    }

    private func makeWindow() -> (window: NSWindow, view: ZoneOverlayView, screen: ScreenInfo, zones: [CGRect]) {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        let view = ZoneOverlayView()
        window.contentView = view
        return (window, view, ScreenInfo(id: "", name: "", frame: .zero, visibleFrame: .zero, pixelSize: .zero), [])
    }
}

/// Draws the zones of one display. Coordinates are local to the display, origin top-left.
final class ZoneOverlayView: NSView {
    var zones: [CGRect] = [] { didSet { needsDisplay = true } }
    var names: [String] = [] { didSet { needsDisplay = true } }
    var highlighted: Set<Int> = [] { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        for (index, zone) in zones.enumerated() {
            let rect = zone.insetBy(dx: 6, dy: 6)
            let path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
            let lit = highlighted.contains(index)
            (lit ? accent.withAlphaComponent(0.35) : NSColor.white.withAlphaComponent(0.12)).setFill()
            path.fill()
            (lit ? accent : NSColor.white.withAlphaComponent(0.7)).setStroke()
            path.lineWidth = lit ? 4 : 2
            path.stroke()

            let label = "\(index + 1)" + (names.indices.contains(index) ? "  \(names[index])" : "")
            let size: CGFloat = min(max(rect.height / 10, 18), 44)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(lit ? 1 : 0.85),
            ]
            let text = NSAttributedString(string: label, attributes: attributes)
            let textSize = text.size()
            let origin = NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2)
            let pill = NSRect(origin: origin, size: textSize).insetBy(dx: -14, dy: -8)
            NSColor.black.withAlphaComponent(0.45).setFill()
            NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
            text.draw(at: origin)
        }
    }
}
