import AppKit
import DedockCore
import DedockTestSupport
import DesignSystem
import DisplayTopology
import ImageIO
import SettingsStore
import Testing
import UniformTypeIdentifiers
@testable import EdgeDock

/// T37a dock styles (design.md §7.1, §7.2a): Dark, Liquid Glass with LG4 Adaptive.
@MainActor @Suite("Dock styles")
struct AppearanceTests {
    func rgba(_ c: NSColor) -> [Int] {
        let s = c.usingColorSpace(.sRGB)!
        return [s.redComponent, s.greenComponent, s.blueComponent, s.alphaComponent].map { Int(($0 * 255).rounded()) }
    }

    @Test func darkIsSolidMatte() {
        let t = DockTokens.capsule(.m, style: .dark)
        #expect(t.blurMaterial == nil)
        #expect(rgba(t.capsuleTint) == [0x1C, 0x1C, 0x1E, 255])
        #expect(rgba(t.widgetPlate) == [0x2A, 0x2A, 0x2C, 255])
        #expect(rgba(t.textSecondary) == [0x98, 0x98, 0x9D, 255])
        #expect(t.systemGlassTint == nil && t.specularRim == 0)
    }

    @Test func liquidGlassOnTheSystemGlassTakesTheLG4Tints() {
        let dark = DockTokens.capsule(.m, style: .liquidGlass, liquid: .dark, systemGlass: true)
        let light = DockTokens.capsule(.m, style: .liquidGlass, liquid: .light, systemGlass: true)
        #expect(dark.blurMaterial == nil && light.blurMaterial == nil)
        #expect(dark.systemGlassTint.map(rgba) == [0x12, 0x12, 0x14, 77])      // @ 0.30
        #expect(light.systemGlassTint.map(rgba) == [0xEA, 0xED, 0xF2, 107])    // @ 0.42
        // Text and running dots flip with the tint.
        #expect(rgba(dark.textPrimary) == [255, 255, 255, 255])
        #expect(rgba(light.textPrimary) == [0x11, 0x11, 0x11, 255])
        #expect(rgba(light.indicatorRunning) == [0, 0, 0, 179])                // black @ 0.7
    }

    @Test func liquidGlassBeforeMacOS26IsTheStandInWithASpecularRim() {
        let dark = DockTokens.capsule(.m, style: .liquidGlass, liquid: .dark, systemGlass: false)
        let light = DockTokens.capsule(.m, style: .liquidGlass, liquid: .light, systemGlass: false)
        #expect(dark.systemGlassTint == nil && dark.specularRim == 0.22)
        #expect(dark.blurMaterial == .hudWindow && rgba(dark.capsuleTint) == rgba(DockTokens.capsule(.m).capsuleTint))
        #expect(light.blurMaterial == .popover && rgba(light.capsuleTint) == [0xEA, 0xED, 0xF2, 140])
        #expect(rgba(light.textPrimary) == [0x11, 0x11, 0x11, 255])
    }

    @Test func reduceTransparencyMakesLiquidGlassTheSolidDark() {
        for tint in LiquidTint.allCases {
            for glass in [true, false] {
                let t = DockTokens.capsule(.m, style: .liquidGlass, reduceTransparency: true, liquid: tint, systemGlass: glass)
                let dark = DockTokens.capsule(.m, style: .dark)
                #expect(t.style == .liquidGlass)
                #expect(t.blurMaterial == nil && t.systemGlassTint == nil && t.specularRim == 0)
                #expect(rgba(t.capsuleTint) == rgba(dark.capsuleTint) && rgba(t.textPrimary) == rgba(dark.textPrimary))
            }
        }
        #expect(DockTokens.capsule(.m, style: .dark, reduceTransparency: true).blurMaterial == nil)
    }

    @Test func everySettingsStyleMaps() {
        for style in AppearanceSettings.Style.allCases {
            var config = DockConfig(id: "D1")
            config.appearance.style = style
            #expect(config.tokens(lightAppearance: false, reduceTransparency: false).style.rawValue == style.rawValue)
        }
    }

    /// The wallpaper reading: a picture white on the left half and black on the right.
    @Test func wallpaperReadingTakesTheStripUnderTheEdge() throws {
        let w = 64, h = 32
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h { for x in 0..<w { let i = (y * w + x) * 4; let v: UInt8 = x < w / 2 ? 255 : 0; px[i] = v; px[i + 1] = v; px[i + 2] = v; px[i + 3] = 255 } }
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        // The context and its image are made while the buffer pointer is valid.
        let made: CGImage? = px.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        let image = try #require(made)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dedock-lg4-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))

        func key(_ edge: ScreenEdge) -> WallpaperLuminance.Key {
            WallpaperLuminance.Key(url: url, modified: nil, displayID: 1, edge: edge, depth: 100, screenSize: CGSize(width: 2000, height: 1000))
        }
        let left = try #require(WallpaperLuminance.measure(key(.left)))
        let right = try #require(WallpaperLuminance.measure(key(.right)))
        let bottom = try #require(WallpaperLuminance.measure(key(.bottom)))
        #expect(left > 0.95 && right < 0.05)
        #expect(abs(bottom - 0.5) < 0.05)
        #expect(WallpaperLuminance.measure(WallpaperLuminance.Key(url: url.appendingPathExtension("missing"), modified: nil, displayID: 1,
                                                                  edge: .left, depth: 100, screenSize: CGSize(width: 2000, height: 1000))) == nil)
    }

    /// Reduce Transparency comes from the surroundings (pinned here, whatever the host's setting),
    /// and no wallpaper is read: the test feeds the readings.
    func makeCoordinator(mode: DockConfig.Mode = .reveal, reduceTransparency: Bool = false) -> EdgeDockCoordinator {
        var config = DockConfig(id: "D1", edge: .left, mode: mode)
        config.appearance.style = .liquidGlass
        let display = AppRegressionTests.regDisplay
        let s = DockSurroundings(layout: DisplayLayout(displays: [display]), nativeDock: NativeDockPreferences(), reduceMotion: true,
                                 reduceTransparency: reduceTransparency)
        let profile = Profile(id: config.profileID, name: "p", items: [TileItem(id: "t1", kind: .app, bundleID: "com.apple.calculator")])
        return EdgeDockCoordinator(config: config, profile: profile, display: display, surroundings: s,
                                   running: RunningAppsMonitor(), icons: IconCache(), clock: ManualClock(), background: .none)
    }

    /// LG4: a reading never changes a shown dock; the next reveal applies it.
    @Test(.enabled(if: NSScreen.main != nil)) func theTintChangesAtRevealNotWhileShown() {
        let c = makeCoordinator()
        defer { c.teardown() }
        c.observeBackground(luminance: 0.9)
        #expect(c.liquid.applied == .dark && rgba(c.model.tokens.textPrimary) == [255, 255, 255, 255])
        c.controller.send(.command(.reveal))
        #expect(c.liquid.applied == .light)
        #expect(rgba(c.model.tokens.textPrimary) == [0x11, 0x11, 0x11, 255])
        c.observeBackground(luminance: 0.1)                  // while revealing/shown
        #expect(c.liquid.applied == .light && c.liquid.pending == .dark)
        #expect(rgba(c.model.tokens.textPrimary) == [0x11, 0x11, 0x11, 255])
    }

    /// Reduce Transparency: Liquid Glass is the solid Dark style, and a light reading changes
    /// nothing visible.
    @Test(.enabled(if: NSScreen.main != nil)) func reduceTransparencyDrawsLiquidGlassAsDarkWithNoTint() {
        let c = makeCoordinator(reduceTransparency: true)
        defer { c.teardown() }
        let dark = DockTokens.capsule(.m, style: .dark)
        c.observeBackground(luminance: 0.9)
        c.controller.send(.command(.reveal))
        let t = c.model.tokens
        #expect(t.style == .liquidGlass && t.blurMaterial == nil && t.systemGlassTint == nil && t.specularRim == 0)
        #expect(rgba(t.capsuleTint) == rgba(dark.capsuleTint) && rgba(t.textPrimary) == [255, 255, 255, 255])
    }

    /// LG4: a Pinned dock is always shown, so it takes a change at once (cross-faded).
    @Test(.enabled(if: NSScreen.main != nil)) func aPinnedDockTakesTheChangeAtOnce() {
        let c = makeCoordinator(mode: .pinned)
        defer { c.teardown() }
        c.observeBackground(luminance: 0.9)
        #expect(c.liquid.applied == .light)
    }
}
