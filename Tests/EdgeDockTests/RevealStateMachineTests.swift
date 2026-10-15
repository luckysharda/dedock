import DedockCore
import Foundation
import Testing
@testable import EdgeDock

typealias SM = RevealStateMachine

extension Duration {
    var ms: Double { (seconds * 1000).rounded() }
}

/// Effects with traces dropped and durations rounded to ms, generations erased.
func plain(_ effects: [RevealEffect]) -> [String] {
    effects.compactMap { e in
        switch e {
        case .trace: nil
        case .startTimer(let id, let d): "start(\(id.rawValue),\(Int(d.ms)))"
        case .cancelTimer(let id): "cancel(\(id.rawValue))"
        case .animate(let r): "animate(\(r.target.rawValue),\(r.curve.rawValue),\(Int(r.duration.ms)))"
        case .stopAnimation: "stop"
        case .snap(let t): "snap(\(t.rawValue))"
        case .setInteractive(let on): "gate(\(on))"
        case .orderIn: "orderIn"
        case .orderOut: "orderOut"
        }
    }
}

func traces(_ effects: [RevealEffect]) -> [RevealTransition] {
    effects.compactMap { if case .trace(let t) = $0 { t } else { nil } }
}

/// Reach a phase through public events only.
func machine(in phase: RevealPhase, config: RevealConfig = .init()) -> SM {
    var m = SM(config: config)
    func send(_ e: RevealEvent, _ p: Double) { _ = m.handle(e, progress: p) }
    switch phase {
    case .hidden: break
    case .arming(let kind): send(.zoneEntered(kind), 0)
    case .revealing:
        send(.zoneEntered(.wall), 0); send(.timerFired(.dwell), 0)
    case .shown:
        send(.zoneEntered(.wall), 0); send(.timerFired(.dwell), 0)
        send(.animationFinished(generation: m.activeGeneration!), 1)
    case .armingHide:
        m = machine(in: .shown, config: config)
        send(.zoneLeft, 1); send(.pointerInside(false), 1)
    case .hiding:
        m = machine(in: .armingHide, config: config)
        send(.timerFired(.hide), 1)
    }
    precondition(m.phase == phase, "fixture reached \(m.phase), wanted \(phase)")
    return m
}

@Suite struct RevealTransitionTableTests {
    struct Row: Sendable, CustomTestStringConvertible {
        let from: RevealPhase, event: RevealEvent, p: Double, to: RevealPhase, effects: [String]?
        init(_ from: RevealPhase, _ event: RevealEvent, _ p: Double, _ to: RevealPhase, _ effects: [String]? = nil) {
            self.from = from; self.event = event; self.p = p; self.to = to; self.effects = effects
        }
        var testDescription: String { "\(from.name) --\(event)--> \(to.name)" }
    }

    /// architecture §6.5 / system-design §4.2 transition table.
    static let rows: [Row] = [
        // hidden
        Row(.hidden, .zoneEntered(.wall), 0, .arming(.wall), ["start(dwell,120)"]),
        Row(.hidden, .zoneEntered(.shared), 0, .arming(.shared), ["start(dwell,300)"]),
        Row(.hidden, .command(.reveal), 0, .revealing, ["gate(true)", "animate(shown,spring,220)"]),
        Row(.hidden, .command(.toggle), 0, .revealing, nil),
        Row(.hidden, .zoneLeft, 0, .hidden, []),
        Row(.hidden, .timerFired(.dwell), 0, .hidden, []),
        Row(.hidden, .pushThrough, 0, .hidden, []),
        Row(.hidden, .command(.hide(explicit: true)), 0, .hidden, []),
        // arming
        Row(.arming(.wall), .zoneLeft, 0, .hidden, ["cancel(dwell)"]),
        Row(.arming(.shared), .crossedToNeighbour, 0, .hidden, ["cancel(dwell)"]),
        Row(.arming(.wall), .buttonHeld(true), 0, .hidden, ["cancel(dwell)"]),
        Row(.arming(.wall), .timerFired(.dwell), 0, .revealing, ["gate(true)", "animate(shown,spring,220)"]),
        Row(.arming(.wall), .pushThrough, 0, .revealing, ["cancel(dwell)", "gate(true)", "animate(shown,spring,220)"]),
        Row(.arming(.shared), .pushThrough, 0, .arming(.shared), []),
        Row(.arming(.shared), .sharedSpeedExceeded, 0, .arming(.shared), ["cancel(dwell)", "start(dwell,300)"]),
        Row(.arming(.wall), .sharedSpeedExceeded, 0, .arming(.wall), []),
        Row(.arming(.shared), .zoneEntered(.wall), 0, .arming(.wall), ["cancel(dwell)", "start(dwell,120)"]),
        Row(.arming(.wall), .command(.reveal), 0, .revealing, ["cancel(dwell)", "gate(true)", "animate(shown,spring,220)"]),
        Row(.arming(.wall), .command(.hide(explicit: true)), 0, .hidden, ["cancel(dwell)", "start(cooldown,500)"]),
        Row(.arming(.wall), .pointerInside(false), 0, .arming(.wall), []),
        // revealing
        Row(.revealing, .animationFinished(generation: 1), 1, .shown, []),
        Row(.revealing, .animationFinished(generation: 99), 0.5, .revealing, []),
        Row(.revealing, .zoneEntered(.wall), 0.5, .revealing, []),
        Row(.revealing, .pushThrough, 0.5, .revealing, []),
        Row(.revealing, .command(.reveal), 0.5, .revealing, []),
        Row(.revealing, .pointerInside(false), 0.5, .revealing, ["start(hide,400)"]),
        Row(.revealing, .command(.hide(explicit: true)), 0.5, .hiding, ["gate(false)", "animate(hidden,easeIn,90)", "start(cooldown,500)"]),
        Row(.revealing, .command(.hide(explicit: false)), 0.5, .hiding, ["gate(false)", "animate(hidden,easeIn,90)"]),
        // shown
        Row(.shown, .pointerInside(false), 1, .armingHide, ["start(hide,400)"]),
        Row(.shown, .pointerInside(true), 1, .shown, []),
        Row(.shown, .zoneEntered(.wall), 1, .shown, []),
        Row(.shown, .command(.reveal), 1, .shown, []),
        Row(.shown, .command(.hide(explicit: true)), 1, .hiding, ["gate(false)", "animate(hidden,easeIn,180)", "start(cooldown,500)"]),
        Row(.shown, .command(.toggle), 1, .hiding, nil),
        // armingHide
        Row(.armingHide, .pointerInside(true), 1, .shown, ["cancel(hide)"]),
        Row(.armingHide, .zoneEntered(.wall), 1, .shown, ["cancel(hide)"]),
        Row(.armingHide, .hold(.menuOpen, true), 1, .shown, ["cancel(hide)"]),
        Row(.armingHide, .hold(.menuOpen, false), 1, .armingHide, []),
        Row(.armingHide, .timerFired(.hide), 1, .hiding, ["gate(false)", "animate(hidden,easeIn,180)"]),
        Row(.armingHide, .timerFired(.dwell), 1, .armingHide, []),
        Row(.armingHide, .command(.hide(explicit: true)), 1, .hiding,
            ["cancel(hide)", "gate(false)", "animate(hidden,easeIn,180)", "start(cooldown,500)"]),
        // hiding
        Row(.hiding, .animationFinished(generation: 2), 0, .hidden, []),
        Row(.hiding, .animationFinished(generation: 1), 0.5, .hiding, []),
        Row(.hiding, .pointerInside(true), 0.5, .revealing, ["gate(true)", "animate(shown,bezier,110)"]),
        Row(.hiding, .zoneEntered(.wall), 0.25, .revealing, ["gate(true)", "animate(shown,bezier,165)"]),
        Row(.hiding, .command(.reveal), 0.75, .revealing, ["gate(true)", "animate(shown,bezier,60)"]),
        Row(.hiding, .pointerInside(false), 0.5, .hiding, []),
        Row(.hiding, .timerFired(.hide), 0.5, .hiding, []),
        Row(.hiding, .command(.hide(explicit: false)), 0.5, .hiding, []),
        Row(.hiding, .command(.hide(explicit: true)), 0.5, .hiding, ["start(cooldown,500)"]),
    ]

    @Test(arguments: rows)
    func transition(_ row: Row) {
        var m = machine(in: row.from)
        let effects = m.handle(row.event, progress: row.p)
        #expect(m.phase == row.to)
        if let expected = row.effects { #expect(plain(effects) == expected) }
        // A trace is emitted exactly when the phase changes.
        #expect(traces(effects).count == (row.from == row.to ? 0 : 1))
    }

    @Test func tableReachesAndLeavesEveryPhase() {
        let names = Set(["hidden", "arming", "revealing", "shown", "armingHide", "hiding"])
        #expect(Set(Self.rows.map(\.from.name)) == names)
        #expect(Set(Self.rows.filter { $0.from != $0.to }.map(\.to.name)) == names)
    }
}

@Suite struct RevealBehaviourTests {
    @Test func traceCausesForTheHappyPath() {
        var m = SM()
        var causes: [String] = []
        func send(_ e: RevealEvent, _ p: Double) { causes += traces(m.handle(e, progress: p)).map { "\($0.to.name):\($0.cause.rawValue)" } }
        send(.zoneEntered(.wall), 0)
        send(.pushThrough, 0)
        send(.animationFinished(generation: m.activeGeneration!), 1)
        send(.zoneLeft, 1); send(.pointerInside(false), 1)
        send(.timerFired(.hide), 1)
        send(.pointerInside(true), 0.4)
        #expect(causes == ["arming:zone", "revealing:push", "shown:animationEnd", "armingHide:leave", "hiding:hideDelay", "revealing:return"])
    }

    @Test func explicitRevealWaitsForAFirstVisit() {
        var m = SM()
        _ = m.handle(.command(.reveal), progress: 0)
        _ = m.handle(.animationFinished(generation: m.activeGeneration!), progress: 1)
        #expect(m.phase == .shown)
        #expect(m.handle(.pointerInside(false), progress: 1).isEmpty)       // still away: stays
        _ = m.handle(.pointerInside(true), progress: 1)                    // visits
        #expect(plain(m.handle(.pointerInside(false), progress: 1)) == ["start(hide,400)"])
    }

    @Test func fullscreenUsesLongerDwell() {
        var m = SM()
        _ = m.handle(.fullscreenChanged(true), progress: 0)
        #expect(plain(m.handle(.zoneEntered(.wall), progress: 0)) == ["start(dwell,400)"])
    }

    @Test func zeroDwellRevealsAtOnce() {
        var c = RevealConfig()
        c.showDwell = .zero
        var m = SM(config: c)
        _ = m.handle(.zoneEntered(.wall), progress: 0)
        #expect(m.phase == .revealing)
    }

    @Test func holdBlocksHidingUntilReleased() {
        for token in HoldOpenToken.allCases {
            var m = machine(in: .shown)
            _ = m.handle(.hold(token, true), progress: 1)
            _ = m.handle(.pointerInside(false), progress: 1)
            #expect(m.phase == .shown, "token \(token)")
            #expect(plain(m.handle(.hold(token, false), progress: 1)) == ["start(hide,400)"])
            #expect(m.phase == .armingHide)
        }
    }

    @Test func shortHideDelayExpiringMidRevealReversesInPlace() {
        var c = RevealConfig()
        c.hideDelay = .milliseconds(50)
        var m = SM(config: c)
        _ = m.handle(.zoneEntered(.wall), progress: 0)
        _ = m.handle(.pointerInside(false), progress: 0)
        _ = m.handle(.timerFired(.dwell), progress: 0)
        #expect(plain(m.handle(.timerFired(.hide), progress: 0.5)) == ["gate(false)", "animate(hidden,easeIn,90)"])
        #expect(m.phase == .hiding)
    }

    @Test func pointerBackDuringRevealCancelsHideTimer() {
        var m = SM()
        _ = m.handle(.zoneEntered(.wall), progress: 0)
        _ = m.handle(.pointerInside(false), progress: 0)
        _ = m.handle(.timerFired(.dwell), progress: 0)
        #expect(plain(m.handle(.pointerInside(true), progress: 0.3)) == ["cancel(hide)"])
        #expect(m.handle(.timerFired(.hide), progress: 0.4).isEmpty)
        #expect(m.phase == .revealing)
    }

    @Test func revealFinishingWithPointerAwayGoesToArmingHide() {
        var m = SM()
        _ = m.handle(.zoneEntered(.wall), progress: 0)
        _ = m.handle(.pointerInside(false), progress: 0)
        _ = m.handle(.timerFired(.dwell), progress: 0)
        _ = m.handle(.animationFinished(generation: m.activeGeneration!), progress: 1)
        #expect(m.phase == .armingHide)
    }

    @Test func cooldownBlocksReArmingUntilItFires() {
        var m = machine(in: .shown)
        _ = m.handle(.command(.hide(explicit: true)), progress: 1)
        _ = m.handle(.animationFinished(generation: m.activeGeneration!), progress: 0)
        #expect(m.phase == .hidden)
        #expect(m.handle(.zoneEntered(.wall), progress: 0).isEmpty)
        _ = m.handle(.timerFired(.cooldown), progress: 0)
        #expect(plain(m.handle(.zoneEntered(.wall), progress: 0)) == ["start(dwell,120)"])
    }

    @Test func pinnedStartsShownAndIgnoresPointer() {
        var m = SM(config: RevealConfig(mode: .pinned))
        #expect(m.phase == .shown)
        for e: RevealEvent in [.pointerInside(false), .timerFired(.hide), .command(.hide(explicit: true)), .zoneEntered(.wall)] {
            #expect(m.handle(e, progress: 1).isEmpty)
        }
        #expect(m.phase == .shown)
    }

    @Test func suppressionForcesHiddenAndClearsBack() {
        var m = machine(in: .shown)
        let on = m.handle(.suppression(.spaceTransition, true), progress: 1)
        #expect(plain(on) == ["cancel(dwell)", "cancel(hide)", "gate(false)", "stop", "snap(hidden)", "orderOut"])
        #expect(m.phase == .hidden)
        #expect(m.handle(.zoneEntered(.wall), progress: 0).isEmpty)
        _ = m.handle(.suppression(.fullscreen, true), progress: 0)
        #expect(m.handle(.suppression(.spaceTransition, false), progress: 0).isEmpty)   // still suppressed
        #expect(plain(m.handle(.suppression(.fullscreen, false), progress: 0)) == ["snap(hidden)", "orderIn"])
        // Membership is re-derived by the evaluator; a fresh zone entry arms again.
        #expect(plain(m.handle(.zoneEntered(.wall), progress: 0)) == ["start(dwell,120)"])
    }

    @Test func pinnedComesBackShownAfterSuppression() {
        var m = SM(config: RevealConfig(mode: .pinned))
        _ = m.handle(.suppression(.displayAsleep, true), progress: 1)
        #expect(m.phase == .hidden)
        #expect(plain(m.handle(.suppression(.displayAsleep, false), progress: 0)) == ["snap(shown)", "orderIn", "gate(true)"])
        #expect(m.phase == .shown)
    }

    @Test func reconfigureModeSwitchesAtOnce() {
        var m = machine(in: .hidden)
        #expect(plain(m.reconfigure(RevealConfig(mode: .pinned))) == ["cancel(dwell)", "cancel(hide)", "gate(true)", "stop", "snap(shown)"])
        #expect(m.phase == .shown)
        #expect(plain(m.reconfigure(RevealConfig(mode: .reveal))) == ["cancel(dwell)", "cancel(hide)", "gate(false)", "stop", "snap(hidden)"])
        #expect(m.phase == .hidden)
        var c = RevealConfig()
        c.hideDelay = .seconds(1)
        #expect(m.reconfigure(c).isEmpty)
        #expect(m.config.hideDelay == .seconds(1))
    }

    @Test func reduceMotionIsAFade() {
        var c = RevealConfig()
        c.reduceMotion = true
        var m = SM(config: c)
        _ = m.handle(.zoneEntered(.wall), progress: 0)
        #expect(plain(m.handle(.timerFired(.dwell), progress: 0)).contains("animate(shown,fade,150)"))
    }
}

@Suite struct RevealMotionTests {
    let c = RevealConfig()

    /// system-design §3.3.1 remaining-travel table.
    @Test(arguments: [(0.10, 198.0, 60.0), (0.25, 165, 60), (0.50, 110, 90), (0.75, 60, 135)])
    func reverseDurations(p: Double, toShown: Double, toHidden: Double) {
        let r = c.animation(to: .shown, from: p, generation: 1)
        let h = c.animation(to: .hidden, from: p, generation: 1)
        #expect(r.duration.ms == toShown)
        #expect(h.duration.ms == toHidden)
        #expect(r.curve == .revealBezier)
        #expect(h.curve == .hideEaseIn)
    }

    @Test func fromRest() {
        #expect(c.animation(to: .shown, from: 0, generation: 1).curve == .revealSpring)
        #expect(c.animation(to: .shown, from: 0, generation: 1).duration == .milliseconds(220))
        #expect(c.animation(to: .hidden, from: 1, generation: 1).duration == .milliseconds(180))
        #expect(c.animation(to: .shown, from: -1, generation: 1).duration == .milliseconds(220))
    }
}

/// Randomised event storms: invariants that must hold on every path.
@Suite struct RevealFuzzTests {
    static let events: [RevealEvent] = [
        .zoneEntered(.wall), .zoneEntered(.shared), .zoneLeft, .pushThrough, .sharedSpeedExceeded, .crossedToNeighbour,
        .pointerInside(true), .pointerInside(false), .buttonHeld(true), .buttonHeld(false),
        .timerFired(.dwell), .timerFired(.hide), .timerFired(.cooldown),
        .hold(.menuOpen, true), .hold(.menuOpen, false), .hold(.dragging, true), .hold(.dragging, false),
        .fullscreenChanged(true), .fullscreenChanged(false),
        .command(.reveal), .command(.hide(explicit: true)), .command(.hide(explicit: false)), .command(.toggle),
        .suppression(.spaceTransition, true), .suppression(.spaceTransition, false),
    ]

    @Test(arguments: 0..<20)
    func invariants(seed: Int) {
        var rng = SplitMix64(seed: UInt64(seed) &+ 7)
        var m = SM()
        var lastTarget: AnimationRequest.Target?
        var interactive = false
        for _ in 0..<2000 {
            var e = Self.events.randomElement(using: &rng)!
            if Int.random(in: 0..<5, using: &rng) == 0, let g = m.activeGeneration { e = .animationFinished(generation: g) }
            let before = m.phase
            let effects = m.handle(e, progress: Double.random(in: 0...1, using: &rng))
            let visible = effects.filter { if case .trace = $0 { false } else { true } }
            for (i, effect) in visible.enumerated() {
                switch effect {
                case .setInteractive(let on): interactive = on
                case .snap(let t): lastTarget = t
                case .stopAnimation: lastTarget = nil
                case .animate(let r):
                    // DD-928: never restart toward the target already in flight.
                    #expect(r.target != lastTarget, "restart toward \(r.target) on \(e) in \(before.name)")
                    lastTarget = r.target
                    #expect(r.duration >= .milliseconds(60) && r.duration <= .milliseconds(220))
                    // DD-933: the gate flips in the same batch, before the animation.
                    #expect(i > 0 && visible[i - 1] == .setInteractive(r.target == .shown))
                default: break
                }
            }
            switch m.phase {
            case .hidden, .arming: #expect(!interactive, "interactive while \(m.phase.name)")
            case .shown, .armingHide: #expect(interactive, "pass-through while \(m.phase.name)")
            case .revealing: #expect(interactive)
            case .hiding: #expect(!interactive)
            }
            switch m.phase {
            case .revealing, .hiding: #expect(m.activeGeneration != nil)
            default: #expect(m.activeGeneration == nil)
            }
        }
    }
}
