/// An axis-aligned bounding box in image coordinates.
///
/// YomiKit uses a **top-left origin** coordinate system: `x` grows to the
/// right and `y` grows downward, matching typical raster image coordinates.
/// Platform layers (e.g. Vision, whose normalized coordinates are
/// bottom-left based) are responsible for converting into this space before
/// handing observations to the core algorithms.
public struct BoundingBox: Sendable, Hashable, Codable {
    /// Left edge.
    public var x: Double
    /// Top edge.
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var maxX: Double { x + width }
    public var minY: Double { y }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var area: Double { width * height }

    /// The smallest box containing both `self` and `other`.
    public func union(_ other: BoundingBox) -> BoundingBox {
        let minX = Swift.min(minX, other.minX)
        let minY = Swift.min(minY, other.minY)
        let maxX = Swift.max(maxX, other.maxX)
        let maxY = Swift.max(maxY, other.maxY)
        return BoundingBox(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The smallest box containing every box in `boxes`, or `nil` when empty.
    public static func union(of boxes: [BoundingBox]) -> BoundingBox? {
        guard var result = boxes.first else { return nil }
        for box in boxes.dropFirst() {
            result = result.union(box)
        }
        return result
    }

    /// Length of the overlap of the two boxes' projections onto the x axis.
    public func horizontalOverlap(with other: BoundingBox) -> Double {
        max(0, min(maxX, other.maxX) - max(minX, other.minX))
    }

    /// Length of the overlap of the two boxes' projections onto the y axis.
    public func verticalOverlap(with other: BoundingBox) -> Double {
        max(0, min(maxY, other.maxY) - max(minY, other.minY))
    }

    /// Overlap of the x projections, normalized by the narrower box's width.
    /// `1.0` means the narrower box is fully covered; `0.0` means disjoint.
    public func horizontalOverlapRatio(with other: BoundingBox) -> Double {
        let denominator = min(width, other.width)
        guard denominator > 0 else { return 0 }
        return horizontalOverlap(with: other) / denominator
    }

    /// Overlap of the y projections, normalized by the shorter box's height.
    public func verticalOverlapRatio(with other: BoundingBox) -> Double {
        let denominator = min(height, other.height)
        guard denominator > 0 else { return 0 }
        return verticalOverlap(with: other) / denominator
    }

    /// Horizontal gap between two boxes (0 when their x projections overlap).
    public func horizontalGap(to other: BoundingBox) -> Double {
        max(0, max(minX, other.minX) - min(maxX, other.maxX))
    }

    /// Vertical gap between two boxes (0 when their y projections overlap).
    public func verticalGap(to other: BoundingBox) -> Double {
        max(0, max(minY, other.minY) - min(maxY, other.maxY))
    }

    /// Whether the two boxes intersect (touching edges count as intersecting).
    public func intersects(_ other: BoundingBox) -> Bool {
        minX <= other.maxX && other.minX <= maxX && minY <= other.maxY && other.minY <= maxY
    }
}
