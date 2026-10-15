import CoreGraphics
import Foundation

/// Edge-trigger tuning for one dock instance.
///
/// Defaults settled by dedock-e9 on 2026-10-15: `ux-patterns.md` T1–T9 and
/// `system-design.md` §5.1 win over `features.md` DD-921/923/924.
public struct EdgeTriggerParameters: Sendable, Equatable {
    /// Hot-zone thickness on a wall (unshared) edge, from the physical edge. Range 1–20 pt (DD-923).
    public var triggerThickness: CGFloat = 3
    /// How far the zone extends past each end of the dock content along the edge.
    public var spanPadding: CGFloat = 40
    public var spanMode: SpanMode = .dockLength
    /// Corner exclusion when that corner has a Hot Corner action. Range 0–96 pt.
    public var cornerExclusion: CGFloat = 24
    /// Corner exclusion when that corner's Hot Corner is disabled (`wvous-*-corner` 0 or 1).
    public var cornerExclusionWithoutHotCorner: CGFloat = 8
    /// Band thickness on an edge segment shared with another display (system-design §5.4).
    public var sharedBandThickness: CGFloat = 8
    /// Accumulated push toward the edge that reveals before the dwell ends. `nil` = off.
    public var pushThroughDistance: CGFloat? = 40
    /// Outset of the dock frame inside which the pointer still counts as "on the dock". Range 0–40 pt.
    public var hideHysteresis: CGFloat = 16
    /// A shared-band dwell restarts while the pointer moves faster than this (pt/s) …
    public var sharedMaxSpeed: CGFloat = 300
    /// … measured over this trailing window (s).
    public var sharedSpeedWindow: TimeInterval = 0.05

    public enum SpanMode: String, Sendable, Codable, CaseIterable {
        /// Dock content length plus `spanPadding` on each side (default).
        case dockLength
        /// The whole edge (minus corner and menu-bar exclusions).
        case wholeEdge
    }

    public init() {}
}
