import DedockCore
import Foundation
import Testing

/// LG4 Adaptive (T37, design.md §7.2a): the tint policy and the wallpaper reading's geometry.
@Suite("LG4 Adaptive")
struct LiquidTintTests {
    @Test func hysteresisSwitchesAboveSixtyAndBackBelowFifty() {
        var p = LiquidTintPolicy()
        p.observe(luminance: 0.59)
        #expect(p.pending == .dark)
        p.observe(luminance: 0.61)
        #expect(p.pending == .light)
        p.observe(luminance: 0.55)                 // between the thresholds: stays light
        #expect(p.pending == .light)
        p.observe(luminance: 0.49)
        #expect(p.pending == .dark)
        p.observe(luminance: 0.58)                 // between: stays dark
        #expect(p.pending == .dark)
    }

    @Test func theTintChangesOnlyAtReveal() {
        var p = LiquidTintPolicy()
        p.observe(luminance: 0.9)
        #expect(p.applied == .dark && p.pending == .light)   // shown: not applied yet
        #expect(p.reveal() == .light)
        #expect(p.applied == .light)
        #expect(p.reveal() == nil)                            // nothing new: no cross-fade
    }

    @Test func relativeLuminance() {
        #expect(Luminance.relative(r: 0, g: 0, b: 0) == 0)
        #expect(abs(Luminance.relative(r: 1, g: 1, b: 1) - 1) < 1e-9)
        #expect(abs(Luminance.relative(r: 0.5, g: 0.5, b: 0.5) - 0.214) < 0.001)   // mid-grey is dark
    }

    @Test func averageOverARegion() {
        // 4 × 2: the left half white, the right half black.
        var px = [UInt8](repeating: 0, count: 4 * 2 * 4)
        for y in 0..<2 { for x in 0..<2 { let i = (y * 4 + x) * 4; px[i] = 255; px[i + 1] = 255; px[i + 2] = 255; px[i + 3] = 255 } }
        let left = Luminance.average(rgba: px, width: 4, height: 2, region: CGRect(x: 0, y: 0, width: 2, height: 2))
        let right = Luminance.average(rgba: px, width: 4, height: 2, region: CGRect(x: 2, y: 0, width: 2, height: 2))
        let all = Luminance.average(rgba: px, width: 4, height: 2, region: CGRect(x: -5, y: -5, width: 50, height: 50))
        #expect(left.map { abs($0 - 1) < 1e-9 } == true)
        #expect(right == 0)
        #expect(all.map { abs($0 - 0.5) < 1e-9 } == true)
        #expect(Luminance.average(rgba: px, width: 4, height: 2, region: CGRect(x: 9, y: 9, width: 1, height: 1)) == nil)
    }

    @Test func regionCropsToTheScreenAspectThenTakesTheEdgeStrip() {
        // A 2:1 picture on a 1:1 screen: the middle 100 × 100 is visible; 1 image px = 10 pt.
        let image = CGSize(width: 200, height: 100), screen = CGSize(width: 1000, height: 1000)
        #expect(WallpaperSampling.region(imageSize: image, screenSize: screen, edge: .left, depth: 100)
                == CGRect(x: 50, y: 0, width: 10, height: 100))
        #expect(WallpaperSampling.region(imageSize: image, screenSize: screen, edge: .right, depth: 100)
                == CGRect(x: 140, y: 0, width: 10, height: 100))
        #expect(WallpaperSampling.region(imageSize: image, screenSize: screen, edge: .top, depth: 100)
                == CGRect(x: 50, y: 0, width: 100, height: 10))
        #expect(WallpaperSampling.region(imageSize: image, screenSize: screen, edge: .bottom, depth: 100)
                == CGRect(x: 50, y: 90, width: 100, height: 10))
        #expect(WallpaperSampling.region(imageSize: .zero, screenSize: screen, edge: .left, depth: 100) == .zero)
    }
}
