import DedockCore
import Foundation
import Testing
@testable import EventTapKit

@MainActor final class FakePointerSource: PointerEventSource {
    var handler: (@MainActor (PointerSample) -> Void)?
    var installCount = 0
    var uninstallCount = 0
    var currentLocation: CGPoint = .zero
    var buttonsDown = false
    var currentModifiers: ModifierSet = []
    var isInstalled: Bool { handler != nil }

    func install(_ handler: @escaping @MainActor (PointerSample) -> Void) {
        installCount += 1
        self.handler = handler
    }

    func uninstall() {
        uninstallCount += 1
        handler = nil
    }

    func move(_ x: CGFloat, _ y: CGFloat, dx: CGFloat = 0, dy: CGFloat = 0, ms: Int) {
        handler?(PointerSample(location: CGPoint(x: x, y: y), delta: CGVector(dx: dx, dy: dy), timestamp: .milliseconds(ms)))
    }
}

@MainActor final class RecordingSink: PointerSampleSink {
    var samples: [PointerSample] = []
    func pointer(_ sample: PointerSample) { samples.append(sample) }
}

@MainActor @Suite struct PointerHubTests {
    let source = FakePointerSource()
    let clock = TestClock()
    let sink = RecordingSink()

    func makeHub() -> PointerHub {
        let hub = PointerHub(source: source, clock: clock, farFieldRate: 15)
        hub.addSink(sink)
        hub.start()
        return hub
    }

    @Test func installsOnStartAndUninstallsOnStop() {
        let hub = makeHub()
        #expect(source.isInstalled)
        hub.stop()
        #expect(!source.isInstalled)
    }

    @Test func nearBandDeliversEveryEvent() {
        let hub = makeHub()
        hub.nearRegions = [CGRect(x: 0, y: 0, width: 100, height: 1000)]
        for i in 0..<10 { source.move(10, 500, dx: -1, ms: i * 5) }
        #expect(sink.samples.count == 10)
        #expect(sink.samples.allSatisfy { $0.delta.dx == -1 })
    }

    @Test func farFieldIsThrottledTo15HzWithSummedDeltas() {
        let hub = makeHub()
        defer { withExtendedLifetime(hub) {} }
        // 10 events 5 ms apart (45 ms total) outside any near region.
        for i in 0..<10 { source.move(800, 500, dx: 2, dy: 1, ms: i * 5) }
        // First is delivered; the rest are held for the trailing sample.
        #expect(sink.samples.count == 1)
        #expect(sink.samples[0].delta == CGVector(dx: 2, dy: 1))
        // Next event after the 66.7 ms interval goes straight through, carrying every held delta.
        source.move(810, 500, dx: 2, dy: 1, ms: 70)
        #expect(sink.samples.count == 2)
        #expect(sink.samples[1].delta == CGVector(dx: 20, dy: 10))
        #expect(sink.samples[1].location == CGPoint(x: 810, y: 500))
    }

    @Test func trailingSampleIsDeliveredWhenThePointerStops() async {
        let hub = makeHub()
        defer { withExtendedLifetime(hub) {} }
        source.move(800, 500, dx: 1, ms: 0)
        source.move(805, 500, dx: 5, ms: 10)
        source.move(809, 500, dx: 4, ms: 20)
        #expect(sink.samples.count == 1)
        await waitForSleepers(clock)
        #expect(clock.sleeperCount == 1)
        // Scheduled at the first held event (t = 10 ms) for the rest of the 66.7 ms interval: 56.7 ms.
        clock.advance(by: .milliseconds(40))
        await settle()
        #expect(sink.samples.count == 1)
        clock.advance(by: .milliseconds(20))
        await settle()
        #expect(sink.samples.count == 2)
        #expect(sink.samples[1].location == CGPoint(x: 809, y: 500))
        #expect(sink.samples[1].delta == CGVector(dx: 9, dy: 0))
    }

    @Test func noTimerWhileThePointerIsStill() async {
        let hub = makeHub()
        defer { withExtendedLifetime(hub) {} }
        source.move(800, 500, ms: 0)
        await settle()
        #expect(clock.sleeperCount == 0)
    }

    @Test func enteringTheNearBandFlushesImmediately() async {
        let hub = makeHub()
        hub.nearRegions = [CGRect(x: 0, y: 0, width: 100, height: 1000)]
        source.move(800, 500, dx: -1, ms: 0)
        source.move(400, 500, dx: -400, ms: 5) // held
        source.move(50, 500, dx: -350, ms: 10) // near: delivered with the held delta
        #expect(sink.samples.count == 2)
        #expect(sink.samples[1].delta.dx == -750)
        await settle()
        #expect(clock.sleeperCount == 0)
    }

    @Test func menuTrackingSwapsMonitorsForTimerAndBack() {
        let hub = makeHub()
        #expect(source.installCount == 1)
        hub.menuTrackingBegan()
        #expect(hub.mode == .menuTimer)
        #expect(!source.isInstalled)

        source.currentLocation = CGPoint(x: 10, y: 20)
        hub.menuTimerTick() // first tick after begin: baseline set at begin (0,0) → moved
        source.currentLocation = CGPoint(x: 13, y: 16)
        hub.menuTimerTick()
        hub.menuTimerTick() // unchanged: no sample
        #expect(sink.samples.count == 2)
        #expect(sink.samples[1].delta == CGVector(dx: 3, dy: -4))
        #expect(sink.samples[1].source == .menuTrackingTimer)

        hub.menuTrackingEnded()
        #expect(hub.mode == .monitors)
        #expect(source.isInstalled)
        #expect(source.installCount == 2)
    }

    @Test func nestedMenusRestoreMonitorsOnlyAfterTheOuterMenuEnds() {
        let hub = makeHub()
        hub.menuTrackingBegan()
        hub.menuTrackingBegan()
        hub.menuTrackingEnded()
        #expect(hub.mode == .menuTimer)
        hub.menuTrackingEnded()
        #expect(hub.mode == .monitors)
        hub.menuTrackingEnded() // unbalanced end is ignored
        #expect(hub.mode == .monitors)
    }

    @Test func sinksAreCalledInRegistrationOrderAndRemovable() {
        let hub = makeHub()
        let second = RecordingSink()
        hub.addSink(second)
        hub.nearRegions = [CGRect(x: 0, y: 0, width: 2000, height: 2000)]
        source.move(1, 1, ms: 0)
        #expect(sink.samples.count == 1 && second.samples.count == 1)
        hub.removeSink(second)
        source.move(2, 2, ms: 5)
        #expect(sink.samples.count == 2 && second.samples.count == 1)
    }

    @Test func nsEventDeltaYIsFlippedToYUp() {
        #expect(NSEventPointerSource.modifiers([.option, .shift]) == [.option, .shift])
    }
}
