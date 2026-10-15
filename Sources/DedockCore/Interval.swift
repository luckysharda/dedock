import CoreGraphics

/// A half-open 1-D interval `[lower, upper)` along a screen edge, in points.
public struct Interval: Hashable, Sendable, CustomStringConvertible {
    public var lower: CGFloat
    public var upper: CGFloat

    public init(_ lower: CGFloat, _ upper: CGFloat) {
        self.lower = lower
        self.upper = upper
    }

    public var length: CGFloat { max(0, upper - lower) }
    public var isEmpty: Bool { upper <= lower }
    public var midpoint: CGFloat { (lower + upper) / 2 }

    public func intersection(_ other: Interval) -> Interval? {
        let result = Interval(max(lower, other.lower), min(upper, other.upper))
        return result.isEmpty ? nil : result
    }

    public func contains(_ value: CGFloat) -> Bool { value >= lower && value < upper }

    public var description: String { "[\(lower), \(upper))" }
}

/// A normalised set of disjoint, sorted, non-empty intervals.
///
/// Used for hot-zone construction: an edge line minus corners, menu bar, neighbouring
/// displays and the native Dock footprint (system-design §5.2).
public struct IntervalSet: Hashable, Sendable, CustomStringConvertible {
    public private(set) var intervals: [Interval]

    public init(_ intervals: [Interval] = []) {
        self.intervals = IntervalSet.normalise(intervals)
    }

    public init(_ interval: Interval) { self.init([interval]) }

    public var isEmpty: Bool { intervals.isEmpty }
    public var totalLength: CGFloat { intervals.reduce(0) { $0 + $1.length } }

    public func union(_ other: IntervalSet) -> IntervalSet {
        IntervalSet(intervals + other.intervals)
    }

    public func subtracting(_ cut: Interval) -> IntervalSet {
        guard !cut.isEmpty else { return self }
        var result: [Interval] = []
        for piece in intervals {
            guard piece.intersection(cut) != nil else {
                result.append(piece)
                continue
            }
            if piece.lower < cut.lower { result.append(Interval(piece.lower, cut.lower)) }
            if cut.upper < piece.upper { result.append(Interval(cut.upper, piece.upper)) }
        }
        return IntervalSet(result)
    }

    public func subtracting(_ other: IntervalSet) -> IntervalSet {
        other.intervals.reduce(self) { $0.subtracting($1) }
    }

    public func intersection(_ other: IntervalSet) -> IntervalSet {
        var result: [Interval] = []
        for a in intervals {
            for b in other.intervals {
                if let overlap = a.intersection(b) { result.append(overlap) }
            }
        }
        return IntervalSet(result)
    }

    public var description: String { intervals.map(\.description).joined(separator: " ∪ ") }

    private static func normalise(_ input: [Interval]) -> [Interval] {
        let sorted = input.filter { !$0.isEmpty }.sorted { $0.lower < $1.lower }
        var merged: [Interval] = []
        for interval in sorted {
            if let last = merged.last, interval.lower <= last.upper {
                merged[merged.count - 1].upper = max(last.upper, interval.upper)
            } else {
                merged.append(interval)
            }
        }
        return merged
    }
}
