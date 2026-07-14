/// Writing direction of a run of text.
public enum TextOrientation: String, Sendable, Hashable, Codable, CaseIterable {
    /// Horizontal writing (yokogaki): left to right, lines stack top to bottom.
    case horizontal
    /// Vertical writing (tategaki): top to bottom, columns stack right to left.
    case vertical
}

/// A single piece of recognized text with its location on the page.
///
/// This is the exchange type between recognition backends (Vision, Core ML,
/// or any custom OCR engine) and the platform-independent layout pipeline.
/// Depending on the backend, one observation may be a character, a word, or
/// a whole line fragment — the layout algorithms only assume that
/// observations do not span multiple lines.
public struct TextObservation: Sendable, Hashable, Codable {
    /// The recognized text.
    public var text: String
    /// Location in top-left-origin image coordinates. See ``BoundingBox``.
    public var boundingBox: BoundingBox
    /// Recognition confidence in `0...1`. Defaults to `1`.
    public var confidence: Double

    public init(text: String, boundingBox: BoundingBox, confidence: Double = 1.0) {
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}

/// A sequence of observations merged into one visual line
/// (or one vertical column of characters for tategaki text).
public struct TextLine: Sendable, Hashable, Codable {
    /// Member observations sorted in reading order within the line.
    public var observations: [TextObservation]
    /// Writing direction of this line.
    public var orientation: TextOrientation

    public init(observations: [TextObservation], orientation: TextOrientation) {
        self.observations = observations
        self.orientation = orientation
    }

    /// The line's text: member texts joined without separators, following
    /// Japanese convention (no spaces between adjacent fragments).
    public var text: String {
        observations.map(\.text).joined()
    }

    /// The line's text with fragments joined by a single space, which is more
    /// natural for Latin-script content.
    public var spacedText: String {
        observations.map(\.text).joined(separator: " ")
    }

    public var boundingBox: BoundingBox {
        BoundingBox.union(of: observations.map(\.boundingBox))
            ?? BoundingBox(x: 0, y: 0, width: 0, height: 0)
    }

    /// Mean confidence of member observations.
    public var confidence: Double {
        guard !observations.isEmpty else { return 0 }
        return observations.map(\.confidence).reduce(0, +) / Double(observations.count)
    }
}

/// A group of lines forming one logical block (paragraph, column segment,
/// heading, caption, ...). Lines are stored in reading order.
public struct TextBlock: Sendable, Hashable, Codable {
    public var lines: [TextLine]
    public var orientation: TextOrientation

    public init(lines: [TextLine], orientation: TextOrientation) {
        self.lines = lines
        self.orientation = orientation
    }

    /// Block text with one line per row.
    public var text: String {
        lines.map(\.text).joined(separator: "\n")
    }

    public var boundingBox: BoundingBox {
        BoundingBox.union(of: lines.map(\.boundingBox))
            ?? BoundingBox(x: 0, y: 0, width: 0, height: 0)
    }
}

/// The result of layout analysis: blocks sorted in reading order.
public struct DocumentLayout: Sendable, Hashable, Codable {
    /// Blocks in reading order (for tategaki documents: right to left).
    public var blocks: [TextBlock]
    /// The dominant writing direction of the page.
    public var orientation: TextOrientation

    public init(blocks: [TextBlock], orientation: TextOrientation) {
        self.blocks = blocks
        self.orientation = orientation
    }

    /// Full document text: blocks separated by blank lines.
    public var text: String {
        blocks.map(\.text).joined(separator: "\n\n")
    }

    /// All lines of the document in reading order.
    public var lines: [TextLine] {
        blocks.flatMap(\.lines)
    }
}
