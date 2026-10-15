import DedockCore
import Foundation
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
