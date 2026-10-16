import AppKit
import DedockCore
import ImageIO

/// LG4's background reading until Screen Recording (design.md §7.2a): the average relative
/// luminance of the desktop picture under the dock's edge, read from the picture file through
/// public `NSWorkspace` and ImageIO calls; no permission, nothing stored, nothing sent.
enum WallpaperLuminance {
    /// What a reading depends on; a reading is redone only when this changes.
    struct Key: Equatable, Sendable {
        let url: URL
        let modified: Date?
        let displayID: UInt32
        let edge: ScreenEdge
        let depth: CGFloat
        let screenSize: CGSize
        /// The picture fills the screen (the default scaling); otherwise it is mapped whole.
        var fill = true
    }

    /// The current key for a dock, or nil when the display has no readable desktop picture.
    @MainActor static func key(display: DisplaySnapshot, edge: ScreenEdge, depth: CGFloat) -> Key? {
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID
        }), let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        // Fill = scale proportionally with clipping (the default); fit, stretch and centre differ.
        let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
        let scaling = (options[.imageScaling] as? NSNumber).flatMap { NSImageScaling(rawValue: $0.uintValue) }
        let clipping = options[.allowClipping] as? Bool
        let fill = (scaling ?? .scaleProportionallyUpOrDown) == .scaleProportionallyUpOrDown && (clipping ?? true)
        return Key(url: url, modified: modified, displayID: display.displayID, edge: edge, depth: depth,
                   screenSize: display.frame.size, fill: fill)
    }

    /// The thumbnail's long side: plenty for an average, cheap to decode.
    static let thumbnail = 160

    /// Reads the strip's luminance (off the main actor; a few ms for a 160 px thumbnail).
    static func read(_ key: Key) async -> Double? {
        await Task.detached(priority: .utility) { measure(key) }.value
    }

    static func measure(_ key: Key) -> Double? {
        guard let source = CGImageSourceCreateWithURL(key.url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: thumbnail,
              ] as CFDictionary) else { return nil }
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        let region = WallpaperSampling.region(imageSize: CGSize(width: w, height: h), screenSize: key.screenSize,
                                              edge: key.edge, depth: key.depth, fill: key.fill)
        return Luminance.average(rgba: pixels, width: w, height: h, region: region)
    }
}

/// Where a dock's LG4 readings come from: the key for its display, edge and depth (nil when
/// there is nothing to read), and the reading itself.
struct BackgroundReader: Sendable {
    var key: @MainActor (DisplaySnapshot, ScreenEdge, CGFloat) -> WallpaperLuminance.Key?
    var read: @Sendable (WallpaperLuminance.Key) async -> Double?

    /// The desktop picture file (until the M3 Screen Recording decision).
    static let wallpaper = BackgroundReader(key: { WallpaperLuminance.key(display: $0, edge: $1, depth: $2) },
                                            read: { await WallpaperLuminance.read($0) })
    /// No readings (tests).
    static let none = BackgroundReader(key: { _, _, _ in nil }, read: { _ in nil })
}
