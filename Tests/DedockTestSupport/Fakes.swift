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
