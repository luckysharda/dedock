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
}
