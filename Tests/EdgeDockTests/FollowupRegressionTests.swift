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

    /// REG-064: opening Settings revealed the dock explicitly, which waits for a first pointer
    /// visit (S-13), so after Settings closed with the pointer away the dock stayed shown.
    /// Releasing the `editing` hold now returns the dock to normal behaviour.
    @Test("REG-064: closing Settings with the pointer away hides the dock after the hide delay")
    func reg064() {
        var m = RevealStateMachine()
        _ = m.handle(.hold(.editing, true), progress: 0)             // Settings opens
        _ = m.handle(.command(.reveal), progress: 0)
        _ = m.handle(.animationFinished(generation: m.activeGeneration!), progress: 1)
        #expect(m.phase == .shown)
        let close = m.handle(.hold(.editing, false), progress: 1)    // Settings closes, pointer away
        #expect(m.phase == .armingHide)
        #expect(close.contains { if case .startTimer(.hide, _) = $0 { true } else { false } })
        _ = m.handle(.timerFired(.hide), progress: 1)
        #expect(m.phase == .hiding)

        // Other holds keep S-13: an explicit reveal still waits for the first visit.
        var n = RevealStateMachine()
        _ = n.handle(.command(.reveal), progress: 0)
        _ = n.handle(.animationFinished(generation: n.activeGeneration!), progress: 1)
        _ = n.handle(.hold(.menuOpen, true), progress: 1)
        _ = n.handle(.hold(.menuOpen, false), progress: 1)
        #expect(n.phase == .shown)
    }
}

@Suite struct DebugCommandTests {
    @Test(arguments: [
        ("setEdge=right", DebugCommand?.some(.setEdge(.right))), ("setEdge=top", .some(.setEdge(.top))),
        ("rebuildZones", .some(.rebuildZones)), ("reveal", .some(.reveal)), ("hide", .some(.hide)),
        ("openSettings", .some(.openSettings)), ("openSettings=x", nil),
        ("setEdge=diagonal", nil), ("setEdge", nil), ("rm -rf", nil), ("", nil), ("reveal=1", nil),
    ])
    func parsesOnlyKnownCommands(raw: String, expected: DebugCommand?) {
        #expect(DebugCommand.parse(raw) == expected)
    }

    /// A command acts only in the process it names; one without a usable pid is rejected.
    @Test func commandsAreAddressedByPID() {
        #expect(DebugCommand.addressing(Int32(4242), ownPID: 4242) == .mine)
        #expect(DebugCommand.addressing(4242, ownPID: 4242) == .mine)
        #expect(DebugCommand.addressing(NSNumber(value: 4242), ownPID: 4242) == .mine)
        #expect(DebugCommand.addressing("4242", ownPID: 4242) == .mine)
        #expect(DebugCommand.addressing("4243", ownPID: 4242) == .other)
        #expect(DebugCommand.addressing(nil, ownPID: 4242) == .missing)
        #expect(DebugCommand.addressing("", ownPID: 4242) == .missing)
        #expect(DebugCommand.addressing("42x", ownPID: 4242) == .missing)
        #expect(DebugCommand.addressing(-1, ownPID: 4242) == .missing)
        #expect(DebugCommand.addressing(Int.max, ownPID: 4242) == .missing)
    }

    /// Any process can post arbitrary text, so the debug log keeps at most 64 characters of it.
    @Test func loggedTextIsCapped() {
        #expect(DebugCommand.logged("reveal") == "reveal")
        let long = String(repeating: "x", count: 500)
        #expect(DebugCommand.logged(long) == String(repeating: "x", count: DebugCommand.maxLoggedLength) + "…")
        #expect(DebugCommand.logged(String(repeating: "y", count: 64)).count == 64)
    }
}
