import AppKit
import os
import WinlegoCore

/// Ties the drag monitor to the overlay and the zone manager: show zones while the
/// trigger is held during a window drag, and hand the drop to the manager.
@MainActor
final class DragCoordinator {
    private unowned let manager: ZoneManager
    private let monitor = DragMonitor()
    private let overlay = ZoneOverlay()
    private let log = Logger(subsystem: Geometry.bundleID, category: "drag")

    init(manager: ZoneManager) {
        self.manager = manager
        monitor.onDrag = { [weak self] window, point, mods in self?.dragged(window, at: point, mods: mods) }
        monitor.onDrop = { [weak self] window, point, mods in self?.dropped(window, at: point, mods: mods) }
    }

    var trigger: DragTrigger {
        get { monitor.trigger }
        set { monitor.trigger = newValue }
    }

    func start() { monitor.start() }

    func stop() {
        monitor.stop()
        overlay.hide()
    }

    private var spanWasDown = false

    private func dragged(_ window: AXWindow, at point: CGPoint, mods: DragMonitor.Modifiers) {
        if mods.span != spanWasDown {
            spanWasDown = mods.span
            log.info("merge key \(mods.span ? "down" : "up", privacy: .public); trigger active: \(mods.active)")
        }
        guard mods.active else { overlay.hide(); return }
        if !overlay.isVisible {
            overlay.adjacencyTolerance = CGFloat(manager.config.gap) + 2
            overlay.show(screens: manager.screens,
                         zones: { manager.zoneFrames(on: $0) },
                         names: { manager.layout(for: $0).zones.map { L($0.name) } })
        }
        let before = overlay.highlighted
        overlay.highlight(at: point, span: mods.span)
        if let now = overlay.highlighted, now != before, now.isSpan || before?.isSpan == true {
            log.info("merge selection: \(now.zones.map { String($0 + 1) }.joined(separator: "+"), privacy: .public)")
        }
    }

    private func dropped(_ window: AXWindow?, at point: CGPoint, mods: DragMonitor.Modifiers) {
        var drop: Placement?
        if overlay.isVisible, mods.active {
            overlay.highlight(at: point, span: mods.span)
            drop = overlay.highlighted
        }
        overlay.hide()
        manager.mouseUp(dragged: window, drop: drop)
    }
}
