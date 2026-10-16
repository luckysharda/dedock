import SwiftUI
import Testing
@testable import SettingsUI

/// Regression guards for the Settings window (macOS only).
@Suite("Regression", .tags(.regression)) @MainActor struct SettingsUIRegressionTests {
    /// REG-063: the numeric fields beside the sliders were AXTextFields with a value and no name
    /// (`labelsHidden()` drops it), so VoiceOver read only the number. Each field is named after
    /// its slider and unit. SwiftUI's live AX tree is not readable in-process; the cua C8
    /// "controls labelled" check verifies the names live.
    @Test("REG-063: every slider's value field is named after its slider")
    func reg063() {
        let rows: [(label: String, unit: String)] = [
            ("Show delay", "ms"), ("Hide delay", "ms"), ("Full-screen show delay", "ms"),
            ("Trigger thickness", "pt"), ("Corner exclusion", "pt"), ("Distance from edge", "pt"),
        ]
        for row in rows {
            let slider = ValueSlider(label: row.label, value: .constant(0), range: 0...100, unit: row.unit)
            #expect(slider.valueFieldLabel == "\(row.label), \(row.unit)")
        }
        #expect(ValueSlider(label: "Scale", value: .constant(0), range: 0...1, unit: "").valueFieldLabel == "Scale")
    }
}

/// Z1: the size slider snaps to the nearest stop on release (T25 row 27).
@Suite @MainActor struct SizeSliderTests {
    @Test func releaseSnapsToTheNearestStop() {
        #expect(SizeSlider.tile(.s) == 48 && SizeSlider.tile(.xl) == 92)
        #expect(SizeSlider.snapped(live: 70, size: .m) == .l)
        #expect(SizeSlider.snapped(live: 49, size: .xl) == .s)
        #expect(SizeSlider.snapped(live: nil, size: .m) == .m)          // a click without a drag
        #expect(SizeSlider.range == 48...92)
    }

    /// e9's #42 must-fix: VoiceOver increment/decrement and arrow keys move one stop and save it
    /// at once, never leaving a live preview behind.
    @Test func keyboardAndVoiceOverStepOneStop() {
        #expect(SizeSlider.stepped(.m, up: true) == .l)
        #expect(SizeSlider.stepped(.m, up: false) == .s)
        #expect(SizeSlider.stepped(.xl, up: true) == .xl)
        #expect(SizeSlider.stepped(.s, up: false) == .s)
        // An arrow nudges the value a little; it still moves a whole stop in that direction.
        #expect(SizeSlider.discrete(.m, to: 62 + 4.4) == .l)
        #expect(SizeSlider.discrete(.m, to: 62 - 4.4) == .s)
        #expect(SizeSlider.discrete(.m, to: 62) == .m)
    }

    /// A new grab during the snap stops it: no further writes and no late finish (e9's #42 review).
    @Test func aNewGrabCancelsTheSnap() async {
        let runner = SnapRunner()
        var steps: [Double] = []
        var finished = 0
        runner.run(path: [1, 2, 3, 4], frame: .milliseconds(5), step: { steps.append($0) }, finish: { finished += 1 })
        for _ in 0..<3 { await Task.yield() }
        runner.cancel()
        let seen = steps.count
        try? await Task.sleep(for: .milliseconds(60))
        #expect(steps.count == seen)
        #expect(finished == 0)
        #expect(!runner.isRunning)

        // Closing the window mid-snap completes it at once.
        runner.run(path: [1, 2, 3, 4], frame: .milliseconds(50), step: { steps.append($0) }, finish: { finished += 1 })
        runner.finishNow()
        #expect(finished == 1)
        try? await Task.sleep(for: .milliseconds(120))
        #expect(finished == 1)                                             // not twice
    }

    /// The release snap eases to the stop and ends exactly on it.
    @Test func snapCurveEndsOnTheStop() {
        let path = SizeSlider.snapCurve(from: 69, to: 76)
        #expect(path.count == 15)
        #expect(path.last == 76)
        #expect(zip(path, path.dropFirst()).allSatisfy { $0 <= $1 })      // monotone, no overshoot
        #expect(path[0] - 69 > (76 - 69) / 15)                             // ease-out: fast start
        #expect(SizeSlider.snapCurve(from: 76, to: 76) == [76])
    }
}
