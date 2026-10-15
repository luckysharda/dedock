import AppKit
import DedockCore
import DesignSystem
import Foundation
import SettingsStore

/// Maps the persisted `DockConfig` (SettingsStore, raw numbers) onto the Edge Dock's typed
/// configuration. SettingsStore sits below EdgeDock, so the mapping lives here.
extension DockConfig {
    public func revealConfig(reduceMotion: Bool) -> RevealConfig {
        var c = RevealConfig(mode: mode == .pinned ? .pinned : .reveal)
        c.showDwell = .milliseconds(reveal.showDwellMs)
        c.fullscreenDwell = .milliseconds(reveal.fullscreenDwellMs)
        c.hideDelay = .milliseconds(reveal.hideDelayMs)
        // Modifier policy: contact with ⌥ held reveals at once (architecture §6.4).
        if reveal.sharedEdgePolicy == .modifier { c.sharedDwell = .zero }
        // Top edge shares pixels with the menu bar: 300 ms dwell unless push-through arrives.
        if edge == .top { c.showDwell = max(c.showDwell, .milliseconds(300)) }
        c.reduceMotion = reduceMotion
        return c
    }

    public var triggerParameters: TriggerParameters {
        var p = TriggerParameters()
        p.thickness = CGFloat(min(20, max(1, reveal.triggerThicknessPt)))
        p.spanMode = reveal.spanMode == .wholeEdge ? .wholeEdge : .content
        p.cornerExclusion = CGFloat(min(96, max(0, reveal.cornerExclusionPt)))
        p.pushThrough = reveal.pushThroughPt.map { CGFloat($0) }
        p.hysteresis = CGFloat(min(64, max(0, reveal.hysteresisPt)))
        p.sharedPolicy = switch reveal.sharedEdgePolicy {
        case .slowDwell: .slowDwell
        case .modifier: .modifier
        case .wallOnly: .wallOnly
        }
        return p
    }

    public var dockAlignment: DockAlignment {
        switch placement.alignment {
        case .start: .start
        case .center: .center
        case .end: .end
        }
    }

    @MainActor public var tokens: DockTokens {
        let size: DockTokens.Size = switch appearance.size {
        case .s: .s
        case .m: .m
        case .l: .l
        case .xl: .xl
        }
        let ws = NSWorkspace.shared
        let light = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
        var t = DockTokens.capsule(size, style: .darkGlass,
                                   reduceTransparency: ws.accessibilityDisplayShouldReduceTransparency,
                                   lightAppearance: light)
        t.edgeGap = CGFloat(min(48, max(0, placement.edgeGapPt)))
        return t
    }
}

extension DockTokens {
    public var metrics: DockMetrics {
        var m = DockMetrics(thickness: thickness, padding: padding, gap: gap, separatorLength: separatorLength,
                            edgeGap: edgeGap, labelLane: labelLane, shadowMargin: shadowMargin)
        m.appCellLength = appCellLength
        m.endMargin = endMargin
        return m
    }
}

extension TileItem {
    /// The view model for a persisted tile (running state is filled in later).
    public var tileModel: TileModel {
        switch kind {
        case .separator:
            return TileModel(id: id, kind: .separator, name: "")
        case .folder:
            let url = path.map { URL(fileURLWithPath: $0, isDirectory: true) }
            return TileModel(id: id, kind: .folder, name: displayName ?? url?.lastPathComponent ?? "Folder", url: url)
        default:
            let url = path.map { URL(fileURLWithPath: $0) }
            let name = displayName ?? url.map { $0.deletingPathExtension().lastPathComponent } ?? bundleID ?? "App"
            return TileModel(id: id, kind: .app, name: name, bundleID: bundleID, url: url)
        }
    }

    public var tileSpec: TileSpec {
        TileSpec(id: id, shape: kind == .separator ? .separator : (kind == .widget ? .square(.unit) : .app))
    }
}
