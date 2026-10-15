import DedockCore
import Foundation
import Testing
@testable import EdgeDock

/// Regression guards for the PR #7 review blockers (pure logic; runs on Linux too).
@Suite("Regression", .tags(.regression)) struct ReviewLogicRegressionTests {
    /// REG-028: hiding re-revealed on pointer return during the 500 ms re-arm cooldown, so a
    /// tile click (explicit hide) bounced the dock straight back.
    @Test("REG-028: no re-reveal while hiding during the re-arm cooldown")
    func reg028() {
        var m = RevealStateMachine()
        _ = m.handle(.zoneEntered(.wall), progress: 0)
        _ = m.handle(.timerFired(.dwell), progress: 0)
        _ = m.handle(.animationFinished(generation: m.activeGeneration!), progress: 1)
        _ = m.handle(.command(.hide(explicit: true)), progress: 1)        // tile click
        #expect(m.phase == .hiding)
        #expect(m.handle(.pointerInside(true), progress: 0.8).isEmpty)  // pointer still on the tile
        #expect(m.handle(.zoneEntered(.wall), progress: 0.7).isEmpty)
        #expect(m.phase == .hiding)
        // An explicit reveal still works, and after the cooldown a return reverses again.
        _ = m.handle(.timerFired(.cooldown), progress: 0.5)
        #expect(m.handle(.pointerInside(true), progress: 0.5).contains(.setInteractive(true)))
        #expect(m.phase == .revealing)
    }

    /// REG-029: TriggerEvaluator.reset() (every zone rebuild) cleared "inside" without telling
    /// the machine, which kept pointerInside == true and never hid.
    @Test("REG-029: a zone rebuild reports the cleared inside/zone state")
    func reg029() {
        var e = TriggerEvaluator()
        let zone = HotZone(id: "z-0", rect: CGRect(x: 0, y: 0, width: 3, height: 500), kind: .wall)
        _ = e.evaluate(PointerSample(location: CGPoint(x: 1, y: 100), timestamp: .zero),
                       zones: [zone], capsule: CGRect(x: 6, y: 0, width: 70, height: 500), edge: .left, onDockDisplay: true)
        #expect(e.reset() == [.zoneLeft, .pointerInside(false)])
        #expect(e.reset().isEmpty)   // nothing left to clear

        // End to end with the machine: shown → rebuild → the pointer has left → hides normally.
        var m = RevealStateMachine()
        _ = m.handle(.zoneEntered(.wall), progress: 0)
        _ = m.handle(.timerFired(.dwell), progress: 0)
        _ = m.handle(.animationFinished(generation: m.activeGeneration!), progress: 1)
        var effects: [RevealEffect] = []
        for ev in [RevealEvent.zoneLeft, .pointerInside(false)] { effects += m.handle(ev, progress: 1) }
        #expect(m.phase == .armingHide)
        #expect(effects.contains(.startTimer(.hide, .milliseconds(400))))
    }
}
