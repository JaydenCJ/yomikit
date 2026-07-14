import Foundation

/// The vocabulary sidecar file that `tools/convert_recognizer.py` writes
/// next to the converted model (`<output>-vocab.json`):
///
/// ```json
/// {
///   "blankIndex": 0,
///   "vocabulary": ["<blank>", "あ", "い", "…"]
/// }
/// ```
///
/// Load it with ``init(contentsOf:)`` and hand it to ``CTCGreedyDecoder``
/// or to `CoreMLTextRecognizer.Configuration` (YomiKit target), so the
/// Swift side always uses exactly the class mapping the conversion script
/// exported. The format is validated by a fixture generated from a real
/// run of the conversion script (see `Tests/YomiKitCoreTests/Resources`).
public struct RecognizerVocabulary: Sendable, Hashable, Codable {

    /// Class index → character (or multi-scalar token) mapping.
    public var vocabulary: [String]
    /// The CTC blank class index recorded by the conversion script.
    public var blankIndex: Int

    public enum ValidationError: Error, Sendable, Equatable {
        /// The vocabulary array is empty.
        case emptyVocabulary
        /// `blankIndex` does not point inside the vocabulary array.
        case blankIndexOutOfRange(blankIndex: Int, vocabularySize: Int)
    }

    /// Creates a validated vocabulary.
    /// - Throws: ``ValidationError`` when the vocabulary is empty or the
    ///   blank index is outside its bounds.
    public init(vocabulary: [String], blankIndex: Int = 0) throws {
        guard !vocabulary.isEmpty else {
            throw ValidationError.emptyVocabulary
        }
        guard vocabulary.indices.contains(blankIndex) else {
            throw ValidationError.blankIndexOutOfRange(
                blankIndex: blankIndex,
                vocabularySize: vocabulary.count
            )
        }
        self.vocabulary = vocabulary
        self.blankIndex = blankIndex
    }

    /// Decodes the JSON produced by `tools/convert_recognizer.py`.
    public init(data: Data) throws {
        let decoded = try JSONDecoder().decode(Raw.self, from: data)
        try self.init(vocabulary: decoded.vocabulary, blankIndex: decoded.blankIndex)
    }

    /// Reads and decodes a `<output>-vocab.json` file from disk.
    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url))
    }

    /// Number of classes (including the blank).
    public var count: Int { vocabulary.count }

    /// Mirror of the on-disk shape, decoded without validation first so
    /// that validation errors are reported as ``ValidationError`` instead
    /// of a generic decoding failure.
    private struct Raw: Codable {
        var vocabulary: [String]
        var blankIndex: Int
    }
}

extension CTCGreedyDecoder {
    /// Creates a decoder from a vocabulary file exported by
    /// `tools/convert_recognizer.py`.
    public init(vocabulary: RecognizerVocabulary) {
        self.init(vocabulary: vocabulary.vocabulary, blankIndex: vocabulary.blankIndex)
    }
}
