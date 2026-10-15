import DedockCore
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
