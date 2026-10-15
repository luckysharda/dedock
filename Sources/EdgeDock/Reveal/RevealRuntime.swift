import DedockCore
import Dispatch
import Foundation

/// The content layer and click-through gate that `RevealRuntime` drives. Implemented by the
/// dock panel; faked in tests.
@MainActor public protocol RevealPresenting: AnyObject {
    /// The content's on-screen (presentation-layer) progress: 0 = fully hidden, 1 = fully shown.
    var presentationProgress: Double { get }
    /// Click-through gate (DD-933): `false` makes the panel ignore mouse events.
    func setInteractive(_ interactive: Bool)
    /// Start animating from the current presentation value, replacing any animation in flight.
    /// Call `completion` once when this animation finishes (not when it is replaced).
    func animate(_ spec: RevealAnimationSpec, completion: @escaping @MainActor () -> Void)
}

/// One-shot timers. Implementations must fire as close as possible to the deadline, with no
/// fixed-rate polling (DD-912 criterion 3: within 16 ms).
@MainActor public protocol OneShotScheduling: AnyObject {
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> ScheduledToken
}

/// Cancels a scheduled one-shot.
@MainActor public final class ScheduledToken {
    private var onCancel: (() -> Void)?
    public init(onCancel: @escaping () -> Void) { self.onCancel = onCancel }
    public func cancel() {
        onCancel?()
        onCancel = nil
    }
}

/// Main-queue one-shot timers. The main queue also drains during `NSMenu` tracking, so timers
/// keep firing while a context menu is open.
@MainActor public final class MainQueueScheduler: OneShotScheduling {
    public init() {}

    public func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> ScheduledToken {
        let item = DispatchWorkItem {
            MainActor.assumeIsolated { action() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: item)
        return ScheduledToken { item.cancel() }
    }
}

/// Runs one dock instance's reveal: pointer samples → `TriggerEvaluator` → `RevealMachine`
/// → timers and the presenter.
@MainActor public final class RevealRuntime {
    public private(set) var machine: RevealMachine
    public private(set) var evaluator: TriggerEvaluator
    public var onStateChange: ((RevealMachine.State) -> Void)?

    private let presenter: RevealPresenting
    private let scheduler: OneShotScheduling
    private var timers: [RevealMachine.Timer: ScheduledToken] = [:]

    public init(
        machine: RevealMachine,
        evaluator: TriggerEvaluator,
        presenter: RevealPresenting,
        scheduler: OneShotScheduling
    ) {
        self.machine = machine
        self.evaluator = evaluator
        self.presenter = presenter
        self.scheduler = scheduler
        presenter.setInteractive(machine.state == .shown)
    }

    public var state: RevealMachine.State { machine.state }

    public func pointer(_ sample: PointerSample) {
        for event in evaluator.evaluate(sample) { send(event) }
    }

    public func updateGeometry(zones: [HotZone], dockFrame: CGRect?) {
        evaluator.update(zones: zones, dockFrame: dockFrame)
    }

    public func send(_ event: RevealMachine.Event) {
        let before = machine.state
        let effects = machine.handle(event, presentation: presenter.presentationProgress)
        for effect in effects { perform(effect) }
        if machine.state != before { onStateChange?(machine.state) }
    }

    private func perform(_ effect: RevealMachine.Effect) {
        switch effect {
        case .startTimer(let timer, let delay):
            timers[timer]?.cancel()
            timers[timer] = scheduler.schedule(after: delay) { [weak self] in
                guard let self else { return }
                self.timers[timer] = nil
                self.send(.timerFired(timer))
            }
        case .cancelTimer(let timer):
            timers[timer]?.cancel()
            timers[timer] = nil
        case .setInteractive(let interactive):
            presenter.setInteractive(interactive)
        case .animate(let id, let spec):
            presenter.animate(spec) { [weak self] in
                self?.send(.animationFinished(id: id))
            }
        }
    }
}
