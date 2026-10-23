import AppKit
import WinlegoCore

/// Resize zones by dragging the boundary between two placed windows, as Windows does.
///
/// A global mouse-moved monitor watches for the cursor nearing a divider that has placed
/// windows on both sides. A thin, nearly invisible panel is then laid over that segment:
/// it shows the resize cursor, takes the click (so the apps underneath do not), and
/// drives the drag. Windows follow live; the layout change stays in memory until the
/// prompt that appears on release is answered with Save.
@MainActor
final class DividerResizer {
    struct Grab: Equatable {
        let screen: ScreenInfo
        let divider: Divider
        /// Quartz coordinates; zero width (vertical line) or zero height.
        let line: CGRect
        var isVertical: Bool { line.width == 0 }
    }

    static let grabDistance: CGFloat = 8
    private static let stripWidth: CGFloat = 18

    private unowned let manager: ZoneManager
    private var moveMonitor: Any?
    private var panel: HandlePanel?
    private var active: Grab?
    private var dragging = false
    private var lastApply = 0.0
    private var cache: (at: Double, grabs: [Grab])?
    private var prompt: SaveLayoutPrompt?

    init(manager: ZoneManager) {
        self.manager = manager
    }

    func start() {
        guard moveMonitor == nil else { return }
        moveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        }
    }

    func stop() {
        if let moveMonitor { NSEvent.removeMonitor(moveMonitor) }
        moveMonitor = nil
        hide()
        prompt?.close()
        prompt = nil
    }

    /// Something changed under the dividers (a placement, a layout); look again soon.
    func invalidate() { cache = nil }

    // MARK: - Hover

    private func grabs() -> [Grab] {
        let now = Date().timeIntervalSinceReferenceDate
        if let cache, now - cache.at < 0.3 { return cache.grabs }
        let grabs = manager.grabbableDividers().map { Grab(screen: $0.screen, divider: $0.divider, line: $0.line) }
        cache = (now, grabs)
        return grabs
    }

    private func mouseMoved() {
        guard !dragging else { return }
        let point = Screens.quartzMouseLocation()
        if let grab = grabs().first(where: { DividerResizer.isNear(point, $0.line) }) {
            show(grab)
        } else if active != nil {
            hide()
        }
    }

    private static func isNear(_ point: CGPoint, _ line: CGRect) -> Bool {
        if line.width == 0 {
            return abs(point.x - line.minX) <= grabDistance && point.y >= line.minY && point.y <= line.maxY
        }
        return abs(point.y - line.minY) <= grabDistance && point.x >= line.minX && point.x <= line.maxX
    }

    private func show(_ grab: Grab) {
        if active == grab { return }
        active = grab
        let panel = self.panel ?? makePanel()
        panel.handleView.isVertical = grab.isVertical
        panel.setFrame(DividerResizer.cocoaStrip(for: grab.line), display: true)
        panel.orderFrontRegardless()
        // The panel's own tracking takes over once the cursor is inside it; until then,
        // set the cursor ourselves so it flips the moment the boundary is in reach.
        (grab.isVertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
    }

    private func hide() {
        guard active != nil else { return }
        active = nil
        panel?.orderOut(nil)
        NSCursor.arrow.set()
    }

    private static func cocoaStrip(for line: CGRect) -> NSRect {
        let strip = line.width == 0
            ? line.insetBy(dx: -stripWidth / 2, dy: 0)
            : line.insetBy(dx: 0, dy: -stripWidth / 2)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return Geometry.flip(strip, primaryHeight: primaryHeight)
    }

    private func makePanel() -> HandlePanel {
        let panel = HandlePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.handleView.resizer = self
        self.panel = panel
        return panel
    }

    // MARK: - Drag (called by the handle view)

    fileprivate func cursorLeft() {
        if !dragging { hide() }
    }

    fileprivate func dragBegan() {
        dragging = true
        prompt?.close()
        prompt = nil
    }

    fileprivate func dragMoved(to point: CGPoint) {
        guard dragging, let grab = active else { return }
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastApply > 1.0 / 30 else { return }
        lastApply = now
        let region = grab.divider.region.resolved(in: grab.screen.visibleFrame)
        let ratio = grab.isVertical
            ? (point.x - region.minX) / max(region.width, 1)
            : (point.y - region.minY) / max(region.height, 1)
        manager.setSessionRatio(ratio, at: grab.divider.path, on: grab.screen)
        // Follow the divider to where it is now.
        if let divider = manager.layout(for: grab.screen).dividers.first(where: { $0.path == grab.divider.path }) {
            let line = divider.line.resolved(in: grab.screen.visibleFrame)
            active = Grab(screen: grab.screen, divider: divider, line: line)
            panel?.setFrame(DividerResizer.cocoaStrip(for: line), display: true)
        }
        invalidate()
    }

    fileprivate func dragEnded() {
        guard dragging else { return }
        dragging = false
        guard let grab = active, manager.hasUnsavedLayout(for: grab.screen) else { return }
        let prompt = SaveLayoutPrompt(displayName: grab.screen.name, near: Screens.quartzMouseLocation()) { [weak self] save in
            guard let self else { return }
            if save { manager.saveSessionLayout(for: grab.screen) }
            self.prompt = nil
        }
        self.prompt = prompt
        prompt.show()
    }
}

/// A borderless, non-activating panel whose only job is to sit on a divider.
private final class HandlePanel: NSPanel {
    let handleView = HandleView()

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        contentView = handleView
    }
}

private final class HandleView: NSView {
    weak var resizer: DividerResizer?
    var isVertical = true { didSet { needsDisplay = true; window?.invalidateCursorRects(for: self) } }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var cursor: NSCursor { isVertical ? .resizeLeftRight : .resizeUpDown }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // `.inVisibleRect` keeps the area in step with the panel, whose frame changes
        // after the view is created and on every drag.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate], owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { cursor.set() }
    override func mouseEntered(with event: NSEvent) { cursor.set() }
    override func mouseMoved(with event: NSEvent) { cursor.set() }

    override func mouseExited(with event: NSEvent) {
        MainActor.assumeIsolated { resizer?.cursorLeft() }
    }

    override func mouseDown(with event: NSEvent) {
        MainActor.assumeIsolated { resizer?.dragBegan() }
    }

    override func mouseDragged(with event: NSEvent) {
        (isVertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
        MainActor.assumeIsolated { resizer?.dragMoved(to: Screens.quartzMouseLocation()) }
    }

    override func mouseUp(with event: NSEvent) {
        MainActor.assumeIsolated { resizer?.dragEnded() }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Almost invisible fill so the whole strip takes clicks.
        NSColor.black.withAlphaComponent(0.01).setFill()
        bounds.fill()
        let accent = NSColor.controlAccentColor
        // A bold bar with a light outline so it reads on any background, and a grip in the middle.
        let bar = isVertical
            ? NSRect(x: bounds.midX - 3, y: bounds.minY + 4, width: 6, height: bounds.height - 8)
            : NSRect(x: bounds.minX + 4, y: bounds.midY - 3, width: bounds.width - 8, height: 6)
        let barPath = NSBezierPath(roundedRect: bar, xRadius: 3, yRadius: 3)
        NSColor.white.withAlphaComponent(0.9).setStroke()
        barPath.lineWidth = 2
        barPath.stroke()
        accent.setFill()
        barPath.fill()
        let grip = isVertical
            ? NSRect(x: bounds.midX - 5, y: bounds.midY - 28, width: 10, height: 56)
            : NSRect(x: bounds.midX - 28, y: bounds.midY - 5, width: 56, height: 10)
        let gripPath = NSBezierPath(roundedRect: grip, xRadius: 5, yRadius: 5)
        NSColor.white.setFill()
        gripPath.fill()
        accent.setStroke()
        gripPath.lineWidth = 2
        gripPath.stroke()
    }
}

/// "Save this layout?" after a divider drag.
@MainActor
final class SaveLayoutPrompt {
    private let panel: NSPanel
    private let decide: (Bool) -> Void
    private var timer: Timer?

    init(displayName: String, near point: CGPoint, decide: @escaping (Bool) -> Void) {
        self.decide = decide
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 76), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        let effect = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        panel.contentView = effect

        let label = NSTextField(labelWithString: "Save this layout for \(displayName)?")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.frame = NSRect(x: 16, y: 44, width: 268, height: 20)
        label.lineBreakMode = .byTruncatingTail
        effect.addSubview(label)

        let save = NSButton(title: "Save", target: self, action: #selector(saveTapped))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.frame = NSRect(x: 196, y: 10, width: 88, height: 28)
        effect.addSubview(save)

        let later = NSButton(title: "Not Now", target: self, action: #selector(laterTapped))
        later.bezelStyle = .rounded
        later.frame = NSRect(x: 100, y: 10, width: 92, height: 28)
        effect.addSubview(later)

        // Just above the cursor, kept on screen.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var origin = NSPoint(x: point.x - 150, y: primaryHeight - point.y + 24)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: point.x, y: primaryHeight - point.y)) }) {
            origin.x = min(max(origin.x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - 308)
            origin.y = min(max(origin.y, screen.visibleFrame.minY + 8), screen.visibleFrame.maxY - 84)
        }
        panel.setFrameOrigin(origin)
    }

    func show() {
        panel.orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(save: false) }
        }
    }

    func close() { finish(save: false) }

    @objc private func saveTapped() { finish(save: true) }
    @objc private func laterTapped() { finish(save: false) }

    private func finish(save: Bool) {
        guard panel.isVisible else { return }
        timer?.invalidate()
        panel.orderOut(nil)
        decide(save)
    }
}
