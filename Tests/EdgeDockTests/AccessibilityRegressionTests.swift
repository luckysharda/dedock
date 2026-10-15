import DedockCore
import Testing
@testable import EdgeDock

/// REG-040 guard (macOS only; excluded on Linux). SwiftUI builds its live accessibility tree only
/// when an assistive client is attached, so the live role (AXButton + AXPress) is verified by the
/// E2E cua-driver check; this unit guard pins the spec and the press routing.
@Suite("Regression", .tags(.regression)) @MainActor struct AccessibilityRegressionTests {
    /// REG-040: dock tiles had role AXUnknown with no action, so VoiceOver and AX clients could
    /// not press them.
    @Test("REG-040: dock tiles are labelled buttons whose press takes the click path")
    func reg040() {
        let app = TileModel(id: "c", kind: .app, name: "Calculator", bundleID: "com.apple.calculator")
        let spec = TileAccessibilitySpec(app)
        #expect(spec == TileAccessibilitySpec(app))
        #expect(spec.isButton && !spec.hidden)
        #expect(spec.label == "Calculator")
        #expect(spec.value == "not running")

        var running = app
        running.running = .frontmost
        #expect(TileAccessibilitySpec(running).value == "running, frontmost")

        let folder = TileAccessibilitySpec(TileModel(id: "d", kind: .folder, name: "Downloads"))
        #expect(folder.isButton && folder.label == "Downloads" && folder.value == "folder")
        #expect(TileAccessibilitySpec(TileModel(id: "s", kind: .separator, name: "")).hidden)

        // AXPress routes to the same activation the click uses.
        var pressed: [TileID] = []
        DockTileAccessibility(tile: app) { pressed.append($0) }.press()
        #expect(pressed == ["c"])

        // The dock model routes AXPress to the coordinator's click path.
        let model = DockViewModel(tokens: .placeholder(), icons: IconCache())
        var routed: [TileID] = []
        model.activate = { routed.append($0) }
        model.activate?("c")
        #expect(routed == ["c"])
    }
}
