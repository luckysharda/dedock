import Foundation

/// The Edge Dock reveal state machine for one dock instance (DD-912, DD-928, DD-929;
/// system-design §4.2).
///
/// A pure reducer: events in, effects out. It owns no clock and no animation. The runtime
/// executes timer effects as one-shot timers and feeds `timerFired` back, and passes the
/// content layer's *presentation* progress with every event, because reversals start from
/// where the dock actually is on screen, not from elapsed time (system-design §3.3.1).
public struct RevealMachine: Sendable {
    public enum State: String, Sendable, Equatable, CaseIterable {
        case hidden, arming, revealing, shown, armingHide, hiding
    }

    public enum Mode: String, Sendable, Equatable {
        /// Hidden until the pointer reaches the edge (DD-912).
        case reveal
        /// Always shown (DD-911). Pointer and timer events are ignored.
        case pinned
    }

    /// Where the pointer is relative to this dock.
    public enum PointerRegion: Sendable, Equatable {
        /// Inside the shown dock frame or a hot zone.
        case onDock
        /// Outside the dock frame but within the hide hysteresis outset.
        case nearDock
        /// Further away.
        case away
    }

    public enum Timer: String, Sendable, Equatable, CaseIterable {
        /// Show delay (dwell) while arming.
        case dwell
        /// Hide delay after the pointer leaves.
        case hideDelay
        /// Re-arm cooldown after an explicit hide.
        case cooldown
    }

    public enum Event: Sendable, Equatable {
        case enteredZone(HotZone.Kind)
        case leftZone
        /// Accumulated push toward the edge reached the push-through distance.
        case pushThrough
        /// The pointer moved too fast inside a shared band; restart its dwell (DD-931).
        case restartDwell
        case pointer(PointerRegion)
        case timerFired(Timer)
        /// The animation with this id finished. Stale ids (superseded animations) are ignored.
        case animationFinished(id: Int)
        case holdOpen(HoldOpenToken, active: Bool)
        /// The display's active Space is full screen (selects the longer dwell, DD-924).
        case fullscreenSpace(Bool)
        /// Hotkey, menu, script or drag reveal: no dwell.
        case explicitReveal
        /// Hotkey, Esc or a launch from a tile. Starts the re-arm cooldown.
        case explicitHide
    }

    public enum Effect: Sendable, Equatable {
        case startTimer(Timer, after: TimeInterval)
        case cancelTimer(Timer)
        /// Click-through gate (DD-933). Always emitted *before* the animation it belongs to:
        /// interactive at the start of a reveal, pass-through at the start of a hide.
        case setInteractive(Bool)
        /// Animate the content layer from its current presentation value.
        case animate(id: Int, RevealAnimationSpec)
    }

    public struct Timing: Sendable, Equatable {
        public var showDelay: TimeInterval = 0.12
        public var fullscreenShowDelay: TimeInterval = 0.40
        /// Shared-edge slow dwell (system-design §5.4).
        public var sharedShowDelay: TimeInterval = 0.30
        public var hideDelay: TimeInterval = 0.40
        public var rearmCooldown: TimeInterval = 0.50
        public init() {}
    }

    public private(set) var state: State
    public private(set) var holdOpen: Set<HoldOpenToken> = []
    public private(set) var pointerRegion: PointerRegion = .away
    public private(set) var isCoolingDown = false
    public private(set) var isFullscreenSpace = false
    /// Id of the animation currently in flight, if any.
    public private(set) var activeAnimationID: Int?

    public let mode: Mode
    public var timing: Timing
    public var motion: RevealMotion

    private var nextAnimationID = 1
    private var armedZoneKind: HotZone.Kind = .wall
    private var hideTimerRunning = false

    public init(mode: Mode = .reveal, timing: Timing = .init(), motion: RevealMotion = .init()) {
        self.mode = mode
        self.timing = timing
        self.motion = motion
        self.state = mode == .pinned ? .shown : .hidden
    }

    /// The pointer counts as on the dock for hide decisions (frame + hysteresis, or a zone).
    private var pointerHolds: Bool { pointerRegion != .away }
    private var isHeldOpen: Bool { !holdOpen.isEmpty }

    /// Handle one event.
    /// - Parameter presentation: The content layer's current presentation progress
    ///   (0 = fully hidden, 1 = fully shown).
    public mutating func handle(_ event: Event, presentation: Double) -> [Effect] {
        // Bookkeeping that applies in every state.
        switch event {
        case .pointer(let region): pointerRegion = region
        // A hot zone counts as part of the dock; the evaluator's region update follows.
        case .enteredZone: pointerRegion = .onDock
        case .holdOpen(let token, let active):
            if active { holdOpen.insert(token) } else { holdOpen.remove(token) }
        case .fullscreenSpace(let on): isFullscreenSpace = on
        case .timerFired(.cooldown): isCoolingDown = false
        default: break
        }
        guard mode == .reveal else { return [] }

        switch state {
        case .hidden: return handleHidden(event, presentation)
        case .arming: return handleArming(event, presentation)
        case .revealing: return handleRevealing(event, presentation)
        case .shown: return handleShown(event, presentation)
        case .armingHide: return handleArmingHide(event, presentation)
        case .hiding: return handleHiding(event, presentation)
        }
    }

    // MARK: - States

    private mutating func handleHidden(_ event: Event, _ p: Double) -> [Effect] {
        switch event {
        case .enteredZone(let kind):
            guard !isCoolingDown else { return [] }
            armedZoneKind = kind
            let delay = dwell(for: kind)
            if delay <= 0 { return reveal(from: p) }
            state = .arming
            return [.startTimer(.dwell, after: delay)]
        case .explicitReveal:
            return reveal(from: p)
        default:
            return []
        }
    }

    private mutating func handleArming(_ event: Event, _ p: Double) -> [Effect] {
        switch event {
        case .leftZone:
            state = .hidden
            return [.cancelTimer(.dwell)]
        case .timerFired(.dwell):
            return reveal(from: p)
        case .pushThrough:
            // Push-through applies to wall edges only; a shared band needs the slow dwell.
            guard armedZoneKind == .wall else { return [] }
            return [.cancelTimer(.dwell)] + reveal(from: p)
        case .explicitReveal:
            return [.cancelTimer(.dwell)] + reveal(from: p)
        case .restartDwell:
            return [.cancelTimer(.dwell), .startTimer(.dwell, after: dwell(for: armedZoneKind))]
        case .fullscreenSpace:
            return []
        case .explicitHide:
            state = .hidden
            isCoolingDown = true
            return [.cancelTimer(.dwell), .startTimer(.cooldown, after: timing.rearmCooldown)]
        default:
            return []
        }
    }

    private mutating func handleRevealing(_ event: Event, _ p: Double) -> [Effect] {
        switch event {
        case .animationFinished(let id) where id == activeAnimationID:
            activeAnimationID = nil
            if hideTimerRunning {
                state = .armingHide
                return []
            }
            state = .shown
            return evaluateHideIntent()
        case .pointer, .holdOpen:
            // A short hide delay can expire mid-reveal (system-design §4.2, case B), so the
            // hide timer runs while revealing too.
            return updateHideTimerWhileRevealing()
        case .timerFired(.hideDelay):
            guard hideTimerRunning else { return [] }
            hideTimerRunning = false
            guard !pointerHolds, !isHeldOpen else { return [] }
            return hide(from: p)
        case .explicitHide:
            return explicitHide(from: p)
        default:
            // enteredZone / pushThrough / explicitReveal: already heading to shown (DD-928 no-op).
            return []
        }
    }

    private mutating func handleShown(_ event: Event, _ p: Double) -> [Effect] {
        switch event {
        case .pointer, .holdOpen:
            return evaluateHideIntent()
        case .explicitHide:
            return explicitHide(from: p)
        default:
            return []
        }
    }

    private mutating func handleArmingHide(_ event: Event, _ p: Double) -> [Effect] {
        switch event {
        case .pointer, .holdOpen:
            if pointerHolds || isHeldOpen {
                state = .shown
                hideTimerRunning = false
                return [.cancelTimer(.hideDelay)]
            }
            return []
        case .enteredZone:
            state = .shown
            hideTimerRunning = false
            return [.cancelTimer(.hideDelay)]
        case .timerFired(.hideDelay):
            guard hideTimerRunning else { return [] }
            hideTimerRunning = false
            return hide(from: p)
        case .explicitHide:
            return explicitHide(from: p)
        default:
            return []
        }
    }

    private mutating func handleHiding(_ event: Event, _ p: Double) -> [Effect] {
        switch event {
        case .animationFinished(let id) where id == activeAnimationID:
            activeAnimationID = nil
            state = .hidden
            return []
        case .pointer(.onDock), .enteredZone, .explicitReveal:
            // Reverse in place, dwell skipped: the intent is already "shown" (DD-928).
            return reveal(from: p)
        default:
            // explicitHide while hiding is a no-op (DD-928).
            return []
        }
    }

    // MARK: - Transitions

    private func dwell(for kind: HotZone.Kind) -> TimeInterval {
        switch kind {
        case .shared: max(timing.sharedShowDelay, isFullscreenSpace ? timing.fullscreenShowDelay : 0)
        case .wall: isFullscreenSpace ? timing.fullscreenShowDelay : timing.showDelay
        }
    }

    private mutating func reveal(from p: Double) -> [Effect] {
        state = .revealing
        var effects: [Effect] = [.setInteractive(true)]
        effects.append(startAnimation(motion.animation(to: .shown, from: p)))
        effects += updateHideTimerWhileRevealing()
        return effects
    }

    private mutating func hide(from p: Double) -> [Effect] {
        state = .hiding
        hideTimerRunning = false
        return [.setInteractive(false), startAnimation(motion.animation(to: .hidden, from: p))]
    }

    private mutating func explicitHide(from p: Double) -> [Effect] {
        var effects: [Effect] = []
        if hideTimerRunning { effects.append(.cancelTimer(.hideDelay)) }
        effects += hide(from: p)
        isCoolingDown = true
        effects.append(.startTimer(.cooldown, after: timing.rearmCooldown))
        return effects
    }

    private mutating func startAnimation(_ spec: RevealAnimationSpec) -> Effect {
        let id = nextAnimationID
        nextAnimationID += 1
        activeAnimationID = id
        return .animate(id: id, spec)
    }

    /// In `shown` / `armingHide`: start or cancel the hide delay from the pointer and inhibitors.
    private mutating func evaluateHideIntent() -> [Effect] {
        if pointerHolds || isHeldOpen {
            if state == .armingHide {
                state = .shown
                hideTimerRunning = false
                return [.cancelTimer(.hideDelay)]
            }
            return []
        }
        state = .armingHide
        hideTimerRunning = true
        return [.startTimer(.hideDelay, after: timing.hideDelay)]
    }

    private mutating func updateHideTimerWhileRevealing() -> [Effect] {
        let shouldRun = !pointerHolds && !isHeldOpen
        guard shouldRun != hideTimerRunning else { return [] }
        hideTimerRunning = shouldRun
        return shouldRun ? [.startTimer(.hideDelay, after: timing.hideDelay)] : [.cancelTimer(.hideDelay)]
    }
}

/// Hold-open inhibitors (DD-929; system-design §4.2). While any is active the dock never hides
/// on its own.
public enum HoldOpenToken: String, Sendable, Hashable, CaseIterable {
    case dragging, menuOpen, previewOpen, popoverOpen, editing, textFocus, pinnedByUser
}
