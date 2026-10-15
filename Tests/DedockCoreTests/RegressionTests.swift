import DedockCore
import Foundation
import Testing

/// Unit-level regression guards (Tests/E2E/regressions.md). Runs on macOS and Linux.
@Suite("Regression", .tags(.regression)) struct CoreRegressionTests {
    /// REG-022: CGVector is missing from swift-corelibs-foundation; DedockCore provides it on
    /// Linux so PointerSample keeps its Equatable conformance. This test compiles on both.
    @Test("REG-022: CGVector and PointerSample equality on every platform")
    func reg022() {
        let v = CGVector(dx: 3, dy: -4)
        #expect(v == CGVector(dx: 3, dy: -4))
        #expect(CGVector.zero == CGVector(dx: 0, dy: 0))
        let a = PointerSample(location: .zero, delta: v, timestamp: .milliseconds(1))
        #expect(a == PointerSample(location: .zero, delta: v, timestamp: .milliseconds(1)))
        #expect(a.push(toward: .right) == 3)
    }
}
