import AppKit

/// App and folder icons from `NSWorkspace`, requested at 256 pt so SwiftUI downsamples rather
/// than upscaling a small representation. Cached by path.
@MainActor public final class IconCache {
    private let cache = NSCache<NSString, NSImage>()
    public init() { cache.countLimit = 256 }

    public func icon(for tile: TileModel) -> NSImage? {
        guard let path = tile.url?.path else { return nil }
        if let hit = cache.object(forKey: path as NSString) { return hit }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 256, height: 256)
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}
