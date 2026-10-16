import AppKit
import DedockCore
import DedockTestSupport
import DisplayTopology
import SettingsStore
import Testing
@testable import EdgeDock

/// T31 (DD-991, DD-992): the 9-cell native Dock matrix, native Dock left / bottom / right ×
/// Edge Dock left / right / bottom, each with auto-hide off and on, at L2: a real coordinator
/// fed `FakeDockPreferences` (placement, zones, recommended edge).
@MainActor @Suite("Native Dock matrix", .serialized)
struct NativeDockMatrixTests {
    struct Cell: CustomTestStringConvertible, Sendable {
        let native: ScreenEdge, edge: ScreenEdge, autohide: Bool
        var testDescription: String { "native \(native) × edge \(edge)\(autohide ? " (auto-hide)" : "")" }
    }

    nonisolated static let cells: [Cell] = [ScreenEdge.left, .bottom, .right].flatMap { native in
        [ScreenEdge.left, .right, .bottom].flatMap { edge in [false, true].map { Cell(native: native, edge: edge, autohide: $0) } }
    }

    func coordinator(_ cell: Cell) -> (EdgeDockCoordinator, FakeDockPreferences) {
        let fake = FakeDockPreferences(edge: cell.native, autohide: cell.autohide)
        var config = DockConfig(id: "D1", edge: cell.edge)
        config.placement.alignment = .center
        let s = DockSurroundings(layout: DisplayLayout(displays: [fake.display]), nativeDock: fake.prefs, reduceMotion: true)
        let items = (1...6).map { TileItem(id: TileID("t\($0)"), kind: .app, bundleID: "com.apple.calculator") }
        let c = EdgeDockCoordinator(config: config, profile: Profile(id: config.profileID, name: "p", items: items),
                                    display: fake.display, surroundings: s, running: RunningAppsMonitor(), icons: IconCache(),
                                    clock: ManualClock())
        return (c, fake)
    }

    @Test(.enabled(if: NSScreen.main != nil), arguments: cells)
    func placementZonesAndRecommendation(_ cell: Cell) throws {
        let (c, fake) = coordinator(cell)
        defer { c.teardown() }
        let capsule = c.capsuleFrame, d = fake.display
        let sameEdge = cell.native == cell.edge

        // Placement: on the display, below the menu bar, on its own edge.
        #expect(d.frame.contains(capsule))
        #expect(capsule.maxY <= d.frame.maxY - d.menuBarHeight)
        switch cell.edge {
        case .left: #expect(capsule.midX < d.frame.midX)
        case .right: #expect(capsule.midX > d.frame.midX)
        default: #expect(capsule.midY < d.frame.midY)
        }
        // Beside a visible native Dock on the same edge, never over it: it sits on the Dock's
        // inner side (architecture §6.4 "Native Dock coexistence").
        if sameEdge, !cell.autohide, let dock = fake.footprintRect {
            #expect(!capsule.intersects(dock), "capsule \(capsule) overlaps the native Dock \(dock)")
            #expect(d.visibleFrame.contains(capsule))
            // The panel starts at the Dock's inner edge: the slide is clipped there, so the dock
            // emerges from behind the Dock, and Dedock's window never covers the Dock's clicks.
            #expect(!c.layout.panelFrame.intersects(dock), "panel \(c.layout.panelFrame) overlaps the native Dock \(dock)")
            let hidden = capsule.offsetBy(dx: c.layout.hiddenOffset.dx, dy: c.layout.hiddenOffset.dy)
            #expect(!hidden.intersects(c.layout.panelFrame))
        }

        // Zones: never empty; beside the native Dock they skip its span (REG-065).
        #expect(!c.zones.isEmpty)
        if sameEdge {
            #expect(c.derivation?.rule == .besideNativeDock)
            let span = try #require(c.nativeDockFootprint?.span)
            for z in c.zones {
                let along = cell.edge.isVertical ? Interval(z.rect.minY, z.rect.maxY) : Interval(z.rect.minX, z.rect.maxX)
                #expect(along.intersection(span).map { $0.length <= 0.5 } ?? true, "zone \(z.rect) inside the Dock span \(span)")
            }
        } else {
            #expect(c.derivation?.rule == .primary)
            #expect(c.nativeDockFootprint == nil)
        }

        // Recommended edge: never the native Dock's own edge.
        #expect(NativeDockPreferences.recommendedEdge(nativeDock: cell.native) != cell.native)
    }
}
