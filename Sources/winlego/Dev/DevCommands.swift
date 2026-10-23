import AppKit
import os
import WinlegoCore

/// Development aid, off unless `defaults write io.github.esteban-eg-kim.winlego devCommands -bool YES`.
/// A shell without Accessibility access of its own can then drive placement by posting a
/// distributed notification named `io.github.esteban-eg-kim.winlego.command` whose object
/// is one of:
///
///     place <bundleID> <display#> <zone#>   first placeable window of the app → zone
///     release <bundleID>                     drop its assignment
///     layout <display#> <layoutID>           pick a preset for a display
///     remember <bundleID>                    add a rule from where its window is now
///     nudge <bundleID> <dx> <dy>             move its window as if the app did it itself
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
        case "release" where parts.count == 2:
            guard let window = firstWindow(of: parts[1]), let key = window.key else { return fail(line) }
            manager.release(key, reason: "dev command")
        case "layout" where parts.count == 3:
            guard let screen = screen(parts[1]), Presets.layout(id: parts[2]) != nil else { return fail(line) }
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
        case "arrange":
            manager.arrangeAll()
        case "dump":
            dump()
        default:
            fail(line)
        }
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
            out += "  \(key) → \(placement.displayID.prefix(8))/\(placement.zone + 1)\n"
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
