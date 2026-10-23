import AppKit
import ApplicationServices
import WinlegoCore

/// Notices when the user drags a window of another app. On mouse down it finds the
/// window under the cursor through the Accessibility API; if that window's origin then
/// changes while the button is held, a drag is on.
@MainActor
final class DragMonitor {
    var trigger: DragTrigger = .shift

    /// A window is being dragged. The point is the cursor in Quartz coordinates; the flag
    /// says whether the trigger (⇧, ⌥ or "always") is active right now.
    var onDrag: ((AXWindow, CGPoint, Bool) -> Void)?
    /// The button went up. The window is the one that was being dragged, if any.
    var onDrop: ((AXWindow?, CGPoint, Bool) -> Void)?

    private var monitors: [Any] = []
    private var candidate: (window: AXWindow, origin: CGPoint)?
    private var dragging: AXWindow?

    func start() {
        guard monitors.isEmpty else { return }
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            let flags = event.modifierFlags
            MainActor.assumeIsolated { self?.mouseDragged(flags: flags) }
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            let flags = event.modifierFlags
            MainActor.assumeIsolated { self?.mouseUp(flags: flags) }
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let flags = event.modifierFlags
            MainActor.assumeIsolated { self?.flagsChanged(flags: flags) }
        } as Any)
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        candidate = nil
        dragging = nil
    }

    private func isActive(_ flags: NSEvent.ModifierFlags) -> Bool {
        switch trigger {
        case .shift: flags.contains(.shift)
        case .option: flags.contains(.option)
        case .always: true
        }
    }

    private func mouseDown() {
        dragging = nil
        candidate = nil
        let point = Screens.quartzMouseLocation()
        guard let window = DragMonitor.window(at: point), window.isPlaceable, let frame = window.frame else { return }
        candidate = (window, frame.origin)
    }

    private func mouseDragged(flags: NSEvent.ModifierFlags) {
        guard let candidate else { return }
        if dragging == nil {
            guard let frame = candidate.window.frame,
                  abs(frame.minX - candidate.origin.x) > 1 || abs(frame.minY - candidate.origin.y) > 1 else { return }
            dragging = candidate.window
        }
        if let dragging { onDrag?(dragging, Screens.quartzMouseLocation(), isActive(flags)) }
    }

    private func flagsChanged(flags: NSEvent.ModifierFlags) {
        // Pressing ⇧ halfway through a drag should bring the zones up right away.
        if let dragging { onDrag?(dragging, Screens.quartzMouseLocation(), isActive(flags)) }
    }

    private func mouseUp(flags: NSEvent.ModifierFlags) {
        let window = dragging
        dragging = nil
        candidate = nil
        onDrop?(window, Screens.quartzMouseLocation(), isActive(flags))
    }

    /// The window under a point, whichever app it belongs to.
    static func window(at point: CGPoint) -> AXWindow? {
        let system = AXUIElementCreateSystemWide()
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success, let hit else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(hit, &pid)
        guard pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(hit, kAXRoleAttribute as CFString, &role)
        if (role as? String) == kAXWindowRole { return AXWindow(element: hit, pid: pid) }
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(hit, kAXWindowAttribute as CFString, &window) == .success, let window else { return nil }
        return AXWindow(element: window as! AXUIElement, pid: pid)
    }
}
