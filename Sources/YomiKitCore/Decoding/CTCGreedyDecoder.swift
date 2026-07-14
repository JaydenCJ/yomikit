/// Greedy (best-path) CTC decoding for text-recognition models.
///
/// Custom recognition models converted with `tools/convert_recognizer.py`
/// emit per-timestep class logits. This decoder collapses repeated classes,
/// removes blanks, and maps class indices to characters via a vocabulary —
/// the standard CTC best-path decode. It lives in YomiKitCore because it is
/// pure logic and unit-testable on any platform; the Core ML layer feeds it
/// with model outputs.
public struct CTCGreedyDecoder: Sendable {

    /// The model's character set, indexed by class id.
    public var vocabulary: [String]
    /// Class id reserved for the CTC blank symbol.
    public var blankIndex: Int

    /// - Parameters:
    ///   - vocabulary: Characters by class index. Entries may be multi-scalar
    ///     strings (e.g. combined forms) — they are appended verbatim.
    ///   - blankIndex: Index of the blank class. Defaults to 0, the most
    ///     common convention.
    public init(vocabulary: [String], blankIndex: Int = 0) {
        self.vocabulary = vocabulary
        self.blankIndex = blankIndex
    }

    /// The result of decoding one sequence.
    public struct DecodedText: Sendable, Hashable {
        public var text: String
        /// Mean probability of the emitted (non-blank, non-repeat) steps.
        /// `1.0` when the input carries no probabilities.
        public var confidence: Double

        public init(text: String, confidence: Double) {
            self.text = text
            self.confidence = confidence
        }
    }

    /// Decodes a sequence of per-timestep class indices.
    public func decode(classIndices: [Int]) -> DecodedText {
        var output = ""
        var previous = blankIndex
        for index in classIndices {
            defer { previous = index }
            guard index != blankIndex, index != previous else { continue }
            guard vocabulary.indices.contains(index) else { continue }
            output += vocabulary[index]
        }
        return DecodedText(text: output, confidence: 1.0)
    }

    /// Decodes a `[timesteps][classes]` matrix of probabilities or logits by
    /// taking the arg-max at each step (best path).
    public func decode(logits: [[Double]]) -> DecodedText {
        var indices: [Int] = []
        var emittedProbabilities: [Double] = []
        var previous = blankIndex

        for step in logits {
            guard let maxValue = step.max(), let index = step.firstIndex(of: maxValue) else {
                continue
            }
            indices.append(index)
            if index != blankIndex, index != previous {
                emittedProbabilities.append(maxValue)
            }
            previous = index
        }

        let decoded = decode(classIndices: indices)
        let confidence: Double
        if emittedProbabilities.isEmpty {
            confidence = decoded.text.isEmpty ? 0 : 1
        } else {
            // Only meaningful when the matrix holds probabilities (softmax
            // output); with raw logits callers should ignore confidence.
            confidence = emittedProbabilities.reduce(0, +) / Double(emittedProbabilities.count)
        }
        return DecodedText(text: decoded.text, confidence: min(max(confidence, 0), 1))
    }
}
