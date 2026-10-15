import DedockCore
import Foundation

/// Scenario cards (DD-910, plan T17): one story applies mode, edge, delays and trigger values
/// in one step. Any later manual change marks the dock `custom`.
public enum Scenario: String, Sendable, CaseIterable, Identifiable {
    case revealLeft, revealRight, revealBottom, revealTop, pinned

    public static let customID = "custom"
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .revealLeft: "Reveal on Left"
        case .revealRight: "Reveal on Right"
        case .revealBottom: "Reveal at Bottom"
        case .revealTop: "Reveal at Top"
        case .pinned: "Pinned"
        }
    }

    public var subtitle: String {
        switch self {
        case .revealLeft: "Hidden until you push the pointer to the left edge."
        case .revealRight: "Hidden until you push the pointer to the right edge."
        case .revealBottom: "Slides up from the bottom edge, above the native Dock."
        case .revealTop: "Slides down below the menu bar."
        case .pinned: "Always visible on its edge."
        }
    }

    /// Beta cards are marked as such (plan T9 items 5–6).
    public var isBeta: Bool { self == .revealBottom || self == .revealTop }

    /// The card recommended for a native Dock on `nativeDockEdge` (AP §9.1): the side edge the
    /// native Dock does not use.
    public static func recommended(nativeDockEdge: ScreenEdge) -> Scenario {
        nativeDockEdge == .left ? .revealRight : .revealLeft
    }

    /// Applies this card to `dock`. Timing and trigger values return to their defaults, with the
    /// per-edge adjustments; display, profile, placement and appearance are kept.
    public func apply(to dock: DockConfig, nativeDockEdge: ScreenEdge) -> DockConfig {
        var d = dock
        var reveal = RevealSettings()
        reveal.unknown = dock.reveal.unknown
        switch self {
        case .revealLeft: d.edge = .left
        case .revealRight: d.edge = .right
        case .revealBottom: d.edge = .bottom
        case .revealTop:
            d.edge = .top
            reveal.showDwellMs = 300 // the zone shares pixels with the menu bar (architecture §6.4)
        case .pinned: break // stays on its current edge
        }
        // A thicker trigger where the native Dock shares the edge (plan §6 table).
        if d.edge == nativeDockEdge { reveal.triggerThicknessPt = 6 }
        d.mode = self == .pinned ? .pinned : .reveal
        d.reveal = reveal
        d.scenario = rawValue
        return d
    }

    /// The card a dock currently shows as selected, or nil for Custom.
    public static func current(_ dock: DockConfig) -> Scenario? {
        Scenario(rawValue: dock.scenario)
    }
}

extension DockConfig {
    /// Marks a manual change: the scenario card becomes Custom (DD-910 item 4).
    public mutating func markCustom() { scenario = Scenario.customID }
}
