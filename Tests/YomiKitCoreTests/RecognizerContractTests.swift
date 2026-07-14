import Foundation
import XCTest
@testable import YomiKitCore

/// Tests pinning the contract between the Python model tools and the Swift
/// decoding side.
///
/// The fixtures in `Resources/` are the *actual output* of running
/// `tools/distill_recognizer.py` and `tools/convert_recognizer.py` against a
/// tiny randomly-initialized teacher model (see `tools/README.md`,
/// "What has been verified"):
///
/// * `tiny-recognizer-vocab.json` — the `<output>-vocab.json` sidecar
///   exactly as the conversion script wrote it.
/// * `tiny-recognizer-roundtrip.json` — real per-timestep logits produced
///   by the distilled TorchScript student on a synthetic line image, plus
///   the Python reference greedy-CTC decode of those values.
///
/// If either side of the contract drifts (JSON shape, blank handling,
/// greedy decode semantics), these tests fail.
final class RecognizerContractTests: XCTestCase {

    private func resourceURL(_ name: String) throws -> URL {
        let url = Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Resources"
        )
        return try XCTUnwrap(url, "missing test resource \(name).json")
    }

    // MARK: - Vocabulary sidecar format

    func testConversionScriptVocabularyFileParses() throws {
        let vocabulary = try RecognizerVocabulary(
            contentsOf: try resourceURL("tiny-recognizer-vocab")
        )
        XCTAssertEqual(vocabulary.count, 25)
        XCTAssertEqual(vocabulary.blankIndex, 0)
        XCTAssertEqual(vocabulary.vocabulary[0], "<blank>")
        // The tiny vocabulary is "<blank>" + 吾輩は猫である… + digits.
        XCTAssertEqual(vocabulary.vocabulary[1], "吾")
        XCTAssertEqual(vocabulary.vocabulary[24], "9")
    }

    func testVocabularyValidationRejectsBadBlankIndex() {
        XCTAssertThrowsError(
            try RecognizerVocabulary(vocabulary: ["<blank>", "あ"], blankIndex: 2)
        ) { error in
            XCTAssertEqual(
                error as? RecognizerVocabulary.ValidationError,
                .blankIndexOutOfRange(blankIndex: 2, vocabularySize: 2)
            )
        }
        XCTAssertThrowsError(
            try RecognizerVocabulary(vocabulary: [], blankIndex: 0)
        ) { error in
            XCTAssertEqual(
                error as? RecognizerVocabulary.ValidationError,
                .emptyVocabulary
            )
        }
    }

    func testVocabularyValidationRejectsMalformedJSON() {
        let malformed = Data(#"{"vocabulary": "not-an-array"}"#.utf8)
        XCTAssertThrowsError(try RecognizerVocabulary(data: malformed))
    }

    // MARK: - Logits round trip

    /// The decoded fixture payload (produced by the fixture dump script).
    private struct RoundtripFixture: Decodable {
        var blankIndex: Int
        var vocabulary: [String]
        var logits: [[Double]]
        var greedyText: String
    }

    func testSwiftDecoderMatchesPythonGreedyDecodeOnRealModelLogits() throws {
        let data = try Data(contentsOf: try resourceURL("tiny-recognizer-roundtrip"))
        let fixture = try JSONDecoder().decode(RoundtripFixture.self, from: data)

        // Shape sanity: the tiny model is 320 px wide / 4 = 80 timesteps,
        // 25 classes, matching the converted Core ML package metadata.
        XCTAssertEqual(fixture.logits.count, 80)
        XCTAssertEqual(fixture.logits[0].count, 25)

        let decoder = CTCGreedyDecoder(
            vocabulary: fixture.vocabulary,
            blankIndex: fixture.blankIndex
        )
        let decoded = decoder.decode(logits: fixture.logits)
        XCTAssertEqual(decoded.text, fixture.greedyText)
        XCTAssertFalse(decoded.text.isEmpty, "fixture should exercise emissions")
    }

    func testDecoderInitFromVocabularyFileMatchesManualInit() throws {
        let vocabulary = try RecognizerVocabulary(
            contentsOf: try resourceURL("tiny-recognizer-vocab")
        )
        let fromFile = CTCGreedyDecoder(vocabulary: vocabulary)
        let manual = CTCGreedyDecoder(
            vocabulary: vocabulary.vocabulary,
            blankIndex: vocabulary.blankIndex
        )
        // Indices 1,1,0,2 collapse to vocab[1] + vocab[2] either way.
        let sequence = [1, 1, 0, 2]
        XCTAssertEqual(
            fromFile.decode(classIndices: sequence),
            manual.decode(classIndices: sequence)
        )
        XCTAssertEqual(fromFile.decode(classIndices: sequence).text, "吾輩")
    }

    // MARK: - Region orientation (drives vertical-column rotation)

    func testRegionClassificationForBackendRotationDecision() {
        let classifier = OrientationClassifier()
        // A tategaki column crop: much taller than wide -> vertical.
        XCTAssertEqual(classifier.classifyRegion(width: 30, height: 270), .vertical)
        // A horizontal line crop -> horizontal.
        XCTAssertEqual(classifier.classifyRegion(width: 180, height: 28), .horizontal)
        // Near-square regions carry no signal -> nil (no rotation).
        XCTAssertNil(classifier.classifyRegion(width: 20, height: 24))
        // Degenerate boxes -> nil.
        XCTAssertNil(classifier.classifyRegion(width: 0, height: 40))
        XCTAssertNil(classifier.classifyRegion(width: 40, height: 0))
        // Exactly at the threshold counts as directional.
        XCTAssertEqual(classifier.classifyRegion(width: 16, height: 25.6), .vertical)
    }
}
