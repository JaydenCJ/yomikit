/// Reconstructs table structure (rows, columns, spans) from unordered OCR
/// fragments using alignment inference on bounding boxes — no ruling lines
/// required.
///
/// Algorithm:
/// 1. Fragments are merged into cell candidates with a tight ``LineClusterer``
///    pass (fragments of one cell sit very close together).
/// 2. Row bands are inferred from the candidates' y intervals and column
///    bands from their x intervals. Band building processes candidates from
///    narrowest to widest so that a header spanning several columns cannot
///    collapse those columns into one: a candidate overlapping two or more
///    established bands never reshapes them — it becomes a spanning cell.
/// 3. Every candidate is assigned an anchor (row, column) plus row/column
///    spans; candidates landing in the same grid position are joined.
public struct TableReconstructor: Sendable {

    /// Minimum overlap (relative to the shorter interval) for a candidate
    /// to be merged into an existing row/column band.
    public var minBandOverlapRatio: Double

    /// Gap factor for the intra-cell fragment merge (multiples of fragment
    /// height). Keep small so adjacent columns are not merged.
    public var cellMergeGapFactor: Double

    public init(minBandOverlapRatio: Double = 0.5, cellMergeGapFactor: Double = 0.6) {
        self.minBandOverlapRatio = minBandOverlapRatio
        self.cellMergeGapFactor = cellMergeGapFactor
    }

    /// Reconstructs a table from OCR fragments.
    public func reconstruct(_ observations: [TextObservation]) -> Table {
        guard !observations.isEmpty else {
            return Table(rowCount: 0, columnCount: 0, cells: [])
        }

        // 1. Merge fragments that belong to the same cell.
        let clusterer = LineClusterer(
            minCrossOverlapRatio: 0.5,
            maxGapFactor: cellMergeGapFactor
        )
        let candidates = clusterer.cluster(observations, orientation: .horizontal)

        let boxes = candidates.map(\.boundingBox)

        // 2. Infer row and column bands.
        let rowBands = Self.buildBands(
            from: boxes.map { Interval(lowerBound: $0.minY, upperBound: $0.maxY) },
            minOverlapRatio: minBandOverlapRatio
        )
        let columnBands = Self.buildBands(
            from: boxes.map { Interval(lowerBound: $0.minX, upperBound: $0.maxX) },
            minOverlapRatio: minBandOverlapRatio
        )

        // 3. Assign each candidate an anchor position and spans.
        struct Placement {
            var row: Int
            var rowSpan: Int
            var column: Int
            var columnSpan: Int
            var candidateIndex: Int
        }

        var placements: [Placement] = []
        for index in candidates.indices {
            let box = boxes[index]
            let rowAssignment = Self.assign(
                Interval(lowerBound: box.minY, upperBound: box.maxY),
                to: rowBands,
                minOverlapRatio: minBandOverlapRatio
            )
            let columnAssignment = Self.assign(
                Interval(lowerBound: box.minX, upperBound: box.maxX),
                to: columnBands,
                minOverlapRatio: minBandOverlapRatio
            )
            placements.append(
                Placement(
                    row: rowAssignment.index,
                    rowSpan: rowAssignment.span,
                    column: columnAssignment.index,
                    columnSpan: columnAssignment.span,
                    candidateIndex: index
                )
            )
        }

        // Join candidates that landed on the same anchor.
        var byPosition: [Int: [Placement]] = [:]
        for placement in placements {
            byPosition[placement.row * columnBands.count + placement.column, default: []]
                .append(placement)
        }

        var cells: [TableCell] = []
        for group in byPosition.values {
            let sortedGroup = group.sorted {
                let a = boxes[$0.candidateIndex]
                let b = boxes[$1.candidateIndex]
                return (a.minY, a.minX) < (b.minY, b.minX)
            }
            let text = sortedGroup
                .map { candidates[$0.candidateIndex].text }
                .joined()
            let box = BoundingBox.union(of: sortedGroup.map { boxes[$0.candidateIndex] })!
            let first = sortedGroup[0]
            cells.append(
                TableCell(
                    row: first.row,
                    column: first.column,
                    rowSpan: sortedGroup.map(\.rowSpan).max() ?? 1,
                    columnSpan: sortedGroup.map(\.columnSpan).max() ?? 1,
                    text: text,
                    boundingBox: box
                )
            )
        }

        return Table(rowCount: rowBands.count, columnCount: columnBands.count, cells: cells)
    }

    // MARK: - Band inference

    /// Builds alignment bands from 1-D intervals, processing narrow
    /// intervals first. An interval overlapping exactly one band extends
    /// that band; an interval overlapping several bands (a spanning cell)
    /// leaves them untouched.
    static func buildBands(from intervals: [Interval], minOverlapRatio: Double) -> [Interval] {
        var bands: [Interval] = []
        for interval in intervals.sorted(by: { $0.length < $1.length }) {
            let overlapping = bands.indices.filter { bandIndex in
                let band = bands[bandIndex]
                let denominator = min(band.length, interval.length)
                guard denominator > 0 else { return false }
                return band.overlap(with: interval) >= minOverlapRatio * denominator
            }
            if overlapping.isEmpty {
                bands.append(interval)
            } else if overlapping.count == 1 {
                bands[overlapping[0]] = bands[overlapping[0]].union(interval)
            }
            // count > 1: spanning cell; bands stay as they are.
        }
        return bands.sorted { $0.lowerBound < $1.lowerBound }
    }

    /// Maps an interval onto (band index, span) against sorted bands.
    static func assign(
        _ interval: Interval,
        to bands: [Interval],
        minOverlapRatio: Double
    ) -> (index: Int, span: Int) {
        let hits = bands.indices.filter { bandIndex in
            let band = bands[bandIndex]
            let denominator = min(band.length, interval.length)
            guard denominator > 0 else { return false }
            return band.overlap(with: interval) >= minOverlapRatio * denominator
        }
        if let first = hits.first, let last = hits.last {
            return (first, last - first + 1)
        }
        // No confident overlap: fall back to the nearest band by center.
        let nearest =
            bands.indices.min {
                abs(bands[$0].center - interval.center) < abs(bands[$1].center - interval.center)
            } ?? 0
        return (nearest, 1)
    }
}
