import DedockCore
import Foundation
import SettingsStore
import Testing
@testable import EdgeDock

/// Regression guards for settings → dock mapping (macOS: the mapping lives in the AppKit module).
@Suite("Regression", .tags(.regression)) struct MappingRegressionTests {
    /// REG-035: hysteresis allowed 0–64 pt (spec 0–40) and dwell/delay values were not clamped
    /// to 0–5 s, so a hand-edited or seeded layout.json could set out-of-range timings.
    @Test("REG-035: trigger and timing values are clamped to their spec ranges")
    func reg035() {
        var d = DedockDocument.makeDefault().docks[0]
        d.reveal.hysteresisPt = 64
        d.reveal.showDwellMs = 99_000
        d.reveal.hideDelayMs = -5
        d.reveal.fullscreenDwellMs = 7000
        d.reveal.pushThroughPt = 1000
        let p = d.triggerParameters
        let c = d.revealConfig(reduceMotion: false)
        #expect(p.hysteresis == 40)
        #expect(p.pushThrough == 200)
        #expect(c.showDwell == .seconds(5))
        #expect(c.hideDelay == .zero)
        #expect(c.fullscreenDwell == .seconds(5))
        d.reveal.pushThroughPt = 2
        #expect(d.triggerParameters.pushThrough == 16)
        d.reveal.pushThroughPt = nil
        #expect(d.triggerParameters.pushThrough == nil)
    }
}
