import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The two tints of the Liquid Glass dock style (LG4 Adaptive, design.md §7.2a).
public enum LiquidTint: String, Sendable, CaseIterable {
    case dark, light
}

/// LG4 Adaptive: picks the Liquid Glass tint from how bright the content behind the dock is.
/// Pure: the caller feeds luminance readings and tells it when the dock reveals.
///
/// - Hysteresis: switch to light above `toLight` (0.60 relative luminance) and back to dark
///   below `toDark` (0.50), so mid-grey content does not flicker between them.
/// - The tint never changes while the dock is shown: readings only update `pending`; `reveal()`
///   applies it, and the caller cross-fades (0.3 s) when it changed.
public struct LiquidTintPolicy: Sendable, Equatable {
    public static let toLight = 0.60
    public static let toDark = 0.50

    public private(set) var applied: LiquidTint
    public private(set) var pending: LiquidTint

    public init(_ tint: LiquidTint = .dark) {
        applied = tint
        pending = tint
    }

    /// A new reading of the average relative luminance (0…1) behind the dock.
    public mutating func observe(luminance: Double) {
        switch pending {
        case .dark where luminance > Self.toLight: pending = .light
        case .light where luminance < Self.toDark: pending = .dark
        default: break
        }
    }

    /// The dock starts to reveal: applies a pending change and returns it (nil if unchanged).
    public mutating func reveal() -> LiquidTint? {
        guard pending != applied else { return nil }
        applied = pending
        return applied
    }
}

public enum Luminance {
    /// WCAG relative luminance of an sRGB colour with 0…1 channels.
    public static func relative(r: Double, g: Double, b: Double) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}

/// Where to read the wallpaper under a dock (LG4 until Screen Recording, design.md §7.2a).
public enum WallpaperSampling {
    /// The strip of the desktop picture behind a dock on `edge`, in image pixels (top-left
    /// origin), `depth` points deep along the edge.
    /// - Parameter fill: the picture fills the screen (the macOS default): it is centre-cropped
    ///   to the screen's aspect first. Otherwise (fit, stretch, centre) the whole picture is
    ///   mapped onto the screen, an approximation that keeps the strip on the right side.
    public static func region(imageSize: CGSize, screenSize: CGSize, edge: ScreenEdge, depth: CGFloat,
                              fill: Bool = true) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, screenSize.width > 0, screenSize.height > 0 else { return .zero }
        let crop: CGRect
        let scaleAlong: CGFloat     // points per image pixel across the edge
        if fill {
            // Aspect fill: the scale at which the image covers the screen.
            let scale = max(screenSize.width / imageSize.width, screenSize.height / imageSize.height)
            let visible = CGSize(width: screenSize.width / scale, height: screenSize.height / scale)
            crop = CGRect(x: (imageSize.width - visible.width) / 2, y: (imageSize.height - visible.height) / 2,
                          width: visible.width, height: visible.height)
            scaleAlong = scale
        } else {
            crop = CGRect(origin: .zero, size: imageSize)
            scaleAlong = edge.isVertical ? screenSize.width / imageSize.width : screenSize.height / imageSize.height
        }
        let d = min(max(depth, 1) / scaleAlong, edge.isVertical ? crop.width : crop.height)
        switch edge {
        case .left: return CGRect(x: crop.minX, y: crop.minY, width: d, height: crop.height)
        case .right: return CGRect(x: crop.maxX - d, y: crop.minY, width: d, height: crop.height)
        case .top: return CGRect(x: crop.minX, y: crop.minY, width: crop.width, height: d)
        case .bottom: return CGRect(x: crop.minX, y: crop.maxY - d, width: crop.width, height: d)
        }
    }
}

extension Luminance {
    /// The mean relative luminance of `region` in an RGBA8 (sRGB, row-major, top-left origin)
    /// bitmap, or nil when the region holds no pixels.
    public static func average(rgba: [UInt8], width: Int, height: Int, region: CGRect) -> Double? {
        let x0 = max(0, Int(region.minX.rounded(.down))), x1 = min(width, Int(region.maxX.rounded(.up)))
        let y0 = max(0, Int(region.minY.rounded(.down))), y1 = min(height, Int(region.maxY.rounded(.up)))
        guard x0 < x1, y0 < y1, rgba.count >= width * height * 4 else { return nil }
        var sum = 0.0, n = 0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = (y * width + x) * 4
                sum += relative(r: Double(rgba[i]) / 255, g: Double(rgba[i + 1]) / 255, b: Double(rgba[i + 2]) / 255)
                n += 1
            }
        }
        return n == 0 ? nil : sum / Double(n)
    }
}
