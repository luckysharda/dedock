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

    @Test func frostedLetsTheMaterialThroughWithAFaintSidebar() throws {
        let p = try render(.frosted)
        #expect(p.sidebar.alphaComponent > 0.1 && p.sidebar.alphaComponent < 0.3)       // the faint overlay
        #expect(p.content.alphaComponent < 0.01)                                         // the blur carries the tint
    }

    /// Liquid Glass: the sidebar is clear glass; the content has a light translucent tint for
    /// legibility, weaker than Frosted's 0.62 and never opaque (design.md §7.2).
    @Test func liquidGlassHasAClearSidebarAndALightContentTint() throws {
        let p = try render(.glass)
        #expect(p.sidebar.alphaComponent < 0.01)
        #expect(p.content.alphaComponent > 0.3 && p.content.alphaComponent < 0.62)
    }

    /// e9's structural gate: on Frosted and Liquid Glass the window is non-opaque with a clear
    /// background and the backdrop covers the whole content view; Solid is the only opaque one.
    @Test func theBackdropCoversTheWindowAndOnlySolidIsOpaque() {
        let w = NSWindow(contentRect: CGRect(x: -3000, y: -3000, width: 900, height: 640),
                         styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: true)
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 900, height: 640))
        let backdrop = WindowBackdropView(frame: .zero)
        container.addSubview(backdrop)
        w.contentView = container
        for material in WindowLook.Material.allCases {
            let look = WindowLook(appearance: .dark, material: material, reduceTransparency: false, systemGlass: true)
            SettingsWindowController.apply(look, to: w, backdrop: backdrop)
            #expect(backdrop.frame == container.bounds)
            #expect(w.isOpaque == (look.backdrop == .solid))
            #expect((w.backgroundColor == .clear) == (look.backdrop != .solid))
        }
    }

    /// The window's Liquid Glass is the clear style: the regular one rendered a window-sized
    /// surface as a near-uniform grey, the same as Solid at a glance.
    @Test(.enabled(if: DockTokens.systemGlassAvailable)) func theWindowGlassIsTheClearStyle() {
        let v = WindowBackdropView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        v.apply(.glass)
        if #available(macOS 26, *) {
            let glass = v.subviews.compactMap { $0 as? NSGlassEffectView }.first
            #expect(glass?.style == .clear && glass?.isHidden == false)
            #expect(glass?.frame == v.bounds)
        }
    }
}
