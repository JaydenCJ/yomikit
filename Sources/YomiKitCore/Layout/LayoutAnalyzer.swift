/// Options controlling the layout pipeline.
public struct LayoutOptions: Sendable {
    /// Force a writing direction instead of auto-detecting it.
    public var orientation: TextOrientation?

    /// See ``LineClusterer/minCrossOverlapRatio``.
    public var lineCrossOverlapRatio: Double

    /// See ``LineClusterer/maxGapFactor``. Use `.infinity` for single-column
    /// material such as receipts.
    public var lineGapFactor: Double

    /// See ``BlockClusterer/minAlignmentOverlapRatio``.
    public var blockAlignmentOverlapRatio: Double

    /// See ``BlockClusterer/maxGapFactor``.
    public var blockGapFactor: Double

    /// Observations below this confidence are dropped before analysis.
    public var minConfidence: Double

    public init(
        orientation: TextOrientation? = nil,
        lineCrossOverlapRatio: Double = 0.4,
        lineGapFactor: Double = 1.5,
        blockAlignmentOverlapRatio: Double = 0.3,
        blockGapFactor: Double = 1.2,
        minConfidence: Double = 0.0
    ) {
        self.orientation = orientation
        self.lineCrossOverlapRatio = lineCrossOverlapRatio
        self.lineGapFactor = lineGapFactor
        self.blockAlignmentOverlapRatio = blockAlignmentOverlapRatio
        self.blockGapFactor = blockGapFactor
        self.minConfidence = minConfidence
    }

    /// Sensible defaults for general documents.
    public static let `default` = LayoutOptions()

    /// Defaults tuned for receipts: single column, unlimited in-line gaps so
    /// "item ......... price" rows stay on one line.
    public static let receipt = LayoutOptions(
        orientation: .horizontal,
        lineGapFactor: .infinity,
        blockGapFactor: 2.0
    )
}

/// The end-to-end layout pipeline:
/// orientation detection → line clustering → block clustering → reading order.
public struct LayoutAnalyzer: Sendable {
    public var options: LayoutOptions

    public init(options: LayoutOptions = .default) {
        self.options = options
    }

    /// Analyzes raw OCR observations into a ``DocumentLayout`` whose blocks
    /// and lines are in natural reading order (right→left column order for
    /// vertical text).
    public func analyze(_ observations: [TextObservation]) -> DocumentLayout {
        let usable = observations.filter { $0.confidence >= options.minConfidence }
        guard !usable.isEmpty else {
            return DocumentLayout(blocks: [], orientation: options.orientation ?? .horizontal)
        }

        let orientation =
            options.orientation
            ?? OrientationClassifier().classify(usable)

        let lineClusterer = LineClusterer(
            minCrossOverlapRatio: options.lineCrossOverlapRatio,
            maxGapFactor: options.lineGapFactor
        )
        let lines = lineClusterer.cluster(usable, orientation: orientation)

        let blockClusterer = BlockClusterer(
            minAlignmentOverlapRatio: options.blockAlignmentOverlapRatio,
            maxGapFactor: options.blockGapFactor
        )
        let blocks = blockClusterer.cluster(lines, orientation: orientation)

        let sorter = ReadingOrderSorter()
        let ordered = sorter.sorted(blocks, boxes: \.boundingBox, orientation: orientation)

        return DocumentLayout(blocks: ordered, orientation: orientation)
    }
}
