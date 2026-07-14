/// Orders layout elements (typically blocks) into natural reading order
/// using a recursive XY-cut over projection-profile gaps.
///
/// * Horizontal (yokogaki) pages: columns are visited left→right, content
///   within a column top→bottom. A vertical gutter that spans the region
///   splits it into columns; a horizontal gap splits it into stacked
///   sections. Column cuts are preferred so multi-column pages are read
///   column by column, but a full-width header still comes first because no
///   column gutter crosses it.
/// * Vertical (tategaki) pages: the mirror image. Sections stack top→bottom
///   (Japanese newspaper "dan"), and within a section content is visited
///   right→left. Section (y) cuts are preferred.
public struct ReadingOrderSorter: Sendable {

    /// Gaps narrower than this fraction of the region's extent on the cut
    /// axis are ignored, so sub-pixel jitter never produces spurious cuts.
    public var minGapRatio: Double

    public init(minGapRatio: Double = 0.005) {
        self.minGapRatio = minGapRatio
    }

    /// Returns the indices of `boxes` in reading order.
    public func orderedIndices(
        of boxes: [BoundingBox],
        orientation: TextOrientation
    ) -> [Int] {
        order(Array(boxes.indices), boxes: boxes, orientation: orientation)
    }

    /// Sorts `items` into reading order using the box provided for each item.
    public func sorted<T>(
        _ items: [T],
        boxes: (T) -> BoundingBox,
        orientation: TextOrientation
    ) -> [T] {
        let boxList = items.map(boxes)
        return orderedIndices(of: boxList, orientation: orientation).map { items[$0] }
    }

    // MARK: - Recursive XY-cut

    private enum Axis {
        case x
        case y
    }

    private func order(
        _ indices: [Int],
        boxes: [BoundingBox],
        orientation: TextOrientation
    ) -> [Int] {
        guard indices.count > 1 else { return indices }

        let xIntervals = indices.map { Interval(lowerBound: boxes[$0].minX, upperBound: boxes[$0].maxX) }
        let yIntervals = indices.map { Interval(lowerBound: boxes[$0].minY, upperBound: boxes[$0].maxY) }

        let xExtent = extent(of: xIntervals)
        let yExtent = extent(of: yIntervals)
        let xGaps = IntervalClustering.gaps(in: xIntervals).filter { $0.length >= minGapRatio * xExtent }
        let yGaps = IntervalClustering.gaps(in: yIntervals).filter { $0.length >= minGapRatio * yExtent }

        let axis: Axis?
        switch orientation {
        case .horizontal:
            // Prefer column cuts (x) so multi-column pages read column-first.
            axis = !xGaps.isEmpty ? .x : (!yGaps.isEmpty ? .y : nil)
        case .vertical:
            // Prefer section cuts (y); within a section, columns go right→left.
            axis = !yGaps.isEmpty ? .y : (!xGaps.isEmpty ? .x : nil)
        }

        guard let axis else {
            return fallbackSort(indices, boxes: boxes, orientation: orientation)
        }

        let gaps = axis == .x ? xGaps : yGaps
        var segments = partition(indices, boxes: boxes, axis: axis, gaps: gaps)

        // Order the segments along the cut axis.
        switch (axis, orientation) {
        case (.x, .horizontal):
            segments.sort { $0.position < $1.position } // left → right
        case (.x, .vertical):
            segments.sort { $0.position > $1.position } // right → left
        case (.y, _):
            segments.sort { $0.position < $1.position } // top → bottom
        }

        return segments.flatMap { order($0.indices, boxes: boxes, orientation: orientation) }
    }

    private struct Segment {
        var indices: [Int]
        var position: Double
    }

    private func partition(
        _ indices: [Int],
        boxes: [BoundingBox],
        axis: Axis,
        gaps: [Interval]
    ) -> [Segment] {
        // Cut points are gap centers; each element falls strictly on one side.
        let cuts = gaps.map(\.center).sorted()
        var buckets: [[Int]] = Array(repeating: [], count: cuts.count + 1)
        for index in indices {
            let center = axis == .x ? boxes[index].midX : boxes[index].midY
            // First cut greater than the element's center decides its bucket.
            let bucket = cuts.firstIndex { center < $0 } ?? cuts.count
            buckets[bucket].append(index)
        }
        return buckets.compactMap { bucket in
            guard !bucket.isEmpty else { return nil }
            let position = bucket
                .map { axis == .x ? boxes[$0].midX : boxes[$0].midY }
                .reduce(0, +) / Double(bucket.count)
            return Segment(indices: bucket, position: position)
        }
    }

    /// Ordering when no projection gap exists (heavily overlapping layout):
    /// stable positional sort.
    private func fallbackSort(
        _ indices: [Int],
        boxes: [BoundingBox],
        orientation: TextOrientation
    ) -> [Int] {
        switch orientation {
        case .horizontal:
            return indices.sorted {
                (boxes[$0].midY, boxes[$0].midX) < (boxes[$1].midY, boxes[$1].midX)
            }
        case .vertical:
            return indices.sorted {
                (boxes[$0].midY, -boxes[$0].midX) < (boxes[$1].midY, -boxes[$1].midX)
            }
        }
    }

    private func extent(of intervals: [Interval]) -> Double {
        guard let first = intervals.first else { return 0 }
        let lower = intervals.reduce(first.lowerBound) { min($0, $1.lowerBound) }
        let upper = intervals.reduce(first.upperBound) { max($0, $1.upperBound) }
        return upper - lower
    }
}
