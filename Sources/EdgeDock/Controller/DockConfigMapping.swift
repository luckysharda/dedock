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
        // Spec ranges (plan §6): every dwell and delay is 0–5 s, whatever the file says (REG-035).
        func ms(_ v: Int) -> Duration { .milliseconds(min(5000, max(0, v))) }
        c.showDwell = ms(reveal.showDwellMs)
        c.fullscreenDwell = ms(reveal.fullscreenDwellMs)
        c.hideDelay = ms(reveal.hideDelayMs)
        // Modifier policy: contact with ⌥ held reveals at once (architecture §6.4).
        if reveal.sharedEdgePolicy == .modifier { c.sharedDwell = .zero }
        // Top edge shares pixels with the menu bar: 300 ms dwell unless push-through arrives.
        if edge == .top { c.showDwell = max(c.showDwell, .milliseconds(300)) }
        c.reduceMotion = reduceMotion
        return c
    }

    /// The trigger as configured. Beside the native Dock use `triggerParameters(nativeDockEdge:)`.
    public var triggerParameters: TriggerParameters { triggerParameters(nativeDockEdge: nil) }

    /// The trigger for this dock with the native Dock on `nativeDockEdge`: where both share an
    /// edge the zone is at least 6 pt thick (plan §6 table). Derived here, never stored (REG-062).
    public func triggerParameters(nativeDockEdge: ScreenEdge?) -> TriggerParameters {
        var p = TriggerParameters()
        p.thickness = CGFloat(min(20, max(1, reveal.triggerThicknessPt)))
        if nativeDockEdge == edge { p.thickness = max(p.thickness, 6) }
        p.spanMode = reveal.spanMode == .wholeEdge ? .wholeEdge : .content
        p.cornerExclusion = CGFloat(min(96, max(0, reveal.cornerExclusionPt)))
        p.pushThrough = reveal.pushThroughPt.map { CGFloat(min(200, max(16, $0))) }   // 16–200 pt or off
        p.hysteresis = CGFloat(min(40, max(0, reveal.hysteresisPt)))                 // 0–40 pt (REG-035)
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

    /// Tokens for the current system state: appearance (label colours) and Reduce Transparency.
    @MainActor public var tokens: DockTokens {
        tokens(lightAppearance: NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua,
               reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
    }

    /// Tokens for this dock's size and `dd.dock.style`, in the given system state.
    public func tokens(lightAppearance: Bool, reduceTransparency: Bool) -> DockTokens {
        let size: DockTokens.Size = switch appearance.size {
        case .s: .s
        case .m: .m
        case .l: .l
        case .xl: .xl
        }
        let style: DockTokens.Style = switch appearance.style {
        case .darkGlass: .darkGlass
        case .black: .black
        case .lightGlass: .lightGlass
        }
        var t = DockTokens.capsule(size, style: style, reduceTransparency: reduceTransparency, lightAppearance: lightAppearance)
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
            // Bookmark first (it follows a moved or renamed folder), then the path (REG-031).
            let url = resolvedBookmark ?? path.map { URL(fileURLWithPath: $0, isDirectory: true) }
            return TileModel(id: id, kind: .folder, name: displayName ?? url?.lastPathComponent ?? "Folder", url: url)
        default:
            let url = path.map { URL(fileURLWithPath: $0) }
            let name = displayName ?? url.map { $0.deletingPathExtension().lastPathComponent } ?? bundleID ?? "App"
            return TileModel(id: id, kind: .app, name: name, bundleID: bundleID, url: url)
        }
    }

    /// The bookmark's current location, if it still resolves.
    public var resolvedBookmark: URL? {
        guard let bookmark else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                        relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    public var tileSpec: TileSpec {
        TileSpec(id: id, shape: kind == .separator ? .separator : (kind == .widget ? .square(.unit) : .app))
    }
}
