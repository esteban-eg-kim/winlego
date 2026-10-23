import CoreGraphics
import Testing
@testable import WinlegoCore

@Suite struct EnforcementPolicyTests {
    let policy = EnforcementPolicy()
    let target = CGRect(x: 0, y: 0, width: 500, height: 400)
    let away = CGRect(x: 300, y: 50, width: 500, height: 400)

    @Test func inPlaceWindowIsLeftAlone() {
        var s = EnforcementPolicy.WindowState()
        let nearly = CGRect(x: 1, y: -1, width: 501, height: 399)
        #expect(policy.handle(.frameChanged(frame: nearly, target: target, mouseDown: false, at: 0), state: &s) == .none)
    }

    @Test func appMovingWindowGetsRestoredAfterDebounce() {
        var s = EnforcementPolicy.WindowState()
        #expect(policy.handle(.frameChanged(frame: away, target: target, mouseDown: false, at: 0), state: &s)
                == .scheduleRestore(after: policy.debounce))
    }

    @Test func userDragWaitsThenReleasesWhenDroppedOutsideZones() {
        var s = EnforcementPolicy.WindowState()
        #expect(policy.handle(.frameChanged(frame: away, target: target, mouseDown: true, at: 0), state: &s) == .none)
        #expect(policy.handle(.dragEnded(frame: away, target: target, dropZone: nil, at: 1), state: &s)
                == .release(reason: "moved by hand"))
    }

    @Test func dropOnZoneAssigns() {
        var s = EnforcementPolicy.WindowState()
        let p = Placement(displayID: "D1", zone: 2)
        #expect(policy.handle(.dragEnded(frame: away, target: target, dropZone: p, at: 1), state: &s) == .assign(p))
    }

    @Test func dragThatEndsBackInPlaceKeepsAssignment() {
        var s = EnforcementPolicy.WindowState()
        #expect(policy.handle(.dragEnded(frame: target, target: target, dropZone: nil, at: 1), state: &s) == .none)
    }

    @Test func fightingAppIsReleased() {
        var s = EnforcementPolicy.WindowState()
        for t in [0.1, 0.2, 0.3] {
            #expect(policy.handle(.restoreResult(success: true, at: t), state: &s) == .none)
        }
        #expect(policy.handle(.frameChanged(frame: away, target: target, mouseDown: false, at: 0.4), state: &s)
                == .release(reason: "the app keeps moving it"))
        // A second later the slate is clean.
        #expect(policy.handle(.frameChanged(frame: away, target: target, mouseDown: false, at: 1.5), state: &s)
                == .scheduleRestore(after: policy.debounce))
    }

    @Test func repeatedFailuresRelease() {
        var s = EnforcementPolicy.WindowState()
        for i in 0..<4 {
            #expect(policy.handle(.restoreResult(success: false, at: Double(i) * 2), state: &s)
                    == .scheduleRestore(after: policy.debounce))
        }
        #expect(policy.handle(.restoreResult(success: false, at: 10), state: &s)
                == .release(reason: "it will not fit the zone"))
    }
}
