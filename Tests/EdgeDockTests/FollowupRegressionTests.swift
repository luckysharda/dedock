import DedockCore
import Foundation
import Testing
@testable import EdgeDock

/// Regression guards for the PR #7 review follow-ups (pure logic; runs on Linux too).
@Suite("Regression", .tags(.regression)) struct FollowupLogicRegressionTests {
    /// REG-034: a mouse press while arming disarmed the dock, and it could not re-arm until the
    /// pointer left the zone and came back.
    @Test("REG-034: releasing the button inside the zone re-arms")
    func reg034() {
        var e = TriggerEvaluator()
        var m = RevealStateMachine()
        let zone = HotZone(id: "z-0", rect: CGRect(x: 0, y: 0, width: 3, height: 500), kind: .wall)
        func send(_ down: Bool, _ ms: Int) {
            let s = PointerSample(location: CGPoint(x: 1, y: 200), timestamp: .milliseconds(ms), buttonsDown: down)
            for ev in e.evaluate(s, zones: [zone], capsule: nil, edge: .left, onDockDisplay: true) { _ = m.handle(ev, progress: 0) }
        }
        send(false, 0)
        #expect(m.phase == .arming(.wall))
        send(true, 50)          // press: disarm
        #expect(m.phase == .hidden)
        send(false, 100)        // release, still at the edge: re-arm
        #expect(m.phase == .arming(.wall))
    }
}

@Suite struct DebugCommandTests {
    @Test(arguments: [
        ("setEdge=right", DebugCommand?.some(.setEdge(.right))), ("setEdge=top", .some(.setEdge(.top))),
        ("rebuildZones", .some(.rebuildZones)), ("reveal", .some(.reveal)), ("hide", .some(.hide)),
        ("setEdge=diagonal", nil), ("setEdge", nil), ("rm -rf", nil), ("", nil), ("reveal=1", nil),
    ])
    func parsesOnlyKnownCommands(raw: String, expected: DebugCommand?) {
        #expect(DebugCommand.parse(raw) == expected)
    }
}
