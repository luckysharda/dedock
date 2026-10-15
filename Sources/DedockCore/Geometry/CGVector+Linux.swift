import Foundation

#if !canImport(CoreGraphics)
/// swift-corelibs-foundation provides CGFloat, CGPoint, CGSize and CGRect but not CGVector.
/// This mirrors the part of the CoreGraphics type dedock uses, so the pure logic builds on Linux.
public struct CGVector: Hashable, Sendable {
    public var dx: CGFloat
    public var dy: CGFloat
    public init(dx: CGFloat, dy: CGFloat) {
        self.dx = dx
        self.dy = dy
    }
    public static let zero = CGVector(dx: 0, dy: 0)
}
#endif
