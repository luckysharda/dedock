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
