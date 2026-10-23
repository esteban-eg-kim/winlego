import CoreGraphics

/// Decides what to do when an assigned window is not where its zone says. Pure: the app
/// feeds it events with timestamps and carries out the actions.
///
/// - A window moved while the mouse button is down is being dragged by the user: wait.
/// - When the drag ends on a zone, the window goes there; anywhere else releases it,
///   because the user plainly wanted it somewhere of their own.
/// - A window that moved on its own (the app restored it, a display changed) is put back
///   after a short debounce. An app that keeps fighting, or a window that cannot be
///   placed, gets released rather than flickering forever.
public struct EnforcementPolicy: Sendable {
    public var debounce: TimeInterval = 0.15
    public var tolerance: CGFloat = 2
    public var maxRestoresPerSecond = 3
    public var maxConsecutiveFailures = 5

    public init() {}

    public typealias TimeInterval = Double

    public struct WindowState: Sendable, Equatable {
        public var restoreTimes: [TimeInterval] = []
        public var failures = 0
        public init() {}
    }

    public enum Event: Sendable {
        /// The window's frame changed. `mouseDown` says whether a mouse button is held.
        case frameChanged(frame: CGRect, target: CGRect, mouseDown: Bool, at: TimeInterval)
        /// The user let go of the window. `dropZone` is set when they dropped it on a zone.
        case dragEnded(frame: CGRect, target: CGRect, dropZone: Placement?, at: TimeInterval)
        /// A restore was attempted.
        case restoreResult(success: Bool, at: TimeInterval)
    }

    public enum Action: Equatable, Sendable {
        case none
        case scheduleRestore(after: TimeInterval)
        case assign(Placement)
        case release(reason: String)
    }

    public func handle(_ event: Event, state: inout WindowState) -> Action {
        switch event {
        case let .frameChanged(frame, target, mouseDown, now):
            if frame.isClose(to: target, tolerance: tolerance) { return .none }
            if mouseDown { return .none }
            let recent = state.restoreTimes.filter { now - $0 < 1 }.count
            if recent >= maxRestoresPerSecond {
                return .release(reason: "the app keeps moving it")
            }
            return .scheduleRestore(after: debounce)

        case let .dragEnded(frame, target, dropZone, _):
            if let dropZone { return .assign(dropZone) }
            if frame.isClose(to: target, tolerance: tolerance) { return .none }
            return .release(reason: "moved by hand")

        case let .restoreResult(success, now):
            state.restoreTimes.append(now)
            state.restoreTimes.removeAll { now - $0 >= 1 }
            if success {
                state.failures = 0
                return .none
            }
            state.failures += 1
            if state.failures >= maxConsecutiveFailures {
                return .release(reason: "it will not fit the zone")
            }
            return .scheduleRestore(after: debounce)
        }
    }
}
