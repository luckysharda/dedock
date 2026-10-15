import AppKit
import DedockCore
import Diagnostics

/// What dedock reads from the native Dock's preferences (`com.apple.dock`, read-only; dedock
/// never writes Dock preferences in v0; architecture §6.4 "Native Dock coexistence").
public struct NativeDockPreferences: Sendable, Hashable {
    /// The native Dock's edge: bottom, left or right.
    public var orientation: ScreenEdge
    public var autohide: Bool
    /// `tilesize` (pt).
    public var tileSize: CGFloat
    public var persistentAppCount: Int
    public var persistentOtherCount: Int
    /// Corners whose Hot Corner has an action.
    public var hotCorners: HotCornerMask

    public init(orientation: ScreenEdge = .bottom, autohide: Bool = false, tileSize: CGFloat = 48,
                persistentAppCount: Int = 0, persistentOtherCount: Int = 0, hotCorners: HotCornerMask = .all) {
        self.orientation = orientation
        self.autohide = autohide
        self.tileSize = tileSize
        self.persistentAppCount = persistentAppCount
        self.persistentOtherCount = persistentOtherCount
        self.hotCorners = hotCorners
    }

    /// The `com.apple.dock` keys this type reads.
    public static let keys = ["orientation", "autohide", "tilesize", "persistent-apps", "persistent-others",
                              "wvous-tl-corner", "wvous-tr-corner", "wvous-bl-corner", "wvous-br-corner"]

    /// Pure parse of raw preference values. Missing keys take the macOS defaults (bottom, no
    /// autohide, 48 pt tiles). A Hot Corner value of 0 or 1 means "no action"; anything greater
    /// is an action. A missing corner key counts as an action, keeping the larger exclusion.
    public static func parse(_ values: [String: Any]) -> NativeDockPreferences {
        func number(_ key: String) -> Double? {
            if let n = values[key] as? NSNumber { return n.doubleValue }
            if let d = values[key] as? Double { return d }
            if let i = values[key] as? Int { return Double(i) }
            return nil
        }
        let orientation: ScreenEdge = switch values["orientation"] as? String {
        case "left": .left
        case "right": .right
        default: .bottom
        }
        var autohide = false
        if let b = values["autohide"] as? Bool { autohide = b } else if let n = number("autohide") { autohide = n != 0 }

        var corners: HotCornerMask = []
        let cornerKeys: [(String, HotCornerMask)] = [
            ("wvous-tl-corner", .topLeft), ("wvous-tr-corner", .topRight),
            ("wvous-bl-corner", .bottomLeft), ("wvous-br-corner", .bottomRight),
        ]
        for (key, corner) in cornerKeys {
            if let value = number(key) {
                if value > 1 { corners.insert(corner) }
            } else {
                corners.insert(corner)
            }
        }

        return NativeDockPreferences(
            orientation: orientation,
            autohide: autohide,
            tileSize: CGFloat(number("tilesize") ?? 48),
            persistentAppCount: (values["persistent-apps"] as? [Any])?.count ?? 0,
            persistentOtherCount: (values["persistent-others"] as? [Any])?.count ?? 0,
            hotCorners: corners)
    }

    /// Padding the estimate adds at each end and around the tiles *(inferred)*.
    public static let estimatePadding: CGFloat = 8

    /// Estimated native Dock footprint on `display` (only for the edge the native Dock is on).
    /// Span = `tileSize × (apps + others + 1) + 2 × padding`, centred on the display edge
    /// *(inferred estimate; replaced by DockObserver's AX tile frames with Pillar A)*. Thickness
    /// is the gap between `frame` and `visibleFrame` on that side, or `tileSize + 2 × padding`
    /// when the Dock auto-hides (no gap).
    public static func footprint(prefs: NativeDockPreferences, display: DisplaySnapshot) -> NativeDockFootprint? {
        let edge = prefs.orientation
        let f = display.frame, v = display.visibleFrame
        let gap: CGFloat = switch edge {
        case .bottom: v.minY - f.minY
        case .left: v.minX - f.minX
        case .right: f.maxX - v.maxX
        case .top: 0
        }
        guard edge != .top else { return nil }
        let pad = estimatePadding
        let thickness = prefs.autohide || gap <= 0 ? prefs.tileSize + 2 * pad : gap
        let length = prefs.tileSize * CGFloat(prefs.persistentAppCount + prefs.persistentOtherCount + 1) + 2 * pad
        let line = edge.line(of: f)
        let centre = line.midpoint
        let span = Interval(max(line.lower, centre - length / 2), min(line.upper, centre + length / 2))
        return NativeDockFootprint(edge: edge, span: span, thickness: thickness, autohide: prefs.autohide)
    }

    /// Default Edge Dock edge from the native Dock's edge: left when the native Dock is at the
    /// bottom or right, right when it is on the left (AP §9.1).
    public static func recommendedEdge(nativeDock: ScreenEdge) -> ScreenEdge {
        nativeDock == .left ? .right : .left
    }
}

/// Reads `com.apple.dock` and calls back when it changes: the distributed
/// `com.apple.dock.prefchanged` notification *(inferred)*, the Dock process relaunching, and
/// screen-parameter changes (a Dock change moves `visibleFrame`).
@MainActor public final class DockPreferencesReader {
    public private(set) var current: NativeDockPreferences
    private let onChange: @MainActor (NativeDockPreferences) -> Void
    private var tokens: [(NotificationCenter, any NSObjectProtocol)] = []

    public init(onChange: @escaping @MainActor (NativeDockPreferences) -> Void) {
        self.onChange = onChange
        current = Self.read()
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        let local = NotificationCenter.default
        tokens = [
            (distributed, distributed.addObserver(forName: Notification.Name("com.apple.dock.prefchanged"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }),
            (workspace, workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let bundle = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                guard bundle == "com.apple.dock" else { return }
                MainActor.assumeIsolated { self?.reload() }
            }),
            (local, local.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }),
        ]
    }

    /// Re-reads the preferences; calls back only when they changed.
    public func reload() {
        let fresh = Self.read()
        guard fresh != current else { return }
        current = fresh
        DedockLog.event(.display, "dock.prefs", [
            "orientation": fresh.orientation.rawValue, "autohide": fresh.autohide,
            "tilesize": Int(fresh.tileSize), "corners": fresh.hotCorners.rawValue,
        ])
        onChange(fresh)
    }

    public func invalidate() {
        for (center, token) in tokens { center.removeObserver(token) }
        tokens = []
    }

    static func read() -> NativeDockPreferences {
        let app = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(app)
        var values: [String: Any] = [:]
        for key in NativeDockPreferences.keys {
            if let value = CFPreferencesCopyAppValue(key as CFString, app) { values[key] = value }
        }
        return NativeDockPreferences.parse(values)
    }
}
