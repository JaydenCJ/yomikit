/// Groups lines into logical blocks (paragraphs / column segments).
///
/// Two lines belong to the same block when they are aligned on the reading
/// axis (their extents overlap) and the gap between them on the stacking
/// axis is small relative to the typical line size. For horizontal text
/// lines stack along y; for vertical (tategaki) text, columns stack along x.
public struct BlockClusterer: Sendable {

    /// Minimum overlap ratio along the reading axis for two lines to be
    /// considered part of the same block (guards against merging side-by-side
    /// columns whose lines barely overlap).
    public var minAlignmentOverlapRatio: Double

    /// Maximum stacking-axis gap between neighboring lines, expressed as a
    /// multiple of the median line size (height for horizontal text, width
    /// for vertical text).
    public var maxGapFactor: Double

    public init(minAlignmentOverlapRatio: Double = 0.3, maxGapFactor: Double = 1.2) {
        self.minAlignmentOverlapRatio = minAlignmentOverlapRatio
        self.maxGapFactor = maxGapFactor
    }

    /// Clusters lines into blocks. Lines inside each block are sorted in
    /// stacking order (top→bottom for horizontal, right→left for vertical).
    /// Blocks themselves are *not* yet in reading order.
    public func cluster(
        _ lines: [TextLine],
        orientation: TextOrientation
    ) -> [TextBlock] {
        guard !lines.isEmpty else { return [] }

        let boxes = lines.map(\.boundingBox)
        let referenceSize = median(
            boxes.map { orientation == .horizontal ? $0.height : $0.width }
        )
        let maxGap = maxGapFactor * referenceSize

        var unionFind = UnionFind(count: lines.count)
        for i in lines.indices {
            for j in (i + 1)..<lines.count {
                if belongToSameBlock(boxes[i], boxes[j], orientation: orientation, maxGap: maxGap) {
                    unionFind.union(i, j)
                }
            }
        }

        var groups: [Int: [Int]] = [:]
        for index in lines.indices {
            groups[unionFind.find(index), default: []].append(index)
        }

        return groups.values.map { memberIndices in
            let sorted = memberIndices.sorted { lhs, rhs in
                switch orientation {
                case .horizontal:
                    // Top to bottom.
                    return boxes[lhs].midY < boxes[rhs].midY
                case .vertical:
                    // Right to left.
                    return boxes[lhs].midX > boxes[rhs].midX
                }
            }
            return TextBlock(lines: sorted.map { lines[$0] }, orientation: orientation)
        }
    }

    private func belongToSameBlock(
        _ a: BoundingBox,
        _ b: BoundingBox,
        orientation: TextOrientation,
        maxGap: Double
    ) -> Bool {
        switch orientation {
        case .horizontal:
            return a.horizontalOverlapRatio(with: b) >= minAlignmentOverlapRatio
                && a.verticalGap(to: b) <= maxGap
        case .vertical:
            return a.verticalOverlapRatio(with: b) >= minAlignmentOverlapRatio
                && a.horizontalGap(to: b) <= maxGap
        }
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
