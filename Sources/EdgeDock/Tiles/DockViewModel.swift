import AppKit
import DedockCore
import DesignSystem
import Observation

/// What a tile shows. Built from the profile's `TileItem`s plus live running state.
public struct TileModel: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable { case app, folder, separator }
    public enum Running: String, Sendable { case none, running, frontmost, hidden }

    public let id: TileID
    public var kind: Kind
    public var name: String
    public var bundleID: String?
    public var url: URL?
    public var running: Running = .none
    /// The app or folder no longer exists.
    public var isMissing = false
    /// The app's window count, read for the hovered tile only (nil when unknown).
    public var windowCount: Int?

    public init(id: TileID, kind: Kind, name: String, bundleID: String? = nil, url: URL? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.bundleID = bundleID
        self.url = url
    }
}

/// Observable state the dock's SwiftUI content renders. Geometry is panel-local, AppKit
/// orientation (y up); the view flips it.
@MainActor @Observable public final class DockViewModel {
    public var tokens: DockTokens
    public var edge: ScreenEdge = .left
    public var tiles: [TileModel] = []
    /// Panel-local frames.
    public var panelSize: CGSize = .zero
    public var capsule: CGRect = .zero
    public var tileFrames: [TileID: CGRect] = [:]
    public var hoveredTile: TileID?
    public var pressedTile: TileID?
    /// The tile being dragged and its panel-local centre, following the pointer along the axis.
    public var draggedTile: TileID?
    public var dragCentre: CGPoint = .zero
    /// Screen origin of the panel, for screen ↔ local conversion.
    public var panelOrigin: CGPoint = .zero

    @ObservationIgnored let icons: IconCache
    /// The tile's press action for accessibility (AXPress); the coordinator routes it to the
    /// same path as a click.
    @ObservationIgnored public var activate: ((TileID) -> Void)?

    public init(tokens: DockTokens, icons: IconCache) {
        self.tokens = tokens
        self.icons = icons
    }

    public func apply(layout: DockLayout, tiles: [TileModel]) {
        let o = layout.panelFrame.origin
        panelOrigin = o
        panelSize = layout.panelFrame.size
        edge = layout.edge
        capsule = layout.capsuleFrame.offsetBy(dx: -o.x, dy: -o.y)
        tileFrames = layout.tileFrames.mapValues { $0.offsetBy(dx: -o.x, dy: -o.y) }
        self.tiles = tiles
    }

    public func tile(atScreen p: CGPoint) -> TileID? {
        let local = CGPoint(x: p.x - panelOrigin.x, y: p.y - panelOrigin.y)
        return tiles.first { $0.kind != .separator && (tileFrames[$0.id]?.contains(local) ?? false) }?.id
    }

    func icon(for tile: TileModel) -> NSImage? { icons.icon(for: tile) }

    /// The hover label's lane: toward the screen centre, `labelGap` from the capsule, beside the
    /// tile (DD-903 item 3), panel-local. The label sits at the lane's capsule-side end.
    public static func labelLane(for tile: CGRect, capsule c: CGRect, edge: ScreenEdge, tokens t: DockTokens) -> CGRect {
        let length = t.labelLane - t.labelGap
        let across = labelHeight(t)
        switch edge {
        case .left: return CGRect(x: c.maxX + t.labelGap, y: tile.midY - across / 2, width: length, height: across)
        case .right: return CGRect(x: c.minX - t.labelGap - length, y: tile.midY - across / 2, width: length, height: across)
        case .bottom: return CGRect(x: tile.midX - length / 2, y: c.maxY + t.labelGap, width: length, height: across)
        case .top: return CGRect(x: tile.midX - length / 2, y: c.minY - t.labelGap - across, width: length, height: across)
        }
    }

    /// Two lines (name, state) plus padding.
    static func labelHeight(_ t: DockTokens) -> CGFloat {
        (t.labelFontSize + t.labelStateFontSize) * 1.3 + 2 * t.labelPaddingV + 2
    }
}

/// What the H4 hover label says: the name, then the state (design.md §7.2a).
public struct TileLabelContent: Equatable, Sendable {
    public let name: String
    public let state: String?
    /// Draw the running dot before the state.
    public let running: Bool

    public init(_ tile: TileModel) {
        name = tile.name
        func windows(_ n: Int?) -> String {
            guard let n else { return "" }
            if n == 0 { return " \u{00B7} No windows" }
            return " \u{00B7} \(n) \(n == 1 ? "window" : "windows")"
        }
        if tile.isMissing {
            state = tile.kind == .folder ? "Folder not found" : "Not found"
            running = false
            return
        }
        switch (tile.kind, tile.running) {
        case (.separator, _): state = nil; running = false
        case (.folder, _): state = "Folder"; running = false
        case (.app, .none): state = "Not running"; running = false
        case (.app, .hidden): state = "Hidden" + windows(tile.windowCount); running = false
        case (.app, .running), (.app, .frontmost): state = "Running" + windows(tile.windowCount); running = true
        }
    }
}
