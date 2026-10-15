import DedockCore
import Foundation
import Testing
@testable import SettingsStore

@Suite struct ScenarioTests {
    let base = DedockDocument.makeDefault().docks[0]

    @Test(arguments: [(ScreenEdge.bottom, Scenario.revealLeft), (.right, .revealLeft), (.left, .revealRight)])
    func recommendedFollowsTheNativeDock(native: ScreenEdge, expected: Scenario) {
        #expect(Scenario.recommended(nativeDockEdge: native) == expected)
    }

    @Test(arguments: [(Scenario.revealLeft, ScreenEdge.left), (.revealRight, .right), (.revealBottom, .bottom), (.revealTop, .top)])
    func revealCardsSetEdgeModeAndScenario(card: Scenario, edge: ScreenEdge) {
        let d = card.apply(to: base)
        #expect(d.edge == edge)
        #expect(d.mode == .reveal)
        #expect(d.scenario == card.rawValue)
    }

    @Test func applyingResetsTimingButKeepsPlacementAndProfile() {
        var custom = base
        custom.reveal.showDwellMs = 900
        custom.reveal.hideDelayMs = 50
        custom.placement.alignment = .end
        custom.profileID = "work"
        let d = Scenario.revealRight.apply(to: custom)
        #expect(d.reveal.showDwellMs == RevealSettings().showDwellMs)
        #expect(d.reveal.hideDelayMs == RevealSettings().hideDelayMs)
        #expect(d.placement.alignment == .end)
        #expect(d.profileID == "work")
    }

    /// Edge-dependent values are derived at mapping time, never stored by a card (REG-062).
    @Test func cardsStoreNoEdgeDerivedValues() {
        let defaults = RevealSettings()
        for card in Scenario.allCases {
            let d = card.apply(to: base)
            #expect(d.reveal.showDwellMs == defaults.showDwellMs, "\(card)")
            #expect(d.reveal.triggerThicknessPt == defaults.triggerThicknessPt, "\(card)")
        }
    }

    @Test func pinnedKeepsTheEdge() {
        var right = base
        right.edge = .right
        let d = Scenario.pinned.apply(to: right)
        #expect(d.edge == .right)
        #expect(d.mode == .pinned)
    }

    @Test func manualChangeMarksCustom() {
        var d = Scenario.revealLeft.apply(to: base)
        #expect(Scenario.current(d) == .revealLeft)
        d.markCustom()
        #expect(Scenario.current(d) == nil)
        #expect(d.scenario == "custom")
    }

    @Test func betaCards() {
        #expect(Scenario.allCases.filter(\.isBeta) == [.revealBottom, .revealTop])
    }
}
