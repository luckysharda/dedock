import Foundation
import Testing

/// A manual `Clock`: `sleep` resumes only when the test advances time.
final class TestClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration
        func advanced(by d: Duration) -> Instant { Instant(offset: offset + d) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (a: Instant, b: Instant) -> Bool { a.offset < b.offset }
    }

    private let lock = NSLock()
    private var _now = Instant(offset: .zero)
    private var sleepers: [(id: UInt64, deadline: Instant, cont: CheckedContinuation<Void, any Error>)] = []
    private var nextID: UInt64 = 0

    var now: Instant { lock.withLock { _now } }
    var minimumResolution: Duration { .nanoseconds(1) }
    var sleeperCount: Int { lock.withLock { sleepers.count } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id: UInt64 = lock.withLock { nextID += 1; return nextID }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
                enum Outcome { case wait, fire, cancelled }
                let outcome: Outcome = lock.withLock {
                    if Task.isCancelled { return .cancelled }
                    if deadline <= _now { return .fire }
                    sleepers.append((id, deadline, cont))
                    return .wait
                }
                switch outcome {
                case .fire: cont.resume()
                case .cancelled: cont.resume(throwing: CancellationError())
                case .wait: break
                }
            }
        } onCancel: {
            let cont: CheckedContinuation<Void, any Error>? = lock.withLock {
                guard let i = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return sleepers.remove(at: i).cont
            }
            cont?.resume(throwing: CancellationError())
        }
    }

    func advance(by d: Duration) {
        let due: [CheckedContinuation<Void, any Error>] = lock.withLock {
            _now = _now.advanced(by: d)
            let ready = sleepers.filter { $0.deadline <= _now }
            sleepers.removeAll { $0.deadline <= _now }
            return ready.map(\.cont)
        }
        due.forEach { $0.resume() }
    }
}

/// Lets queued main-actor tasks run.
@MainActor func settle(_ rounds: Int = 20) async {
    for _ in 0..<rounds { await Task.yield() }
}

/// Waits (by yielding) until `clock` has `count` sleepers registered.
@MainActor func waitForSleepers(_ clock: TestClock, _ count: Int = 1) async {
    for _ in 0..<500 where clock.sleeperCount < count { await Task.yield() }
}
