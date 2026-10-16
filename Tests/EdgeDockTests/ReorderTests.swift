import AppKit
import DedockCore
import DedockTestSupport
import DisplayTopology
import EventTapKit
import Foundation
import SettingsStore
import Testing
@testable import EdgeDock

@Suite struct ReorderTests {
    let order: [TileID] = ["a", "b", "c", "d"]

    @Test(arguments: [
        ("a", 2, ["b", "c", "a", "d"]),
        ("a", 3, ["b", "c", "d", "a"]),
        ("d", 0, ["d", "a", "b", "c"]),
        ("b", 1, ["a", "b", "c", "d"]),
        ("c", 99, ["a", "b", "d", "c"]),
        ("c", -1, ["c", "a", "b", "d"]),
    ])
    @MainActor func reorderedInsertsAmongTheOthers(moving: String, index: Int, expected: [String]) {
        let result = EdgeDockCoordinator.reordered(order, moving: TileID(moving), to: index)
        #expect(result == expected.map { TileID($0) })
    }
}

@Suite struct DropToPinTests {
    @Test @MainActor func appURLBecomesAnAppTileWithItsBundleID() {
        let item = EdgeDockManager.tileItem(for: URL(fileURLWithPath: "/System/Applications/Calculator.app"))
        #expect(item.kind == .app)
        #expect(item.bundleID == "com.apple.calculator")
        #expect(item.path == "/System/Applications/Calculator.app")
        #expect(item.displayName == "Calculator")
    }

    @Test @MainActor func folderURLBecomesAFolderTileWithABookmark() {
        let dir = FileManager.default.temporaryDirectory
        let item = EdgeDockManager.tileItem(for: dir)
        #expect(item.kind == .folder)
        #expect(item.bookmark != nil)
        #expect(item.bundleID == nil)
    }
}

/// Drag-out-to-remove (evaluation row 43, design §2.3a). macOS only.
@Suite(.serialized) @MainActor struct DragOutRemovalTests {
    func makeManager(_ dir: URL, clock: ManualClock) -> (EdgeDockManager, SettingsModel) {
        let settings = SettingsModel(file: LayoutFile(directory: dir), clock: clock, document: .makeDefault())
        let manager = EdgeDockManager(settings: settings, topology: DisplayTopology(clock: clock),
                                      hub: PointerHub(source: SilentPointerSource(), clock: clock), clock: clock, dataDirectory: dir)
        return (manager, settings)
    }

    func ask(_ manager: EdgeDockManager, _ settings: SettingsModel) throws -> (RemovalConfirmation, EdgeDockCoordinator, TileID) {
        var asked: RemovalConfirmation?
        manager.replaceRemovalPresenter { _, confirmation, _, _ in asked = confirmation }
        let c = try #require(manager.coordinators.values.first)
        let tile = try #require(settings.document.profiles.first?.items.first?.id)
        manager.askToRemove(tile, from: c.config.profileID, coordinator: c, at: CGPoint(x: 400, y: 400))
        return (try #require(asked), c, tile)
    }

    @Test(.enabled(if: NSScreen.main != nil)) func removeRemovesAndReleasesTheHold() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dedock-dragout-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (manager, settings) = makeManager(dir, clock: ManualClock())
        let (confirmation, c, tile) = try ask(manager, settings)
        #expect(c.controller.machine.holds.contains(.popoverOpen))      // the dock stays shown
        confirmation.answer(.remove)
        #expect(!(settings.document.profiles.first?.items.contains { $0.id == tile } ?? true))
        #expect(!c.controller.machine.holds.contains(.popoverOpen))
        #expect(manager.pendingRemoval == nil)
        for c in manager.coordinators.values { c.teardown() }
    }

    @Test(.enabled(if: NSScreen.main != nil)) func keepLeavesTheTile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dedock-dragout-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (manager, settings) = makeManager(dir, clock: ManualClock())
        let before = settings.document.profiles.first?.items
        let (confirmation, c, _) = try ask(manager, settings)
        confirmation.answer(.keep)
        confirmation.answer(.remove)                                      // answers only once
        #expect(settings.document.profiles.first?.items == before)
        #expect(confirmation.result == .keep)
        #expect(!c.controller.machine.holds.contains(.popoverOpen))
        for c in manager.coordinators.values { c.teardown() }
    }

    @Test(.enabled(if: NSScreen.main != nil)) func noAnswerKeepsAfterEightSeconds() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dedock-dragout-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = ManualClock()
        let (manager, settings) = makeManager(dir, clock: clock)
        let before = settings.document.profiles.first?.items
        let (confirmation, _, _) = try ask(manager, settings)
        for _ in 0..<100 where clock.pendingCount == 0 { await Task.yield() }
        clock.advance(by: .milliseconds(7900))
        for _ in 0..<50 { await Task.yield() }
        #expect(confirmation.result == nil)
        clock.advance(by: .milliseconds(200))
        for _ in 0..<100 where confirmation.result == nil { await Task.yield() }
        #expect(confirmation.result == .timeout)
        #expect(settings.document.profiles.first?.items == before)
        for c in manager.coordinators.values { c.teardown() }
    }

    @Test(.enabled(if: NSScreen.main != nil)) func panelNeverTakesKeyFocus() {
        let confirmation = RemovalConfirmation(tile: "t", clock: ManualClock()) { _ in }
        let p = RemoveConfirmPanel(name: "Calculator", confirmation: confirmation)
        p.show(capsule: CGRect(x: 8, y: 300, width: 78, height: 300), drop: CGPoint(x: 200, y: 450), edge: .left,
               visible: CGRect(x: 0, y: 0, width: 1920, height: 1056))
        #expect(p.panel.isVisible)
        #expect(!p.panel.isKeyWindow)
        #expect(p.panel.styleMask.contains(.nonactivatingPanel))
        #expect(p.panel.title == "Remove \u{201C}Calculator\u{201D} from the Edge Dock?")
        #expect(p.panel.frame.minX >= CGFloat(86 + 10))                          // beside the dock, toward the centre
        p.remove()
        #expect(confirmation.result == .remove)
        p.close()
    }

    @Test(.enabled(if: NSScreen.main != nil)) func droppingOutsideTheDockAsksDroppingInsideDoesNot() throws {
        let config = DedockDocument.makeDefault().docks[0]
        let items = [TileItem(id: "t1", kind: .app, bundleID: "com.apple.calculator"),
                     TileItem(id: "t2", kind: .app, bundleID: "com.apple.TextEdit")]
        let (c, _, _) = AppRegressionTests().makeCoordinator(config, items: items)
        var asked: [(TileID, CGPoint)] = []
        var reordered = 0
        c.onDragOut = { asked.append(($0, $1)) }
        c.onReorder = { _ in reordered += 1 }
        let t1 = try #require(c.layout.tileFrames["t1"])

        c.panel.root.onDragBegan?("t1", CGPoint(x: t1.midX, y: t1.midY))
        c.panel.root.onDragEnded?(CGPoint(x: t1.midX + 1, y: t1.midY))    // inside, same slot
        #expect(asked.isEmpty)

        let outside = CGPoint(x: c.capsuleFrame.maxX + 200, y: t1.midY)
        c.panel.root.onDragBegan?("t1", CGPoint(x: t1.midX, y: t1.midY))
        c.panel.root.onDragMoved?(outside)
        c.panel.root.onDragEnded?(outside)
        #expect(asked.count == 1 && asked.first?.0 == "t1" && asked.first?.1 == outside)
        #expect(reordered == 0)
        #expect(c.model.draggedTile == nil)
        c.teardown()
    }

    @Test func panelSitsOnTheScreenCentreSide() {
        let size = CGSize(width: 300, height: 92), visible = CGRect(x: 0, y: 0, width: 1920, height: 1056)
        let left = RemoveConfirmPanel.origin(size: size, capsule: CGRect(x: 8, y: 300, width: 78, height: 300),
                                             drop: CGPoint(x: 200, y: 450), edge: .left, visible: visible)
        #expect(left.x == 96 && left.y == 404)
        let right = RemoveConfirmPanel.origin(size: size, capsule: CGRect(x: 1834, y: 300, width: 78, height: 300),
                                              drop: CGPoint(x: 1700, y: 450), edge: .right, visible: visible)
        #expect(right.x == CGFloat(1834 - 10 - 300))
        let bottom = RemoveConfirmPanel.origin(size: size, capsule: CGRect(x: 800, y: 86, width: 300, height: 78),
                                               drop: CGPoint(x: 950, y: 300), edge: .bottom, visible: visible)
        #expect(bottom.y == CGFloat(164 + 10))
        let top = RemoveConfirmPanel.origin(size: size, capsule: CGRect(x: 800, y: 940, width: 300, height: 78),
                                            drop: CGPoint(x: 950, y: 800), edge: .top, visible: visible)
        #expect(top.y == CGFloat(940 - 10 - 92))                                // below the capsule
        #expect(top.x == CGFloat(950 - 150))
    }
}
