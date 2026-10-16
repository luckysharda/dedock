import DedockCore
import EdgeDock
import Foundation

/// Records animation requests and reports a scripted presentation progress.
@MainActor public final class FakeAnimator: RevealAnimating {
    public var presentationProgress: Double = 0
    public private(set) var requests: [AnimationRequest] = []
    public private(set) var stops = 0
    public private(set) var snaps: [AnimationRequest.Target] = []
    private var completions: [UInt64: @MainActor (UInt64) -> Void] = [:]

    public init() {}

    public func run(_ request: AnimationRequest, completion: @escaping @MainActor (UInt64) -> Void) {
        requests.append(request)
        completions[request.generation] = completion
    }

    public func stop() { stops += 1 }

    public func snap(to target: AnimationRequest.Target) {
        snaps.append(target)
        presentationProgress = target == .shown ? 1 : 0
    }

    /// Finish the most recent animation: progress jumps to its target and its completion fires.
    public func finishLatest() {
        guard let last = requests.last, let done = completions.removeValue(forKey: last.generation) else { return }
        presentationProgress = last.target == .shown ? 1 : 0
        done(last.generation)
    }
}

@MainActor public final class FakeGate: ClickThroughGating {
    public private(set) var interactive: [Bool] = []
    public private(set) var hitRegion: [CGRect] = []
    public init() {}
    public func setInteractive(_ on: Bool) { interactive.append(on) }
    public func updateHitRegion(_ rects: [CGRect]) { hitRegion = rects }
    public func pointerMoved(_ location: CGPoint) {}
}

/// One native-Dock cell for the T31 matrix (DD-991/992): the `com.apple.dock` values dedock
/// reads, and a 1920 × 1080 display whose `visibleFrame` leaves room for a visible Dock the way
/// macOS does (an auto-hidden Dock leaves none). Read-only by construction: it is a value.
public struct FakeDockPreferences: Sendable {
    public let prefs: NativeDockPreferences
    public let display: DisplaySnapshot

    /// The visible Dock's thickness (tile 48 + padding), which macOS takes from `visibleFrame`.
    public static let visibleThickness: CGFloat = 70

    public init(edge: ScreenEdge, autohide: Bool, apps: Int = 8, others: Int = 2) {
        prefs = NativeDockPreferences(orientation: edge, autohide: autohide, tileSize: 48,
                                      persistentAppCount: apps, persistentOtherCount: others)
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        var visible = CGRect(x: 0, y: 0, width: 1920, height: 1056)   // below the 24 pt menu bar
        let t = autohide ? 0 : Self.visibleThickness
        switch edge {
        case .bottom: visible = CGRect(x: 0, y: t, width: 1920, height: 1056 - t)
        case .left: visible = CGRect(x: t, y: 0, width: 1920 - t, height: 1056)
        case .right: visible = CGRect(x: 0, y: 0, width: 1920 - t, height: 1056)
        case .top: break
        }
        display = DisplaySnapshot(identity: DisplayIdentity(uuid: "matrix"), frame: frame, visibleFrame: visible,
                                  menuBarHeight: 24, menuBarAutoHides: false, isMain: true, backingScale: 1)
    }

    /// The native Dock's estimated footprint as a screen rect (for overlap checks).
    public var footprintRect: CGRect? {
        NativeDockPreferences.footprint(prefs: prefs, display: display).map {
            $0.edge.strip(of: display.frame, along: $0.span, thickness: $0.thickness)
        }
    }
}
