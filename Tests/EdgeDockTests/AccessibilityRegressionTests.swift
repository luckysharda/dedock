import AppKit
import DedockCore
import SettingsStore
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
        DockTileAccessibility(tile: app, cell: CGSize(width: 62, height: 54)) { pressed.append($0) }.press()
        #expect(pressed == ["c"])

        // (Token-agnostic on purpose: this guard must compile with any DockTokens skin.)
    }

    /// REG-054: `AXUIElementCopyElementAtPosition` at a shown tile's centre returned Dedock's
    /// AXWindow: the root view's click-routing `hitTest` hid the SwiftUI tiles from the default
    /// accessibility hit test. The live element is checked by the E2E cua probe; this guard
    /// pins that the root forwards point hit tests to its content.
    @Test("REG-054: point accessibility hit tests reach the dock content, not the window")
    func reg054() {
        let root = DockRootView(frame: CGRect(x: 0, y: 0, width: 78, height: 400), model: DockViewModel(tokens: DedockDocument.makeDefault().docks[0].tokens, icons: IconCache()))
        let content = HitTestSpy()
        root.accessibilityContent = content
        let point = NSPoint(x: 47, y: 423)
        #expect(root.accessibilityHitTest(point) as? String == HitTestSpy.element)
        #expect(content.points == [point])
    }
}

extension AccessibilityRegressionTests {
    /// REG-056: the panel's AXWindow reported subrole AXSystemDialog, so VoiceOver could announce
    /// the dock as a "system dialog". It is a named floating window.
    @Test("REG-056: the dock window is a named floating window, not a system dialog",
          .enabled(if: NSScreen.main != nil))
    func reg056() {
        let model = DockViewModel(tokens: DedockDocument.makeDefault().docks[0].tokens, icons: IconCache())
        let panel = EdgeDockPanel(frame: CGRect(x: 0, y: 0, width: 78, height: 400), model: model)
        defer { panel.close() }
        #expect(panel.accessibilityRole() == .window)
        #expect(panel.accessibilitySubrole() == .floatingWindow)
        #expect(panel.accessibilityLabel() == "Edge Dock")
    }
}

extension AccessibilityRegressionTests {
    /// REG-061: a tile's AX element was only the 52 pt icon while the click target is the whole
    /// cell, so at the cell edge a click opened the app but VoiceOver found the content group.
    /// SwiftUI's live AX frames are not readable in-process (the cua C3/C7 checks verify them);
    /// this guard pins that every laid-out tile's element is sized to its layout cell.
    @Test("REG-061: each tile's accessibility element covers its whole layout cell",
          .enabled(if: NSScreen.main != nil))
    func reg061() throws {
        let doc = DedockDocument.makeDefault()
        let config = doc.docks[0]
        let display = DisplaySnapshot(identity: DisplayIdentity(uuid: "reg061"), frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                      visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1056), menuBarHeight: 24,
                                      menuBarAutoHides: false, isMain: true, backingScale: 1)
        let items = [TileItem(id: "a", kind: .app, bundleID: "com.apple.calculator"),
                     TileItem(id: "f", kind: .folder, path: "/tmp"),
                     TileItem(id: "s", kind: .separator)]
        let layout = LayoutEngine.layout(items.map(\.tileSpec), PlacementInput(display: display, edge: config.edge), config.tokens.metrics)
        let model = DockViewModel(tokens: config.tokens, icons: IconCache())
        for item in items where item.kind != .separator {
            let cell = try #require(layout.tileFrames[item.id])
            let view = TileView(tile: item.tileModel, model: model, size: cell.size)
            #expect(view.accessibility.cell == cell.size, "\(item.id)")
            #expect(view.accessibility.cell.width > config.tokens.appIcon)   // larger than the icon alone
        }
    }
}

/// Stands in for the SwiftUI content's accessibility tree.
@MainActor final class HitTestSpy: NSView {
    static let element = "tile-button"
    var points: [NSPoint] = []
    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        points.append(point)
        return Self.element
    }
}
