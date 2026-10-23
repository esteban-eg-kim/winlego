import AppKit
import WinlegoCore

/// Ties the drag monitor to the overlay and the zone manager: show zones while the
/// trigger is held during a window drag, and hand the drop to the manager.
@MainActor
final class DragCoordinator {
    private unowned let manager: ZoneManager
    private let monitor = DragMonitor()
    private let overlay = ZoneOverlay()

    init(manager: ZoneManager) {
        self.manager = manager
        monitor.onDrag = { [weak self] window, point, active in self?.dragged(window, at: point, active: active) }
        monitor.onDrop = { [weak self] window, point, active in self?.dropped(window, at: point, active: active) }
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

    private func dragged(_ window: AXWindow, at point: CGPoint, active: Bool) {
        guard active else { overlay.hide(); return }
        if !overlay.isVisible {
            overlay.show(screens: manager.screens,
                         zones: { manager.zoneFrames(on: $0) },
                         names: { manager.layout(for: $0).zones.map(\.name) })
        }
        overlay.highlight(at: point)
    }

    private func dropped(_ window: AXWindow?, at point: CGPoint, active: Bool) {
        var drop: Placement?
        if overlay.isVisible, active {
            overlay.highlight(at: point)
            drop = overlay.highlighted
        }
        overlay.hide()
        manager.mouseUp(dragged: window, drop: drop)
    }
}
