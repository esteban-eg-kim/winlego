import AppKit
import os
import WinlegoCore

/// Development aid, off unless `defaults write io.github.esteban-eg-kim.winlego devCommands -bool YES`.
/// A shell without Accessibility access of its own can then drive placement by posting a
/// distributed notification named `io.github.esteban-eg-kim.winlego.command` whose object
/// is one of:
///
///     place <bundleID> <display#> <zone#>   first placeable window of the app → zone
///     span <bundleID> <display#> <z1,z2,…>   first window of the app → merged zones
///     release <bundleID>                     drop its assignment
///     layout <display#> <layoutID>           pick a preset for a display
///     remember <bundleID>                    add a rule from where its window is now
///     nudge <bundleID> <dx> <dy>             move its window as if the app did it itself
///     ratio <display#> <path|root> <r>       move a divider for now (what a boundary drag does)
///     savelayout <display#>                  keep the dragged proportions (the prompt's Save)
///     arrange                                apply all rules
///     dump                                   write displays, windows and assignments to dev-dump.txt
///
/// Display numbers follow `ZoneManager.orderedScreens` (left to right), 1-based like the menu.
@MainActor
final class DevCommands {
    static let notification = Notification.Name("io.github.esteban-eg-kim.winlego.command")
    static var dumpURL: URL { ConfigStore.url.deletingLastPathComponent().appendingPathComponent("dev-dump.txt") }

    private let model: AppModel
    private let log = Logger(subsystem: Geometry.bundleID, category: "dev")
    private var observer: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        guard UserDefaults.standard.bool(forKey: "devCommands"), observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(forName: DevCommands.notification, object: nil, queue: .main) { [weak self] note in
            let line = note.object as? String ?? ""
            MainActor.assumeIsolated { self?.run(line) }
        }
        log.info("dev commands enabled")
    }

    private func run(_ line: String) {
        let parts = line.split(separator: " ").map(String.init)
        let manager = model.manager
        log.info("command: \(line, privacy: .public)")
        switch parts.first {
        case "place" where parts.count == 4:
            guard let window = firstWindow(of: parts[1]), let screen = screen(parts[2]), let zone = Int(parts[3]) else { return fail(line) }
            manager.place(window, at: Placement(displayID: screen.id, zone: zone - 1))
        case "span" where parts.count == 4:
            guard let window = firstWindow(of: parts[1]), let screen = screen(parts[2]) else { return fail(line) }
            let zones = parts[3].split(separator: ",").compactMap { Int($0) }.map { $0 - 1 }
            manager.place(window, at: Placement(displayID: screen.id, zones: zones))
        case "release" where parts.count == 2:
            guard let window = firstWindow(of: parts[1]), let key = window.key else { return fail(line) }
            manager.release(key, reason: "dev command")
        case "layout" where parts.count == 3:
            guard let screen = screen(parts[1]), model.config.layout(id: parts[2]) != nil else { return fail(line) }
            model.setLayout(parts[2], for: screen)
        case "remember" where parts.count == 2:
            guard let window = firstWindow(of: parts[1]) else { return fail(line) }
            window.raise()
            NSRunningApplication(processIdentifier: window.pid)?.activate()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                self.model.rememberFocused()
            }
        case "nudge" where parts.count == 4:
            // Moves the window behind winlego's back, the way an app restoring its own
            // position would; the tracker sees it as any other external move.
            guard let window = firstWindow(of: parts[1]), let frame = window.frame,
                  let dx = Double(parts[2]), let dy = Double(parts[3]) else { return fail(line) }
            window.setFrame(frame.offsetBy(dx: dx, dy: dy))
        case "ratio" where parts.count == 4:
            // ratio <display#> <path, e.g. "root" or "1,0"> <0.1…0.9>: what dragging a divider does.
            guard let screen = screen(parts[1]), let ratio = Double(parts[3]) else { return fail(line) }
            let path: NodePath = parts[2] == "root" ? [] : parts[2].split(separator: ",").compactMap { Int($0) }
            manager.setSessionRatio(ratio, at: path, on: screen)
        case "savelayout" where parts.count == 2:
            guard let screen = screen(parts[1]) else { return fail(line) }
            manager.saveSessionLayout(for: screen)
        case "simdrag" where parts.count >= 4:
            // simdrag <bundleID> <toX> <toY> [shift,option,control,command]: drags the app's
            // first window by its title bar with synthetic mouse events, modifiers held.
            guard let window = firstWindow(of: parts[1]), let frame = window.frame,
                  let x = Double(parts[2]), let y = Double(parts[3]) else { return fail(line) }
            var flags: CGEventFlags = []
            for name in (parts.count > 4 ? parts[4] : "").split(separator: ",") {
                switch name {
                case "shift": flags.insert(.maskShift)
                case "option": flags.insert(.maskAlternate)
                case "control": flags.insert(.maskControl)
                case "command": flags.insert(.maskCommand)
                default: break
                }
            }
            let start = CGPoint(x: frame.midX, y: frame.minY + 12)
            Task { @MainActor in
                await DevCommands.simulateDrag(from: start, to: CGPoint(x: x, y: y), flags: flags)
                self.log.info("simdrag done")
            }
        case "hotkey" where parts.count == 3:
            // hotkey <bundleID> <action>: bring the app forward, then act as if the shortcut was pressed.
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: parts[1]).first,
                  let key = HotKeyCenter.Key(rawValue: parts[2]) else { return fail(line) }
            app.activate()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                let focused = AXWindow.focused()
                self.log.info("focused: \(focused?.title ?? "nil", privacy: .public)")
                self.model.hotKey(key)
            }
        case "arrange":
            manager.arrangeAll()
        case "dump":
            dump()
        default:
            fail(line)
        }
    }

    /// Posts a mouse-down, a trail of drags, and a mouse-up to the HID event tap.
    static func simulateDrag(from start: CGPoint, to end: CGPoint, flags: CGEventFlags, steps: Int = 25) async {
        var flags = flags
        func post(_ type: CGEventType, _ point: CGPoint) {
            guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
        CGWarpMouseCursorPosition(start)
        try? await Task.sleep(for: .milliseconds(80))
        // Press without ⌃ (that would be a right-click), add it once the drag is under way.
        let downFlags = flags
        flags.remove(.maskControl)
        post(.leftMouseDown, start)
        flags = downFlags
        try? await Task.sleep(for: .milliseconds(80))
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
            try? await Task.sleep(for: .milliseconds(30))
        }
        try? await Task.sleep(for: .milliseconds(150))
        post(.leftMouseUp, end)
    }

    private func fail(_ line: String) {
        log.error("bad command: \(line, privacy: .public)")
    }

    private func screen(_ number: String) -> ScreenInfo? {
        guard let n = Int(number) else { return nil }
        let ordered = model.manager.orderedScreens
        return ordered.indices.contains(n - 1) ? ordered[n - 1] : nil
    }

    private func firstWindow(of bundleID: String) -> AXWindow? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        return AXWindow.windows(of: app.processIdentifier).first(where: \.isPlaceable)
    }

    private func dump() {
        let manager = model.manager
        var out = "displays (ordered):\n"
        for (i, screen) in manager.orderedScreens.enumerated() {
            out += "  \(i + 1). \(screen.title) id=\(screen.id) frame=\(screen.frame) visible=\(screen.visibleFrame) layout=\(manager.layout(for: screen).id)\n"
            for (z, frame) in manager.zoneFrames(on: screen).enumerated() {
                out += "       zone \(z + 1) \(manager.layout(for: screen).zones[z].name): \(frame)\n"
            }
        }
        out += "assignments:\n"
        for (key, placement) in manager.assignments {
            out += "  \(key) → \(placement.displayID.prefix(8))/\(placement.zones.map { String($0 + 1) }.joined(separator: "+"))\n"
        }
        out += "windows:\n"
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            for window in AXWindow.windows(of: app.processIdentifier) where window.isStandard {
                let key = window.key.map(String.init(describing:)) ?? "-"
                out += "  \(app.bundleIdentifier ?? "?") [\(key)] '\(window.title ?? "")' \(window.frame.map { "\($0)" } ?? "?")\(window.isMinimized ? " min" : "")\(window.isFullscreen ? " fs" : "")\n"
            }
        }
        do {
            try FileManager.default.createDirectory(at: DevCommands.dumpURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try out.write(to: DevCommands.dumpURL, atomically: true, encoding: .utf8)
        } catch {
            log.error("dump failed: \(error)")
        }
    }
}
