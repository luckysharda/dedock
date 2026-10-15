import Foundation

/// A `Clock` whose `sleep` resumes only when the test advances time. Deterministic timers
/// for controller tests (architecture §11).
public final class ManualClock: Clock, @unchecked Sendable {
    public struct Instant: InstantProtocol, Hashable, Sendable {
        public var offset: Duration
        public init(offset: Duration) { self.offset = offset }
        public func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        public func duration(to other: Instant) -> Duration { other.offset - offset }
        public static func < (a: Instant, b: Instant) -> Bool { a.offset < b.offset }
    }

    private struct Sleeper {
        let id: UInt64
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var _now = Instant(offset: .zero)
    private var sleepers: [Sleeper] = []
    private var nextID: UInt64 = 0

    public init() {}

    public var now: Instant { lock.withLock { _now } }
    public var minimumResolution: Duration { .nanoseconds(1) }

    /// Number of sleepers waiting (useful to await a timer being armed).
    public var pendingCount: Int { lock.withLock { sleepers.count } }

    public func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        let id: UInt64 = lock.withLock {
            nextID += 1
            return nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                let fireNow: Bool = lock.withLock {
                    if deadline <= _now { return true }
                    sleepers.append(Sleeper(id: id, deadline: deadline, continuation: c))
                    return false
                }
                if fireNow { c.resume() }
            }
        } onCancel: {
            let cancelled: Sleeper? = lock.withLock {
                guard let i = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return sleepers.remove(at: i)
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Advance time and resume every sleeper whose deadline has passed, in deadline order.
    public func advance(by duration: Duration) {
        let due: [Sleeper] = lock.withLock {
            _now = _now.advanced(by: duration)
            let ready = sleepers.filter { $0.deadline <= _now }.sorted { $0.deadline < $1.deadline }
            sleepers.removeAll { $0.deadline <= _now }
            return ready
        }
        for s in due { s.continuation.resume() }
    }
}
