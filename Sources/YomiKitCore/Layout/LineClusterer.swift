/// Groups raw observations into visual lines.
///
/// For horizontal text a line is a run of boxes that overlap vertically and
/// sit close together along the x axis. For vertical (tategaki) text the
/// roles of the axes are swapped: a "line" is a column of boxes that overlap
/// horizontally and sit close together along the y axis.
public struct LineClusterer: Sendable {

    /// Minimum overlap ratio on the cross axis (perpendicular to the reading
    /// direction) for two boxes to be considered part of the same line.
    public var minCrossOverlapRatio: Double

    /// Maximum gap along the reading axis between neighboring members,
    /// expressed as a multiple of the larger box's cross-axis size.
    /// Use `.infinity` for single-column material such as receipts, where a
    /// line may contain widely separated fragments (item name … price).
    public var maxGapFactor: Double

    public init(minCrossOverlapRatio: Double = 0.4, maxGapFactor: Double = 1.5) {
        self.minCrossOverlapRatio = minCrossOverlapRatio
        self.maxGapFactor = maxGapFactor
    }

    /// Clusters observations into lines and sorts each line's members in
    /// reading order (left→right for horizontal, top→bottom for vertical).
    /// The returned lines are not yet in page reading order — that is the
    /// job of block clustering and ``ReadingOrderSorter``.
    public func cluster(
        _ observations: [TextObservation],
        orientation: TextOrientation
    ) -> [TextLine] {
        guard !observations.isEmpty else { return [] }

        // Sort by position along the reading axis so neighbor checks are local.
        let sortedIndices = observations.indices.sorted { lhs, rhs in
            readingStart(observations[lhs].boundingBox, orientation)
                < readingStart(observations[rhs].boundingBox, orientation)
        }

        var unionFind = UnionFind(count: observations.count)
        for (position, index) in sortedIndices.enumerated() {
            let box = observations[index].boundingBox
            for otherPosition in (position + 1)..<sortedIndices.count {
                let otherIndex = sortedIndices[otherPosition]
                let otherBox = observations[otherIndex].boundingBox
                if belongToSameLine(box, otherBox, orientation: orientation) {
                    unionFind.union(index, otherIndex)
                }
                // Early exit: boxes are sorted by reading-axis start, so once
                // the start is beyond the reach of this box we can stop.
                let reach = readingEnd(box, orientation) + maxGapAbsolute(box, otherBox, orientation)
                if readingStart(otherBox, orientation) > reach && maxGapFactor.isFinite {
                    break
                }
            }
        }

        var groups: [Int: [TextObservation]] = [:]
        for index in observations.indices {
            groups[unionFind.find(index), default: []].append(observations[index])
        }

        return groups.values.map { members in
            let sorted = members.sorted {
                readingStart($0.boundingBox, orientation) < readingStart($1.boundingBox, orientation)
            }
            return TextLine(observations: sorted, orientation: orientation)
        }
    }

    // MARK: - Internals

    private func belongToSameLine(
        _ a: BoundingBox,
        _ b: BoundingBox,
        orientation: TextOrientation
    ) -> Bool {
        switch orientation {
        case .horizontal:
            guard a.verticalOverlapRatio(with: b) >= minCrossOverlapRatio else { return false }
            return a.horizontalGap(to: b) <= maxGapFactor * max(a.height, b.height)
        case .vertical:
            guard a.horizontalOverlapRatio(with: b) >= minCrossOverlapRatio else { return false }
            return a.verticalGap(to: b) <= maxGapFactor * max(a.width, b.width)
        }
    }

    private func readingStart(_ box: BoundingBox, _ orientation: TextOrientation) -> Double {
        orientation == .horizontal ? box.minX : box.minY
    }

    private func readingEnd(_ box: BoundingBox, _ orientation: TextOrientation) -> Double {
        orientation == .horizontal ? box.maxX : box.maxY
    }

    private func maxGapAbsolute(
        _ a: BoundingBox,
        _ b: BoundingBox,
        _ orientation: TextOrientation
    ) -> Double {
        let crossSize =
            orientation == .horizontal ? max(a.height, b.height) : max(a.width, b.width)
        return maxGapFactor.isFinite ? maxGapFactor * crossSize : .greatestFiniteMagnitude
    }
}

/// Minimal union-find (disjoint set) with path compression and union by size.
struct UnionFind {
    private var parent: [Int]
    private var size: [Int]

    init(count: Int) {
        parent = Array(0..<count)
        size = [Int](repeating: 1, count: count)
    }

    mutating func find(_ element: Int) -> Int {
        var root = element
        while parent[root] != root {
            root = parent[root]
        }
        // Path compression.
        var current = element
        while parent[current] != root {
            let next = parent[current]
            parent[current] = root
            current = next
        }
        return root
    }

    mutating func union(_ a: Int, _ b: Int) {
        let rootA = find(a)
        let rootB = find(b)
        guard rootA != rootB else { return }
        if size[rootA] < size[rootB] {
            parent[rootA] = rootB
            size[rootB] += size[rootA]
        } else {
            parent[rootB] = rootA
            size[rootA] += size[rootB]
        }
    }
}
