import AppKit
import ApplicationServices

/// Watches every regular app for windows appearing, moving, resizing and going away.
/// Notifications are registered on the application element, which covers all of its
/// windows; the run loop source lives on the main run loop, so callbacks arrive there.
@MainActor
final class WindowTracker {
    enum Change { case created, moved, resized, focused, destroyed }

    var onChange: ((AXWindow, Change) -> Void)?
    var onAppQuit: ((pid_t) -> Void)?

    private(set) var apps: [pid_t: TrackedApp] = [:]
    private var observers: [NSObjectProtocol] = []
    private var launchPolls: [pid_t: Task<Void, Never>] = [:]

    final class TrackedApp {
        let pid: pid_t
        let bundleID: String?
        let name: String
        let element: AXUIElement
        let observer: AXObserver
        init(pid: pid_t, bundleID: String?, name: String, element: AXUIElement, observer: AXObserver) {
            self.pid = pid; self.bundleID = bundleID; self.name = name; self.element = element; self.observer = observer
        }
    }

    private static let notifications: [String] = [
        kAXWindowCreatedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification,
        kAXFocusedWindowChangedNotification, kAXUIElementDestroyedNotification,
    ]

    var isRunning: Bool { !observers.isEmpty }

    func start() {
        guard observers.isEmpty else { return }
        for app in NSWorkspace.shared.runningApplications { track(app) }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.track(app, justLaunched: true) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.untrack(app.processIdentifier) }
        })
    }

    func stop() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        for pid in Array(apps.keys) { untrack(pid) }
    }

    func app(for pid: pid_t) -> TrackedApp? { apps[pid] }

    /// Every placeable window of every tracked app.
    func allWindows() -> [AXWindow] {
        apps.keys.sorted().flatMap { AXWindow.windows(of: $0).filter(\.isPlaceable) }
    }

    private func track(_ app: NSRunningApplication, justLaunched: Bool = false) {
        let pid = app.processIdentifier
        guard app.activationPolicy == .regular, pid != ProcessInfo.processInfo.processIdentifier, apps[pid] == nil else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, WindowTracker.callback, &observer) == .success, let observer else { return }
        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in WindowTracker.notifications {
            AXObserverAddNotification(observer, element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        apps[pid] = TrackedApp(pid: pid, bundleID: app.bundleIdentifier, name: app.localizedName ?? "App \(pid)", element: element, observer: observer)
        if justLaunched { pollForFirstWindows(pid) }
    }

    private func untrack(_ pid: pid_t) {
        guard let app = apps.removeValue(forKey: pid) else { return }
        launchPolls.removeValue(forKey: pid)?.cancel()
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(app.observer), .commonModes)
        for name in WindowTracker.notifications {
            AXObserverRemoveNotification(app.observer, app.element, name as CFString)
        }
        onAppQuit?(pid)
    }

    /// Some apps never post `AXWindowCreated` for the windows they open at launch, and
    /// others are not ready for observers yet. Look for a few seconds.
    private func pollForFirstWindows(_ pid: pid_t) {
        launchPolls[pid]?.cancel()
        launchPolls[pid] = Task { [weak self] in
            var seen = Set<WindowKey>()
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else { return }
                for window in AXWindow.windows(of: pid) where window.isPlaceable {
                    guard let key = window.key, !seen.contains(key) else { continue }
                    seen.insert(key)
                    self.onChange?(window, .created)
                }
            }
            self?.launchPolls.removeValue(forKey: pid)
        }
    }

    private static let callback: AXObserverCallback = { _, element, notification, refcon in
        guard let refcon else { return }
        let tracker = Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue()
        let name = notification as String
        // The callback runs on the main run loop; the element is ours alone from here on.
        nonisolated(unsafe) let element = element
        MainActor.assumeIsolated {
            tracker.handle(element: element, notification: name)
        }
    }

    private func handle(element: AXUIElement, notification: String) {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let window = AXWindow(element: element, pid: pid)
        switch notification {
        case kAXWindowCreatedNotification: onChange?(window, .created)
        case kAXWindowMovedNotification: onChange?(window, .moved)
        case kAXWindowResizedNotification: onChange?(window, .resized)
        case kAXFocusedWindowChangedNotification: onChange?(window, .focused)
        case kAXUIElementDestroyedNotification: onChange?(window, .destroyed)
        default: break
        }
    }
}
