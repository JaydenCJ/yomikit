/// A closed 1-D interval used by clustering helpers.
public struct Interval: Sendable, Hashable, Codable {
    public var lowerBound: Double
    public var upperBound: Double

    public init(lowerBound: Double, upperBound: Double) {
        self.lowerBound = min(lowerBound, upperBound)
        self.upperBound = max(lowerBound, upperBound)
    }

    public var length: Double { upperBound - lowerBound }
    public var center: Double { (lowerBound + upperBound) / 2 }

    /// Length of the overlap with `other`, 0 when disjoint.
    public func overlap(with other: Interval) -> Double {
        max(0, min(upperBound, other.upperBound) - max(lowerBound, other.lowerBound))
    }

    /// Overlap normalized by the shorter interval, in `0...1`.
    public func overlapRatio(with other: Interval) -> Double {
        let denominator = min(length, other.length)
        guard denominator > 0 else { return 0 }
        return overlap(with: other) / denominator
    }

    public func union(_ other: Interval) -> Interval {
        Interval(
            lowerBound: min(lowerBound, other.lowerBound),
            upperBound: max(upperBound, other.upperBound)
        )
    }
}

/// 1-D interval clustering used for table row/column band inference and for
/// projection-profile gap analysis in the reading-order sorter.
public enum IntervalClustering {

    /// Groups intervals into bands: two intervals belong to the same band
    /// when their overlap ratio is at least `minOverlapRatio`. Bands are
    /// grown transitively (single-link) and returned sorted by lower bound.
    ///
    /// - Returns: For each input interval, the index of its band, plus the
    ///   band extents. `assignments[i]` is the band index of `intervals[i]`.
    public static func bands(
        of intervals: [Interval],
        minOverlapRatio: Double
    ) -> (assignments: [Int], bands: [Interval]) {
        guard !intervals.isEmpty else { return ([], []) }

        // Sort indices by interval start so band growth is a single pass.
        let order = intervals.indices.sorted {
            (intervals[$0].lowerBound, intervals[$0].upperBound)
                < (intervals[$1].lowerBound, intervals[$1].upperBound)
        }

        var bandOfIndex = [Int](repeating: -1, count: intervals.count)
        var bands: [Interval] = []
        // Track band members so band extent updates cannot dilute the
        // overlap test: a new interval must overlap at least one *member*.
        var members: [[Int]] = []

        for index in order {
            let interval = intervals[index]
            var joined = -1
            for bandIndex in bands.indices.reversed() {
                guard bands[bandIndex].overlap(with: interval) > 0 else { continue }
                let overlapsMember = members[bandIndex].contains { memberIndex in
                    intervals[memberIndex].overlapRatio(with: interval) >= minOverlapRatio
                }
                if overlapsMember {
                    joined = bandIndex
                    break
                }
            }
            if joined >= 0 {
                bands[joined] = bands[joined].union(interval)
                members[joined].append(index)
                bandOfIndex[index] = joined
            } else {
                bands.append(interval)
                members.append([index])
                bandOfIndex[index] = bands.count - 1
            }
        }

        // Renumber bands sorted by their lower bound.
        let bandOrder = bands.indices.sorted { bands[$0].lowerBound < bands[$1].lowerBound }
        var rank = [Int](repeating: 0, count: bands.count)
        for (newIndex, oldIndex) in bandOrder.enumerated() {
            rank[oldIndex] = newIndex
        }
        let sortedBands = bandOrder.map { bands[$0] }
        let assignments = bandOfIndex.map { rank[$0] }
        return (assignments, sortedBands)
    }

    /// Returns the gaps left uncovered when all `intervals` are projected
    /// onto one axis and merged. Gaps are returned in ascending order.
    public static func gaps(in intervals: [Interval]) -> [Interval] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { $0.lowerBound < $1.lowerBound }
        var gaps: [Interval] = []
        var coveredUntil = sorted[0].upperBound
        for interval in sorted.dropFirst() {
            if interval.lowerBound > coveredUntil {
                gaps.append(Interval(lowerBound: coveredUntil, upperBound: interval.lowerBound))
            }
            coveredUntil = max(coveredUntil, interval.upperBound)
        }
        return gaps
    }
}
