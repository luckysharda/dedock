import Foundation
#if canImport(CoreGraphics)
import CoreGraphics // CGRect Hashable etc.; Linux Foundation provides these itself
#endif

/// Stable across reboots and port changes; never `CGDirectDisplayID` alone.
public struct DisplayIdentity: Hashable, Codable, Sendable, CustomStringConvertible {
    public let uuid: String
    public let vendor: UInt32
    public let model: UInt32
    public let serial: UInt32

    public init(uuid: String, vendor: UInt32 = 0, model: UInt32 = 0, serial: UInt32 = 0) {
        self.uuid = uuid
        self.vendor = vendor
        self.model = model
        self.serial = serial
    }

    public var description: String { uuid }
}

/// An AppKit-free snapshot of one display. Rects are AppKit global coordinates.
public struct DisplaySnapshot: Hashable, Sendable {
    public let identity: DisplayIdentity
    /// The CoreGraphics display id at snapshot time (for GEOM output and CG calls only).
    public let displayID: UInt32
    public let frame: CGRect
    public let visibleFrame: CGRect
    /// `frame.maxY − visibleFrame.maxY`, or the auto-hide reserve when that is 0.
    public let menuBarHeight: CGFloat
    public let menuBarAutoHides: Bool
    /// The notch, between `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`.
    public let notch: CGRect?
    public let isBuiltin: Bool
    public let isMain: Bool
    public let backingScale: CGFloat

    public init(
        identity: DisplayIdentity, displayID: UInt32 = 0, frame: CGRect, visibleFrame: CGRect,
        menuBarHeight: CGFloat, menuBarAutoHides: Bool, notch: CGRect? = nil,
        isBuiltin: Bool = false, isMain: Bool = false, backingScale: CGFloat = 2
    ) {
        self.identity = identity
        self.displayID = displayID
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.menuBarHeight = menuBarHeight
        self.menuBarAutoHides = menuBarAutoHides
        self.notch = notch
        self.isBuiltin = isBuiltin
        self.isMain = isMain
        self.backingScale = backingScale
    }

    /// Derives a snapshot from raw `NSScreen` values (architecture §6.10). Pure, so tests need no screens.
    /// - Parameters:
    ///   - safeAreaTop: `NSScreen.safeAreaInsets.top` (> 0 on notched displays).
    ///   - statusBarThickness: `NSStatusBar.system.thickness`.
    ///   - auxiliaryTopLeft / auxiliaryTopRight: `NSScreen.auxiliaryTopLeftArea` / `…RightArea`.
    public static func make(
        identity: DisplayIdentity, displayID: UInt32 = 0, frame: CGRect, visibleFrame: CGRect,
        safeAreaTop: CGFloat = 0, statusBarThickness: CGFloat = 24,
        auxiliaryTopLeft: CGRect? = nil, auxiliaryTopRight: CGRect? = nil,
        isBuiltin: Bool = false, isMain: Bool = false, backingScale: CGFloat = 2
    ) -> DisplaySnapshot {
        let shown = frame.maxY - visibleFrame.maxY
        let autoHides = shown <= 0
        let height = autoHides ? max(statusBarThickness, safeAreaTop) : shown
        var notch: CGRect?
        if safeAreaTop > 0, let left = auxiliaryTopLeft, let right = auxiliaryTopRight, right.minX > left.maxX {
            notch = CGRect(x: left.maxX, y: frame.maxY - safeAreaTop, width: right.minX - left.maxX, height: safeAreaTop)
        }
        return DisplaySnapshot(
            identity: identity, displayID: displayID, frame: frame, visibleFrame: visibleFrame,
            menuBarHeight: height, menuBarAutoHides: autoHides, notch: notch,
            isBuiltin: isBuiltin, isMain: isMain, backingScale: backingScale)
    }
}

/// Every connected display. `generation` is bumped on every change; zones are rebuilt per generation.
public struct DisplayLayout: Hashable, Sendable {
    public let displays: [DisplaySnapshot]
    public let generation: UInt64

    public init(displays: [DisplaySnapshot], generation: UInt64 = 0) {
        self.displays = displays
        self.generation = generation
    }

    public var main: DisplaySnapshot? { displays.first(where: \.isMain) ?? displays.first }
    public var builtin: DisplaySnapshot? { displays.first(where: \.isBuiltin) }

    /// Height of the primary display, for AppKit ↔ CoreGraphics conversion.
    public var primaryHeight: CGFloat { (displays.first(where: { $0.frame.origin == .zero }) ?? main)?.frame.height ?? 0 }

    public func display(_ identity: DisplayIdentity) -> DisplaySnapshot? {
        displays.first { $0.identity == identity }
    }

    /// The display whose frame contains `p` (inclusive of the max edges, where the cursor can sit).
    public func display(containing p: CGPoint) -> DisplaySnapshot? {
        displays.first { $0.frame.contains(p) }
            ?? displays.first { p.x >= $0.frame.minX && p.x <= $0.frame.maxX && p.y >= $0.frame.minY && p.y <= $0.frame.maxY }
    }
}
