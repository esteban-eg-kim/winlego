import AppKit
import os
import WinlegoCore

/// Puts windows into zones and keeps them there. Owns the window tracker and the
/// per-window enforcement state; the model feeds it config and displays.
@MainActor
final class ZoneManager {
    private let log = Logger(subsystem: Geometry.bundleID, category: "zones")
    private let tracker = WindowTracker()
    private let policy = EnforcementPolicy()

    private(set) var assignments: [WindowKey: Placement] = [:]
    private var states: [WindowKey: EnforcementPolicy.WindowState] = [:]
    /// The frame a window actually took after its last successful placement. Apps with a
    /// minimum size never match the zone exactly; this is what "in place" means for them.
    private var settledFrames: [WindowKey: CGRect] = [:]
    private var pendingRestores: [WindowKey: Task<Void, Never>] = [:]
    private var dragging: WindowKey?
    private var settleTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    var config = Config() { didSet { drag.trigger = config.dragTrigger } }
    var screens: [ScreenInfo] = []
    var enabled = true
    private lazy var drag = DragCoordinator(manager: self)
    private lazy var resizer = DividerResizer(manager: self)
    /// Divider drags live here until the user saves them; keyed by display.
    private var sessionLayouts: [String: Layout] = [:]
    /// A display's layout was saved after dragging a divider; the model persists it.
    var onLayoutEdited: ((ScreenInfo, Layout) -> Void)?

    var isRunning: Bool { tracker.isRunning }

    func start() {
        guard !tracker.isRunning else { return }
        tracker.onChange = { [weak self] window, change in self?.handle(window, change) }
        tracker.onAppQuit = { [weak self] pid in self?.forget(pid: pid) }
        tracker.start()
        drag.trigger = config.dragTrigger
        drag.start()
        resizer.start()
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reapplyAllAfterSettling() }
        })
        log.info("started; tracking \(self.tracker.apps.count) apps")
    }

    func stop() {
        tracker.stop()
        drag.stop()
        resizer.stop()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        pendingRestores.values.forEach { $0.cancel() }
        pendingRestores.removeAll()
    }

    // MARK: - Zones

    func screen(_ id: String) -> ScreenInfo? { screens.first { $0.id == id } }

    func layout(for screen: ScreenInfo) -> Layout {
        sessionLayouts[screen.id] ?? config.layout(for: screen.id, portrait: screen.isPortrait)
    }

    func zoneFrames(on screen: ScreenInfo) -> [CGRect] {
        layout(for: screen).frames(in: screen.visibleFrame, gap: config.gap)
    }

    /// A zone number past the end (the layout shrank) maps to the last zone.
    func targetFrame(for placement: Placement) -> CGRect? {
        guard let screen = screen(placement.displayID) else { return nil }
        let frames = zoneFrames(on: screen)
        guard let last = frames.indices.last else { return nil }
        return frames[min(placement.zone, last)]
    }

    // MARK: - Resizing zones by dragging a divider

    /// Dividers with placed windows on both sides, as absolute Quartz lines.
    func grabbableDividers() -> [(screen: ScreenInfo, divider: Divider, line: CGRect)] {
        var result: [(ScreenInfo, Divider, CGRect)] = []
        for screen in screens {
            let layout = layout(for: screen)
            let zones = layout.zones
            let occupied = Set(assignments.values.filter { $0.displayID == screen.id }.map { min($0.zone, zones.count - 1) })
            guard !occupied.isEmpty else { continue }
            for divider in layout.dividers {
                let firstSide = occupied.contains { zones[$0].path.starts(with: divider.path + [0]) }
                let secondSide = occupied.contains { zones[$0].path.starts(with: divider.path + [1]) }
                if firstSide && secondSide {
                    result.append((screen, divider, divider.line.resolved(in: screen.visibleFrame)))
                }
            }
        }
        return result
    }

    /// Moves one divider for now: windows on the display follow, nothing is saved yet.
    func setSessionRatio(_ ratio: Double, at path: NodePath, on screen: ScreenInfo) {
        sessionLayouts[screen.id] = layout(for: screen).settingRatio(ratio, at: path)
        replaceWindows(on: screen)
    }

    func hasUnsavedLayout(for screen: ScreenInfo) -> Bool { sessionLayouts[screen.id] != nil }

    /// Keeps the dragged proportions. A preset becomes a custom copy owned by that display;
    /// a custom layout is updated in place.
    func saveSessionLayout(for screen: ScreenInfo) {
        guard var layout = sessionLayouts.removeValue(forKey: screen.id) else { return }
        if !config.customLayouts.contains(where: { $0.id == layout.id }) {
            layout = Layout(id: "custom-\(screen.id.prefix(8).lowercased())", name: "\(layout.name) · \(screen.name)", root: layout.root)
        }
        config.upsert(layout)
        config.layoutByDisplay[screen.id] = layout.id
        onLayoutEdited?(screen, layout)
        log.info("saved adjusted layout \(layout.id, privacy: .public) for \(screen.name, privacy: .public)")
    }

    /// The user picked another layout for the display: forget any unsaved drag.
    func discardSessionLayout(for screen: ScreenInfo) {
        sessionLayouts[screen.id] = nil
    }

    private func replaceWindows(on screen: ScreenInfo) {
        for (key, placement) in assignments where placement.displayID == screen.id {
            guard let window = window(for: key), let target = targetFrame(for: placement) else { continue }
            if apply(target, to: window) { settledFrames[key] = window.frame }
        }
    }

    /// Display ordering for ⌃⌥↑/↓: left to right, then top to bottom.
    var orderedScreens: [ScreenInfo] {
        screens.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
    }

    /// The display showing most of a window.
    func screen(under frame: CGRect) -> ScreenInfo? {
        screens.max { $0.frame.overlapArea(with: frame) < $1.frame.overlapArea(with: frame) }
    }

    // MARK: - Placing

    func placement(of window: AXWindow) -> Placement? {
        window.key.flatMap { assignments[$0] }
    }

    /// Moves the window into the zone and remembers it there.
    @discardableResult
    func place(_ window: AXWindow, at placement: Placement) -> Bool {
        guard let key = window.key else {
            log.warning("cannot place '\(window.title ?? "?", privacy: .public)': no window number")
            return false
        }
        guard let target = targetFrame(for: placement) else { return false }
        pendingRestores.removeValue(forKey: key)?.cancel()
        assignments[key] = placement
        states[key] = states[key] ?? EnforcementPolicy.WindowState()
        let ok = apply(target, to: window)
        if ok { settledFrames[key] = window.frame }
        resizer.invalidate()
        log.info("place \(key, privacy: .public) '\(window.title ?? "", privacy: .public)' → \(placement.displayID.prefix(8), privacy: .public)/\(placement.zone) \(ok ? "ok" : "FAILED", privacy: .public)")
        return ok
    }

    func release(_ key: WindowKey, reason: String) {
        guard assignments.removeValue(forKey: key) != nil else { return }
        states[key] = nil
        settledFrames[key] = nil
        pendingRestores.removeValue(forKey: key)?.cancel()
        resizer.invalidate()
        log.info("release \(key, privacy: .public): \(reason, privacy: .public)")
    }

    /// Sets the frame and reports whether the window ended up at the zone's origin. Size
    /// may fall short when the app enforces a minimum; that still counts as placed.
    private func apply(_ target: CGRect, to window: AXWindow) -> Bool {
        guard window.setFrame(target), let frame = window.frame else { return false }
        return abs(frame.minX - target.minX) <= policy.tolerance && abs(frame.minY - target.minY) <= policy.tolerance
    }

    // MARK: - Commands

    func placeFocused(at placement: Placement) {
        guard let window = AXWindow.focused(), window.isPlaceable else { return }
        place(window, at: placement)
    }

    func releaseFocused() {
        guard let window = AXWindow.focused(), let key = window.key else { return }
        release(key, reason: "released by the user")
    }

    /// ⌃⌥←/→: the previous or next zone on the window's display, wrapping around. A window
    /// that is not in a zone yet starts from the zone it overlaps most.
    func moveFocused(by delta: Int) {
        guard let window = AXWindow.focused(), window.isPlaceable, let frame = window.frame else { return }
        if let current = placement(of: window), let screen = screen(current.displayID) {
            let count = layout(for: screen).zones.count
            place(window, at: Placement(displayID: screen.id, zone: Geometry.step(zone: current.zone, count: count, by: delta)))
        } else if let screen = screen(under: frame) {
            let zones = zoneFrames(on: screen)
            let zone = Geometry.bestZone(for: frame, in: zones) ?? (delta > 0 ? zones.count - 1 : 0)
            place(window, at: Placement(displayID: screen.id, zone: Geometry.step(zone: zone, count: zones.count, by: delta)))
        }
    }

    /// ⌃⌥↑/↓: the same zone number on the previous or next display.
    func moveFocusedToDisplay(by delta: Int) {
        guard let window = AXWindow.focused(), window.isPlaceable, let frame = window.frame else { return }
        let ordered = orderedScreens
        guard ordered.count > 1 else { return }
        let current = placement(of: window)
        let fromID = current?.displayID ?? screen(under: frame)?.id
        guard let index = ordered.firstIndex(where: { $0.id == fromID }) else { return }
        let next = ordered[Geometry.step(zone: index, count: ordered.count, by: delta)]
        let zone = min(current?.zone ?? 0, layout(for: next).zones.count - 1)
        place(window, at: Placement(displayID: next.id, zone: zone))
    }

    /// Every window that has a rule goes where the rule says.
    func arrangeAll() {
        var placed = 0
        for window in tracker.allWindows() where applyRules(to: window) { placed += 1 }
        log.info("arranged \(placed) windows by rule")
    }

    /// Applies the matching rule, if any.
    @discardableResult
    func applyRules(to window: AXWindow) -> Bool {
        guard let app = tracker.app(for: window.pid), let bundleID = app.bundleID,
              !config.excludedBundleIDs.contains(bundleID),
              let rule = Rules.match(config.rules, bundleID: bundleID, title: window.title) else { return false }
        let displayID = rule.displayID.flatMap { screen($0)?.id } ?? Screens.mainScreenID() ?? ""
        return place(window, at: Placement(displayID: displayID, zone: rule.zone))
    }

    /// A rule that sends the focused window's app to where the window is now.
    func ruleForFocused() -> Rule? {
        guard let window = AXWindow.focused(), window.isPlaceable, let frame = window.frame,
              let app = tracker.app(for: window.pid), let bundleID = app.bundleID else { return nil }
        let spot: Placement
        if let current = placement(of: window) {
            spot = current
        } else if let screen = screen(under: frame), let zone = Geometry.bestZone(for: frame, in: zoneFrames(on: screen)) {
            spot = Placement(displayID: screen.id, zone: zone)
            place(window, at: spot)
        } else {
            return nil
        }
        return Rule(bundleID: bundleID, appName: app.name, displayID: spot.displayID, zone: spot.zone)
    }

    /// Display or layout changes: wait for the system to settle, then put everything back.
    func reapplyAllAfterSettling(after seconds: Double = 1.5) {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.reapplyAll()
        }
    }

    func reapplyAll() {
        guard enabled else { return }
        var count = 0
        for (key, placement) in assignments {
            guard let window = window(for: key), let target = targetFrame(for: placement) else { continue }
            if apply(target, to: window) { settledFrames[key] = window.frame; count += 1 }
        }
        log.info("reapplied \(count) of \(self.assignments.count) assignments")
    }

    // MARK: - Enforcement

    private var now: Double { Date().timeIntervalSinceReferenceDate }
    private var mouseIsDown: Bool { NSEvent.pressedMouseButtons & 1 != 0 }

    private func handle(_ window: AXWindow, _ change: WindowTracker.Change) {
        guard enabled else { return }
        switch change {
        case .created:
            if window.isPlaceable { applyRules(to: window) }
        case .moved, .resized:
            enforce(window)
        case .focused:
            break
        case .destroyed:
            prune(pid: window.pid)
        }
    }

    private func enforce(_ window: AXWindow) {
        guard let key = window.key, let placement = assignments[key],
              let target = targetFrame(for: placement), let frame = window.frame else { return }
        let mouseDown = mouseIsDown
        if mouseDown { dragging = key }
        let expected = settledFrames[key] ?? target
        if frame.isClose(to: expected, tolerance: policy.tolerance) { return }
        var state = states[key] ?? EnforcementPolicy.WindowState()
        let action = policy.handle(.frameChanged(frame: frame, target: target, mouseDown: mouseDown, at: now), state: &state)
        states[key] = state
        perform(action, for: key, window: window)
    }

    /// The mouse button went up. `dragged` is the window the drag monitor saw being moved;
    /// `drop` the zone it was let go over, if the overlay was up.
    func mouseUp(dragged: AXWindow?, drop: Placement?) {
        let key = dragged?.key ?? dragging
        dragging = nil
        if let drop, let dragged, dragged.isPlaceable {
            place(dragged, at: drop)
            return
        }
        guard let key, let placement = assignments[key], let window = dragged ?? window(for: key),
              let target = targetFrame(for: placement), let frame = window.frame else { return }
        let expected = settledFrames[key] ?? target
        var state = states[key] ?? EnforcementPolicy.WindowState()
        let action = policy.handle(.dragEnded(frame: frame, target: expected, dropZone: drop, at: now), state: &state)
        states[key] = state
        perform(action, for: key, window: window)
    }

    private func perform(_ action: EnforcementPolicy.Action, for key: WindowKey, window: AXWindow) {
        switch action {
        case .none:
            break
        case let .scheduleRestore(after):
            scheduleRestore(key, window: window, after: after)
        case let .assign(placement):
            place(window, at: placement)
        case let .release(reason):
            release(key, reason: reason)
        }
    }

    private func scheduleRestore(_ key: WindowKey, window: AXWindow, after: Double) {
        pendingRestores[key]?.cancel()
        pendingRestores[key] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(after))
            guard !Task.isCancelled, let self else { return }
            self.pendingRestores[key] = nil
            guard let placement = self.assignments[key], let target = self.targetFrame(for: placement),
                  let frame = window.frame else { return }
            if frame.isClose(to: self.settledFrames[key] ?? target, tolerance: self.policy.tolerance) { return }
            if self.mouseIsDown { self.dragging = key; return }
            let ok = self.apply(target, to: window)
            if ok { self.settledFrames[key] = window.frame }
            self.log.info("restore \(key, privacy: .public) \(ok ? "ok" : "failed", privacy: .public)")
            var state = self.states[key] ?? EnforcementPolicy.WindowState()
            let action = self.policy.handle(.restoreResult(success: ok, at: self.now), state: &state)
            self.states[key] = state
            self.perform(action, for: key, window: window)
        }
    }

    // MARK: - Bookkeeping

    private func window(for key: WindowKey) -> AXWindow? {
        AXWindow.windows(of: key.pid).first { $0.key == key }
    }

    /// Drops assignments of windows the app no longer lists.
    private func prune(pid: pid_t) {
        let keys = assignments.keys.filter { $0.pid == pid }
        guard !keys.isEmpty else { return }
        let alive = Set(AXWindow.windows(of: pid).compactMap(\.key))
        for key in keys where !alive.contains(key) { release(key, reason: "window closed") }
    }

    private func forget(pid: pid_t) {
        for key in assignments.keys where key.pid == pid { release(key, reason: "app quit") }
    }
}
