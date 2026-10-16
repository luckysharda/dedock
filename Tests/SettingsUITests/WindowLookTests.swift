import AppKit
import DesignSystem
import SettingsStore
import SwiftUI
import Testing
@testable import SettingsUI

/// T37b: the windows' look after the fallbacks (design.md §7.2).
@Suite @MainActor struct WindowLookTests {
    @Test func materialResolvesWithItsFallbacks() {
        func backdrop(_ m: WindowLook.Material, rt: Bool = false, glass: Bool = true) -> WindowLook.Backdrop {
            WindowLook(appearance: .system, material: m, reduceTransparency: rt, systemGlass: glass).backdrop
        }
        #expect(backdrop(.frosted) == .frosted)
        #expect(backdrop(.liquidGlass) == .glass)
        #expect(backdrop(.liquidGlass, glass: false) == .frosted)      // before macOS 26
        #expect(backdrop(.solid) == .solid)
        for m in WindowLook.Material.allCases { #expect(backdrop(m, rt: true) == .solid) }   // Reduce Transparency
    }

    @Test func appearanceMapsToTheWindowAppearance() {
        #expect(WindowLook(appearance: .system, material: .frosted, reduceTransparency: false).nsAppearance == nil)
        #expect(WindowLook(appearance: .light, material: .frosted, reduceTransparency: false).nsAppearance?.name == .aqua)
        #expect(WindowLook(appearance: .dark, material: .frosted, reduceTransparency: false).nsAppearance?.name == .darkAqua)
    }

    /// The settings enums and the DesignSystem ones stay in step (the controller maps by raw value).
    @Test func settingsValuesMapOneToOne() {
        #expect(AppPreferences.WindowAppearance.allCases.map(\.rawValue) == WindowLook.Appearance.allCases.map(\.rawValue))
        #expect(AppPreferences.WindowMaterial.allCases.map(\.rawValue) == WindowLook.Material.allCases.map(\.rawValue))
    }

    @Test func backdropShowsOneLayerPerMaterial() {
        let v = WindowBackdropView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        v.apply(.solid)
        #expect(v.backdrop == .solid && v.layer?.backgroundColor != NSColor.clear.cgColor)
        v.apply(.frosted)
        #expect(v.layer?.backgroundColor == NSColor.clear.cgColor)
        #expect(v.subviews.contains { $0 is NSVisualEffectView && !$0.isHidden })
        v.apply(.solid)
        #expect(!v.subviews.contains { $0 is NSVisualEffectView && !$0.isHidden })
    }
}

/// The material choice reaches every column of the Settings window: our own pixels, rendered
/// offscreen (the system blur and glass are not drawn offscreen; the fills over them are).
@Suite @MainActor struct SettingsWindowFillTests {
    struct Pixels { let sidebar: NSColor; let content: NSColor }

    func render(_ backdrop: WindowLook.Backdrop) throws -> Pixels {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dedock-fill-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let settings = SettingsModel(file: LayoutFile(directory: dir), clock: ContinuousClock(), document: .makeDefault())
        let chrome = SettingsChrome()
        chrome.backdrop = backdrop
        let root = SettingsRootView(settings: settings, environment: SettingsEnvironment(nativeDockEdge: { .bottom }, hasSharedEdge: { _ in false }),
                                    navigation: SettingsNavigation(), chrome: chrome)
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(x: 0, y: 0, width: 900, height: 640)
        host.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let s = rep.size.width / 900       // points → pixels
        func at(_ x: CGFloat, _ y: CGFloat) -> NSColor {   // top-left points
            rep.colorAt(x: Int(x * s), y: Int(y * s))?.usingColorSpace(.sRGB) ?? .clear
        }
        // The sidebar below its rows; the content's right margin (no card there).
        return Pixels(sidebar: at(120, 600), content: at(892, 400))
    }

    func rgb(_ c: NSColor) -> [Int] { [c.redComponent, c.greenComponent, c.blueComponent].map { Int(($0 * 255).rounded()) } }

    @Test func solidIsOpaqueInEveryColumn() throws {
        let p = try render(.solid)
        #expect(p.sidebar.alphaComponent > 0.99 && rgb(p.sidebar) == [0x1E, 0x1D, 0x1B])
        #expect(p.content.alphaComponent > 0.99 && rgb(p.content) == [0x25, 0x24, 0x21])
    }

    @Test func frostedAndGlassLetTheWindowMaterialThrough() throws {
        for backdrop in [WindowLook.Backdrop.frosted, .glass] {
            let p = try render(backdrop)
            #expect(p.sidebar.alphaComponent > 0.1 && p.sidebar.alphaComponent < 0.3)   // the faint overlay
            #expect(p.content.alphaComponent < 0.01)
        }
    }
}
