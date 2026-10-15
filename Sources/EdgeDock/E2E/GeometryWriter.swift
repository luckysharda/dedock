import DedockCore
import Diagnostics
import Foundation

/// One dock's geometry for the GEOM file.
public struct DockGeometrySnapshot: Sendable {
    public let id: DockID
    public let display: DisplaySnapshot
    public let edge: ScreenEdge
    public let mode: RevealMode
    public let phase: RevealPhase
    public let layout: DockLayout?
    public let zones: [HotZone]
    public let tiles: [TileModel]
    /// `dd.dock.style` in effect (`darkGlass`, `black`, `lightGlass`).
    public var style: String = "darkGlass"
    /// The capsule material: the blur material's name, or `solid` (Reduce Transparency).
    public var material: String = "solid"
    /// The effective show dwell in ms (after the top edge's 300 ms minimum).
    public var showDwellMs: Int = 0
}

/// Writes `<data dir>/e2e/geometry.json` (E2E contract §4) atomically after every layout pass
/// and every state change. Debug builds with `DEDOCK_E2E=1` only.
public struct GeometryWriter: Sendable {
    public let url: URL

    public init(dataDirectory: URL) {
        url = dataDirectory.appendingPathComponent("e2e", isDirectory: true).appendingPathComponent("geometry.json")
    }

    public func write(layout: DisplayLayout, docks: [DockGeometrySnapshot]) {
        let h = layout.primaryHeight
        func rect(_ r: CGRect) -> [String: [Double]] {
            let tl = r.flippedVertically(primaryHeight: h)
            return ["appkit": [r.minX, r.minY, r.width, r.height].map(Double.init),
                    "topLeft": [tl.minX, tl.minY, tl.width, tl.height].map(Double.init)]
        }
        let screens: [[String: Any]] = layout.displays.map { d in
            ["id": Int(d.displayID), "uuid": d.identity.uuid, "main": d.isMain, "scale": Double(d.backingScale),
             "frame": rect(d.frame), "visibleFrame": rect(d.visibleFrame)]
        }
        let dockObjects: [[String: Any]] = docks.map { dock in
            var o: [String: Any] = [
                "id": dock.id.rawValue, "screen": Int(dock.display.displayID), "edge": dock.edge.rawValue,
                "mode": dock.mode.rawValue, "state": dock.phase.name, "style": dock.style, "material": dock.material, "showDwellMs": dock.showDwellMs,
                "zones": dock.zones.map { ["id": $0.id, "kind": $0.kind.rawValue, "rect": rect($0.rect)] as [String: Any] },
            ]
            if let l = dock.layout {
                o["panel"] = rect(l.panelFrame)
                o["capsule"] = rect(l.capsuleFrame)
                o["tiles"] = dock.tiles.compactMap { t -> [String: Any]? in
                    guard let f = l.tileFrames[t.id] else { return nil }
                    var tile: [String: Any] = ["id": t.id.rawValue, "kind": t.kind.rawValue, "name": t.name,
                                               "frame": rect(f), "hitRect": rect(f), "running": t.running.rawValue]
                    if let b = t.bundleID { tile["bundleId"] = b }
                    if let u = t.url { tile["path"] = u.path }
                    return tile
                }
            } else {
                o["tiles"] = [[String: Any]]()
            }
            return o
        }
        let root: [String: Any] = [
            "schema": 1, "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "written": ISO8601DateFormatter.e2e.string(from: Date()),
            "screens": screens, "docks": dockObjects,
        ]
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch {
            DedockLog.error(.layout, "geometry.json write failed: \(error.localizedDescription)")
        }
    }
}

extension ISO8601DateFormatter {
    nonisolated(unsafe) static let e2e: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
