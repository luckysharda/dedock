import Testing
@testable import Diagnostics

@Suite("Regression", .tags(.regression)) struct LogRegressionTests {
    /// REG-030: release builds logged every value `.public`, including bundle ids, paths and
    /// error text, now that the repo (and its logs in bug reports) are public.
    @Test("REG-030: release logging keeps string values private, numbers public")
    func reg030() {
        let release = DedockLog.format("tile.activate", ["id": "t-1", "bundle": "com.example.secret", "ms": 486, "ok": true],
                                       redactStrings: true)
        #expect(release.public == "tile.activate ms=486 ok=true")
        #expect(release.private == " id=t-1 bundle=com.example.secret")
        #expect(!release.public.contains("com.example"))

        let numericString = DedockLog.format("edge.zoneEnter", ["x": DedockLog.pt(12.5), "edge": "left"], redactStrings: true)
        #expect(numericString.public == "edge.zoneEnter x=12.50")

        // Debug builds keep the full E2E grammar public, in field order.
        let debug = DedockLog.format("tile.activate", ["id": "t-1", "ms": 486], redactStrings: false)
        #expect(debug.public == "tile.activate id=t-1 ms=486")
        #expect(debug.private.isEmpty)
    }
}
