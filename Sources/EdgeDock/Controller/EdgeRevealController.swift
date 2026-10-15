import DedockCore
import Diagnostics
import Foundation

/// The content layer's slide (or fade). Implemented by `SlideAnimator`; faked in tests.
@MainActor public protocol RevealAnimating: AnyObject {
    /// From the content layer's `presentation()`: 0 = hidden, 1 = shown.
    var presentationProgress: Double { get }
    /// Start from the presentation value, replacing any animation in flight. `completion` fires
    /// once with the request's generation when this animation finishes (not when replaced).
    func run(_ request: AnimationRequest, completion: @escaping @MainActor (UInt64) -> Void)
    /// Freeze at the presentation value.
    func stop()
    /// Jump to a target with no animation.
    func snap(to target: AnimationRequest.Target)
}

/// The DD-933 click-through gate (architecture §6.7).
@MainActor public protocol ClickThroughGating: AnyObject {
    /// Coarse layer: `false` makes the panel ignore every mouse event.
    func setInteractive(_ on: Bool)
    /// The capsule and tiles, AppKit global.
    func updateHitRegion(_ rects: [CGRect])
    /// Fine layer: while interactive, pass clicks through outside the hit region.
    func pointerMoved(_ location: CGPoint)
}

/// Feeds events to the pure `RevealStateMachine` and performs its effects: one-shot timer
/// tasks on an injected clock, the animator, the gate, panel ordering and logging (§6.6).
@MainActor public final class EdgeRevealController {
    public private(set) var machine: RevealStateMachine
    public var phase: RevealPhase { machine.phase }

    /// Called for `.orderIn` (`true`) / `.orderOut` (`false`).
    public var onOrder: ((Bool) -> Void)?
    /// Called after every transition, after the effects of the event ran.
    public var onTransition: ((RevealTransition) -> Void)?

    private let clock: any Clock<Duration>
    private let animator: any RevealAnimating
    private let gate: any ClickThroughGating
    private let edge: ScreenEdge
    private var timers: [TimerID: Task<Void, Never>] = [:]
    private var timerTokens: [TimerID: UInt64] = [:]
    private var nextToken: UInt64 = 0

    public init(config: RevealConfig, clock: any Clock<Duration>, animator: any RevealAnimating,
                gate: any ClickThroughGating, edge: ScreenEdge) {
        machine = RevealStateMachine(config: config)
        self.clock = clock
        self.animator = animator
        self.gate = gate
        self.edge = edge
        let shown = machine.phase == .shown
        animator.snap(to: shown ? .shown : .hidden)
        gate.setInteractive(shown)
    }

    public func send(_ events: [RevealEvent]) {
        for e in events { send(e) }
    }

    public func send(_ event: RevealEvent) {
        if case .hold(let token, let on) = event {
            DedockLog.event(.reveal, "inhibitor", ["edge": edge.rawValue, "token": token.rawValue, "on": on])
        }
        let effects = machine.handle(event, progress: animator.presentationProgress)
        perform(effects)
    }

    public func reconfigure(_ config: RevealConfig) {
        perform(machine.reconfigure(config))
    }

    /// Cancels every timer (on teardown).
    public func invalidate() {
        for task in timers.values { task.cancel() }
        timers.removeAll()
        timerTokens.removeAll()
    }

    private func perform(_ effects: [RevealEffect]) {
        var transitions: [RevealTransition] = []
        for effect in effects {
            switch effect {
            case .startTimer(let id, let delay):
                start(id, after: delay)
            case .cancelTimer(let id):
                timers.removeValue(forKey: id)?.cancel()
                timerTokens[id] = nil
            case .animate(let request):
                animator.run(request) { [weak self] generation in
                    self?.send(.animationFinished(generation: generation))
                }
            case .stopAnimation:
                animator.stop()
            case .snap(let target):
                animator.snap(to: target)
            case .setInteractive(let on):
                gate.setInteractive(on)
            case .orderIn:
                onOrder?(true)
            case .orderOut:
                onOrder?(false)
            case .trace(let t):
                // Logged in effect order: the machine emits the trace before the gate and the
                // animation it causes, so `reveal.transition` precedes `reveal.begin`.
                let inh = machine.holds.map(\.rawValue).sorted().joined(separator: ",")
                DedockLog.event(.reveal, "reveal.transition", [
                    "edge": edge.rawValue, "from": t.from.name, "to": t.to.name,
                    "cause": t.cause.rawValue, "inh": inh.isEmpty ? "-" : inh,
                ])
                transitions.append(t)
            }
        }
        for t in transitions { onTransition?(t) }
    }

    /// One-shot timer: a task that sleeps once on the clock, then fires. A token guards against
    /// a cancelled task that already woke (the machine also ignores stale fires).
    private func start(_ id: TimerID, after delay: Duration) {
        timers.removeValue(forKey: id)?.cancel()
        nextToken += 1
        let token = nextToken
        timerTokens[id] = token
        let clock = clock
        timers[id] = Task { @MainActor [weak self] in
            do {
                try await clock.sleep(for: delay)
            } catch {
                return
            }
            guard let self, self.timerTokens[id] == token else { return }
            self.timers[id] = nil
            self.timerTokens[id] = nil
            self.send(.timerFired(id))
        }
    }
}
