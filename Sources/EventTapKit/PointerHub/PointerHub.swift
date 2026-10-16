import AppKit
import DedockCore
import Diagnostics

/// Receives pointer samples, synchronously on the main actor, in registration order.
@MainActor public protocol PointerSampleSink: AnyObject {
    func pointer(_ sample: PointerSample)
}

/// The OS edge: NSEvent monitors in the app, a fake in tests.
@MainActor public protocol PointerEventSource: AnyObject {
    func install(_ handler: @escaping @MainActor (PointerSample) -> Void)
    func uninstall()
    /// `NSEvent.mouseLocation` (AppKit global).
    var currentLocation: CGPoint { get }
    /// `NSEvent.pressedMouseButtons != 0`.
    var buttonsDown: Bool { get }
    /// Current modifier keys (`NSEvent.modifierFlags`).
    var currentModifiers: ModifierSet { get }
}

/// Edge sensing input (architecture §6.3). Turns monitor events into throttled `PointerSample`s.
///
/// - Inside any `nearRegions` rect every event is delivered.
/// - Outside, at most `farFieldRate` Hz, plus a trailing sample so the last position before the
///   pointer stops is always delivered. Deltas accumulate on every event, throttled or not, and
///   travel with the next delivered sample.
/// - While one of dedock's own `NSMenu`s tracks, global-monitor delivery stalls, so the monitors
///   are swapped for a 30 Hz `.common`-mode timer that reads the pointer position.
/// - No timer runs while the pointer is still.
@MainActor public final class PointerHub {
    public enum Mode: String, Sendable { case monitors, menuTimer }

    /// Rects where every event is delivered unthrottled (zones and capsules outset by 96 pt).
    public var nearRegions: [CGRect] = []
    public private(set) var mode: Mode = .monitors
    public private(set) var isRunning = false

    private let source: any PointerEventSource
    private let clock: any Clock<Duration>
    private let farInterval: Duration
    private let menuTimerRate: Double

    private struct SinkBox { weak var sink: (any PointerSampleSink)? }
    private var sinks: [SinkBox] = []

    private var accumulated = CGVector.zero
    private var lastDelivered: Duration?
    private var pending: PointerSample?
    private var trailingTask: Task<Void, Never>?

    private var menuTimer: Timer?
    private var menuDepth = 0
    private var lastTimerLocation: CGPoint?
    private var menuObservers: [any NSObjectProtocol] = []

    public init(source: any PointerEventSource, clock: any Clock<Duration> = ContinuousClock(),
                farFieldRate: Double = 15, menuTimerRate: Double = 30) {
        self.source = source
        self.clock = clock
        farInterval = .nanoseconds(Int64((1e9 / farFieldRate).rounded()))
        self.menuTimerRate = menuTimerRate
    }

    public func addSink(_ sink: any PointerSampleSink) {
        sinks.removeAll { $0.sink == nil || $0.sink === sink }
        sinks.append(SinkBox(sink: sink))
    }

    public func removeSink(_ sink: any PointerSampleSink) {
        sinks.removeAll { $0.sink == nil || $0.sink === sink }
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        installMonitors()
        let center = NotificationCenter.default
        menuObservers = [
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.menuTrackingBegan() }
            },
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.menuTrackingEnded() }
            },
        ]
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        menuObservers.forEach(NotificationCenter.default.removeObserver)
        menuObservers = []
        stopMenuTimer()
        menuDepth = 0
        mode = .monitors
        source.uninstall()
        cancelTrailing()
        accumulated = .zero
        lastDelivered = nil
    }

    // MARK: - Monitor path

    private func installMonitors() {
        source.install { [weak self] sample in self?.receive(sample) }
    }

    /// Entry point for every raw event (also used by tests through the fake source).
    func receive(_ raw: PointerSample) {
        accumulated.dx += raw.delta.dx
        accumulated.dy += raw.delta.dy

        if isNear(raw.location) {
            cancelTrailing()
            deliver(raw)
            return
        }
        if let last = lastDelivered, raw.timestamp - last < farInterval {
            pending = raw
            scheduleTrailing(after: farInterval - (raw.timestamp - last))
            return
        }
        cancelTrailing()
        deliver(raw)
    }

    private func isNear(_ p: CGPoint) -> Bool {
        nearRegions.contains { p.x >= $0.minX && p.x <= $0.maxX && p.y >= $0.minY && p.y <= $0.maxY }
    }

    private func deliver(_ raw: PointerSample) {
        var sample = raw
        sample.delta = accumulated
        accumulated = .zero
        lastDelivered = raw.timestamp
        pending = nil
        for box in sinks { box.sink?.pointer(sample) }
    }

    private func scheduleTrailing(after delay: Duration) {
        guard trailingTask == nil else { return }
        let clock = clock
        trailingTask = Task { @MainActor [weak self] in
            do { try await clock.sleep(for: delay, tolerance: .zero) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.trailingTask = nil
            if let pending = self.pending { self.deliver(pending) }
        }
    }

    private func cancelTrailing() {
        trailingTask?.cancel()
        trailingTask = nil
    }

    // MARK: - Menu-tracking fallback

    /// The run-loop mode of the menu-tracking timer: `.common`, so it fires while a menu tracks
    /// (row 35 pin).
    static let menuTimerMode: RunLoop.Mode = .common
    /// The running menu-tracking timer's interval (tests).
    var menuTimerInterval: TimeInterval? { menuTimer?.timeInterval }

    /// Called on `NSMenu.didBeginTrackingNotification` (internal so tests can drive it).
    func menuTrackingBegan() {
        menuDepth += 1
        guard menuDepth == 1, isRunning else { return }
        source.uninstall()
        cancelTrailing()
        if let pending { deliver(pending) }
        mode = .menuTimer
        lastTimerLocation = source.currentLocation
        DedockLog.event(.pointer, "pointer.mode", ["mode": Mode.menuTimer.rawValue])
        let timer = Timer(timeInterval: 1 / menuTimerRate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuTimerTick() }
        }
        RunLoop.main.add(timer, forMode: Self.menuTimerMode)
        menuTimer = timer
    }

    /// Called on `NSMenu.didEndTrackingNotification`.
    func menuTrackingEnded() {
        guard menuDepth > 0 else { return }
        menuDepth -= 1
        guard menuDepth == 0, mode == .menuTimer else { return }
        stopMenuTimer()
        mode = .monitors
        DedockLog.event(.pointer, "pointer.mode", ["mode": Mode.monitors.rawValue])
        if isRunning { installMonitors() }
    }

    /// One 30 Hz tick while a menu tracks: a sample only when the pointer moved or buttons changed.
    func menuTimerTick() {
        let location = source.currentLocation
        let previous = lastTimerLocation ?? location
        lastTimerLocation = location
        guard location != previous else { return }
        let sample = PointerSample(
            location: location,
            delta: CGVector(dx: location.x - previous.x, dy: location.y - previous.y),
            timestamp: Self.uptime(),
            buttonsDown: source.buttonsDown,
            modifiers: source.currentModifiers,
            source: .menuTrackingTimer)
        accumulated.dx += sample.delta.dx
        accumulated.dy += sample.delta.dy
        deliver(sample)
    }

    private func stopMenuTimer() {
        menuTimer?.invalidate()
        menuTimer = nil
        lastTimerLocation = nil
    }

    /// Time since boot, the same base as `NSEvent.timestamp`.
    static func uptime() -> Duration {
        .nanoseconds(Int64((ProcessInfo.processInfo.systemUptime * 1e9).rounded()))
    }
}
