import Foundation
#if canImport(CoreGraphics)
import CoreGraphics // CGRect Hashable etc.; Linux Foundation provides these itself
#endif
import DedockCore

// Pure (architecture rule D5). The machine owns no clock, timer or panel: it takes an event
// plus the content's presentation progress and returns effects (architecture §6.5).

public enum RevealMode: String, Codable, Sendable { case reveal, pinned }

public enum RevealPhase: Sendable, Hashable {
    case hidden, arming(SegmentKind), revealing, shown, armingHide, hiding

    /// Contract name for logs and GEOM (`hidden|arming|revealing|shown|armingHide|hiding`).
    public var name: String {
        switch self {
        case .hidden: "hidden"
        case .arming: "arming"
        case .revealing: "revealing"
        case .shown: "shown"
        case .armingHide: "armingHide"
        case .hiding: "hiding"
        }
    }
}

public enum TimerID: String, Sendable, Hashable, CaseIterable { case dwell, hide, cooldown }

public enum Suppression: String, Sendable, Hashable, CaseIterable { case fullscreen, displayAsleep, spaceTransition, disabled }

public enum RevealCommand: Sendable, Equatable {
    case reveal
    /// `explicit` (a tile launch, Esc, the menu) starts the re-arm cooldown.
    case hide(explicit: Bool)
    case toggle
}

public enum RevealEvent: Sendable, Equatable {
    case zoneEntered(SegmentKind), zoneLeft, pushThrough, sharedSpeedExceeded, crossedToNeighbour
    case pointerInside(Bool), buttonHeld(Bool)
    case fullscreenChanged(Bool)
    case timerFired(TimerID)
    case animationFinished(generation: UInt64)
    case command(RevealCommand)
    case hold(HoldOpenToken, Bool)
    case suppression(Suppression, Bool)
}

public enum MotionCurve: String, Sendable, Hashable {
    /// `motion.edge.reveal`: critically damped spring, 99 % at 0.22 s.
    case revealSpring = "spring"
    /// Bezier (0.2, 0.7, 0.2, 1) for duration-scaled reversals into a reveal.
    case revealBezier = "bezier"
    /// `motion.edge.hide`: ease-in (0.42, 0, 1, 1).
    case hideEaseIn = "easeIn"
    /// Reduce Motion: opacity in place.
    case fade
}

public struct AnimationRequest: Sendable, Equatable {
    public enum Target: String, Sendable, Equatable { case shown, hidden }
    public let target: Target
    public let curve: MotionCurve
    public let duration: Duration
    public let generation: UInt64

    public init(target: Target, curve: MotionCurve, duration: Duration, generation: UInt64) {
        self.target = target
        self.curve = curve
        self.duration = duration
        self.generation = generation
    }
}

/// Why a transition happened (the `cause` key of `reveal.transition`).
public enum TransitionCause: String, Sendable, Equatable {
    case zone, dwell, push, leave, `return`, hideDelay, animationEnd, explicit, inhibitor, cooldown, settings, suppression, button
}

public struct RevealTransition: Sendable, Equatable {
    public let from: RevealPhase
    public let to: RevealPhase
    public let cause: TransitionCause
}

public enum RevealEffect: Sendable, Equatable {
    case startTimer(TimerID, Duration), cancelTimer(TimerID)
    /// Animate from the current presentation value, replacing any animation in flight.
    case animate(AnimationRequest)
    /// Freeze at the presentation value.
    case stopAnimation
    /// Jump to a target with no animation (suppression, pinned mode).
    case snap(AnimationRequest.Target)
    /// The DD-933 click-through gate, coarse layer. Emitted before the animation it belongs to.
    case setInteractive(Bool)
    case orderIn, orderOut
    case trace(RevealTransition)
}

public struct RevealConfig: Sendable, Hashable {
    public var mode: RevealMode = .reveal
    public var showDwell: Duration = .milliseconds(120)
    public var fullscreenDwell: Duration = .milliseconds(400)
    public var sharedDwell: Duration = .milliseconds(300)
    public var hideDelay: Duration = .milliseconds(400)
    public var cooldown: Duration = .milliseconds(500)
    public var revealDuration: Duration = .milliseconds(220)
    public var hideDuration: Duration = .milliseconds(180)
    public var reduceMotionDuration: Duration = .milliseconds(150)
    public var reverseFloor: Duration = .milliseconds(60)
    public var reduceMotion = false

    public init(mode: RevealMode = .reveal) { self.mode = mode }

    /// The animation from presentation progress `p` (0 hidden … 1 shown) to `target`. A start from
    /// rest takes the full duration; a reversal takes full × remaining travel, floored (DD-928).
    public func animation(to target: AnimationRequest.Target, from p: Double, generation: UInt64) -> AnimationRequest {
        let p = min(1, max(0, p))
        let remaining = target == .shown ? 1 - p : p
        let atRest = target == .shown ? p <= 0 : p >= 1
        func scaled(_ full: Duration) -> Duration { atRest ? full : max(reverseFloor, full * remaining) }

        if reduceMotion {
            return AnimationRequest(target: target, curve: .fade, duration: scaled(reduceMotionDuration), generation: generation)
        }
        switch target {
        case .shown:
            return AnimationRequest(target: .shown, curve: atRest ? .revealSpring : .revealBezier,
                                    duration: scaled(revealDuration), generation: generation)
        case .hidden:
            return AnimationRequest(target: .hidden, curve: .hideEaseIn, duration: scaled(hideDuration), generation: generation)
        }
    }
}

public struct RevealStateMachine: Sendable {
    public private(set) var phase: RevealPhase
    public private(set) var holds: Set<HoldOpenToken> = []
    public private(set) var suppressions: Set<Suppression> = []
    public private(set) var config: RevealConfig
    public private(set) var pointerInside = false
    public private(set) var isFullscreen = false
    public private(set) var isCoolingDown = false
    /// Generation of the animation in flight, if any.
    public private(set) var activeGeneration: UInt64?

    private var generation: UInt64 = 0
    private var hideTimerRunning = false
    /// After an explicit reveal (menu, hotkey) the pointer is usually elsewhere; the dock stays
    /// until the pointer has visited it once, then the normal hide rules apply.
    public private(set) var awaitingFirstVisit = false

    public init(config: RevealConfig = .init()) {
        self.config = config
        phase = config.mode == .pinned ? .shown : .hidden
    }

    private var isHeld: Bool { !holds.isEmpty }
    private var isSuppressed: Bool { !suppressions.isEmpty }

    public mutating func handle(_ event: RevealEvent, progress p: Double) -> [RevealEffect] {
        // Bookkeeping in every phase.
        switch event {
        case .pointerInside(let on):
            pointerInside = on
            if on { awaitingFirstVisit = false }
        case .zoneEntered:
            pointerInside = true
            awaitingFirstVisit = false
        case .hold(let token, let on):
            if on { holds.insert(token) } else { holds.remove(token) }
        case .fullscreenChanged(let on): isFullscreen = on
        case .timerFired(.cooldown): isCoolingDown = false
        case .suppression(let s, let on): return handleSuppression(s, on, p)
        default: break
        }
        guard !isSuppressed else { return [] }

        // Pinned (DD-911): always shown; only suppression flags move it.
        if config.mode == .pinned { return [] }

        switch phase {
        case .hidden: return hidden(event, p)
        case .arming(let kind): return arming(kind, event, p)
        case .revealing: return revealing(event, p)
        case .shown: return shown(event, p)
        case .armingHide: return armingHide(event, p)
        case .hiding: return hiding(event, p)
        }
    }

    /// Apply new settings. Mode changes move the dock at once; timing changes apply to the next timer.
    public mutating func reconfigure(_ new: RevealConfig) -> [RevealEffect] {
        let old = config
        config = new
        guard old.mode != new.mode, !isSuppressed else { return [] }
        var effects = cancelAllTimers()
        switch new.mode {
        case .pinned:
            effects += [.setInteractive(true), .stopAnimation, .snap(.shown)]
            effects += go(.shown, .settings)
        case .reveal:
            effects += [.setInteractive(false), .stopAnimation, .snap(.hidden)]
            effects += go(.hidden, .settings)
        }
        activeGeneration = nil
        return effects
    }

    // MARK: - Phases

    private mutating func hidden(_ e: RevealEvent, _ p: Double) -> [RevealEffect] {
        switch e {
        case .zoneEntered(let kind):
            guard !isCoolingDown else { return [] }
            let dwell = dwell(for: kind)
            if dwell <= .zero { return reveal(from: p, cause: .dwell) }
            return go(.arming(kind), .zone) + [.startTimer(.dwell, dwell)]
        case .command(.reveal), .command(.toggle):
            return explicitReveal(from: p)
        default:
            return []
        }
    }

    private mutating func arming(_ kind: SegmentKind, _ e: RevealEvent, _ p: Double) -> [RevealEffect] {
        switch e {
        case .zoneLeft, .crossedToNeighbour:
            return [.cancelTimer(.dwell)] + go(.hidden, .leave)
        case .buttonHeld(true):
            return [.cancelTimer(.dwell)] + go(.hidden, .button)
        case .timerFired(.dwell):
            return reveal(from: p, cause: .dwell)
        case .pushThrough where kind == .wall:
            return [.cancelTimer(.dwell)] + reveal(from: p, cause: .push)
        case .sharedSpeedExceeded where kind == .shared:
            return [.cancelTimer(.dwell), .startTimer(.dwell, dwell(for: kind))]
        case .zoneEntered(let newKind) where newKind != kind:
            return [.cancelTimer(.dwell)] + go(.arming(newKind), .zone) + [.startTimer(.dwell, dwell(for: newKind))]
        case .command(.reveal), .command(.toggle):
            return [.cancelTimer(.dwell)] + explicitReveal(from: p)
        case .command(.hide(let explicit)):
            var effects: [RevealEffect] = [.cancelTimer(.dwell)] + go(.hidden, .explicit)
            if explicit { effects += startCooldown() }
            return effects
        default:
            return []
        }
    }

    private mutating func revealing(_ e: RevealEvent, _ p: Double) -> [RevealEffect] {
        switch e {
        case .animationFinished(let g) where g == activeGeneration:
            activeGeneration = nil
            if hideTimerRunning { return go(.armingHide, .animationEnd) }
            return go(.shown, .animationEnd)
        case .pointerInside, .hold, .zoneEntered:
            // A short hide delay can expire mid-reveal (system-design §4.2), so the hide timer
            // also runs while revealing.
            return syncHideTimerWhileRevealing()
        case .timerFired(.hide):
            guard hideTimerRunning else { return [] }
            hideTimerRunning = false
            guard !pointerInside, !isHeld else { return [] }
            return hide(from: p, cause: .hideDelay)
        case .command(.hide(let explicit)):
            return explicitHide(from: p, startCooldown: explicit)
        case .command(.toggle):
            return explicitHide(from: p, startCooldown: true)
        default:
            // zoneEntered / pushThrough / reveal: already heading to shown (DD-928 no-op).
            return []
        }
    }

    private mutating func shown(_ e: RevealEvent, _ p: Double) -> [RevealEffect] {
        switch e {
        case .pointerInside, .hold:
            return evaluateHideIntent()
        case .command(.hide(let explicit)):
            return explicitHide(from: p, startCooldown: explicit)
        case .command(.toggle):
            return explicitHide(from: p, startCooldown: true)
        default:
            return []
        }
    }

    private mutating func armingHide(_ e: RevealEvent, _ p: Double) -> [RevealEffect] {
        switch e {
        case .pointerInside, .hold, .zoneEntered:
            if pointerInside || isHeld {
                hideTimerRunning = false
                let cause: TransitionCause = if case .hold = e { .inhibitor } else { .return }
                return [.cancelTimer(.hide)] + go(.shown, cause)
            }
            return []
        case .timerFired(.hide):
            guard hideTimerRunning else { return [] }
            hideTimerRunning = false
            return hide(from: p, cause: .hideDelay)
        case .command(.hide(let explicit)):
            return explicitHide(from: p, startCooldown: explicit)
        case .command(.toggle):
            return explicitHide(from: p, startCooldown: true)
        default:
            return []
        }
    }

    private mutating func hiding(_ e: RevealEvent, _ p: Double) -> [RevealEffect] {
        switch e {
        case .animationFinished(let g) where g == activeGeneration:
            activeGeneration = nil
            return go(.hidden, .animationEnd)
        case .pointerInside(true), .zoneEntered:
            // Reverse in place, no dwell: the intent is already "shown" (DD-928). Not during the
            // re-arm cooldown after an explicit hide: the pointer is usually still on the tile it
            // clicked (PR #7 review item 2).
            guard !isCoolingDown else { return [] }
            return reveal(from: p, cause: .return)
        case .command(.reveal), .command(.toggle):
            return explicitReveal(from: p)
        case .command(.hide(true)):
            return isCoolingDown ? [] : startCooldown()
        default:
            return []
        }
    }

    // MARK: - Transitions

    private mutating func go(_ to: RevealPhase, _ cause: TransitionCause) -> [RevealEffect] {
        let from = phase
        phase = to
        return from == to ? [] : [.trace(RevealTransition(from: from, to: to, cause: cause))]
    }

    private func dwell(for kind: SegmentKind) -> Duration {
        switch kind {
        case .wall: isFullscreen ? config.fullscreenDwell : config.showDwell
        case .shared: max(config.sharedDwell, isFullscreen ? config.fullscreenDwell : .zero)
        }
    }

    private mutating func reveal(from p: Double, cause: TransitionCause) -> [RevealEffect] {
        var effects = go(.revealing, cause)
        effects.append(.setInteractive(true))
        effects.append(.animate(nextAnimation(to: .shown, from: p)))
        effects += syncHideTimerWhileRevealing()
        return effects
    }

    private mutating func explicitReveal(from p: Double) -> [RevealEffect] {
        awaitingFirstVisit = !pointerInside
        return reveal(from: p, cause: .explicit)
    }

    private mutating func hide(from p: Double, cause: TransitionCause) -> [RevealEffect] {
        hideTimerRunning = false
        awaitingFirstVisit = false
        return go(.hiding, cause) + [.setInteractive(false), .animate(nextAnimation(to: .hidden, from: p))]
    }

    private mutating func explicitHide(from p: Double, startCooldown cooldown: Bool) -> [RevealEffect] {
        var effects: [RevealEffect] = []
        if hideTimerRunning { effects.append(.cancelTimer(.hide)) }
        effects += hide(from: p, cause: .explicit)
        if cooldown { effects += startCooldown() }
        return effects
    }

    private mutating func startCooldown() -> [RevealEffect] {
        isCoolingDown = true
        return [.startTimer(.cooldown, config.cooldown)]
    }

    private mutating func nextAnimation(to target: AnimationRequest.Target, from p: Double) -> AnimationRequest {
        generation += 1
        activeGeneration = generation
        return config.animation(to: target, from: p, generation: generation)
    }

    private mutating func evaluateHideIntent() -> [RevealEffect] {
        if pointerInside || isHeld || awaitingFirstVisit {
            guard phase == .armingHide else { return [] }
            hideTimerRunning = false
            return [.cancelTimer(.hide)] + go(.shown, .return)
        }
        hideTimerRunning = true
        return go(.armingHide, .leave) + [.startTimer(.hide, config.hideDelay)]
    }

    private mutating func syncHideTimerWhileRevealing() -> [RevealEffect] {
        let shouldRun = !pointerInside && !isHeld && !awaitingFirstVisit
        guard shouldRun != hideTimerRunning else { return [] }
        hideTimerRunning = shouldRun
        return shouldRun ? [.startTimer(.hide, config.hideDelay)] : [.cancelTimer(.hide)]
    }

    private mutating func cancelAllTimers() -> [RevealEffect] {
        hideTimerRunning = false
        return [.cancelTimer(.dwell), .cancelTimer(.hide)]
    }

    private mutating func handleSuppression(_ s: Suppression, _ on: Bool, _ p: Double) -> [RevealEffect] {
        let wasSuppressed = isSuppressed
        if on { suppressions.insert(s) } else { suppressions.remove(s) }
        switch (wasSuppressed, isSuppressed) {
        case (false, true):
            activeGeneration = nil
            return cancelAllTimers() + [.setInteractive(false), .stopAnimation, .snap(.hidden), .orderOut]
                + go(.hidden, .suppression)
        case (true, false):
            if config.mode == .pinned {
                return [.snap(.shown), .orderIn, .setInteractive(true)] + go(.shown, .suppression)
            }
            return [.snap(.hidden), .orderIn]
        default:
            return []
        }
    }
}
