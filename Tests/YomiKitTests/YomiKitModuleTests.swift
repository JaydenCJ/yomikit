import XCTest
import YomiKit

/// Tests for the umbrella `YomiKit` module. On Linux the Apple-specific
/// sources are compiled out, so these tests verify the platform gates and
/// that the re-exported core API is fully usable through `import YomiKit`.
final class YomiKitModuleTests: XCTestCase {

    func testVersionsAreConsistent() {
        XCTAssertEqual(YomiKitInfo.version, "0.1.0")
        XCTAssertEqual(YomiKitInfo.version, YomiKitCore.version)
    }

    func testFeatureFlagsMatchPlatformCapabilities() {
        #if canImport(Vision)
        XCTAssertTrue(YomiKitInfo.hasVisionSupport)
        #else
        XCTAssertFalse(YomiKitInfo.hasVisionSupport)
        #endif

        #if canImport(CoreML)
        XCTAssertTrue(YomiKitInfo.hasCoreMLSupport)
        #else
        XCTAssertFalse(YomiKitInfo.hasCoreMLSupport)
        #endif
    }

    func testCoreAPIIsReexported() async throws {
        // The whole core pipeline must be reachable through `import YomiKit`
        // alone (no separate `import YomiKitCore`).
        let observations = [
            TextObservation(
                text: "コーヒー",
                boundingBox: BoundingBox(x: 10, y: 10, width: 80, height: 16)
            ),
            TextObservation(
                text: "¥480",
                boundingBox: BoundingBox(x: 200, y: 10, width: 40, height: 16)
            ),
        ]
        let pipeline = DocumentPipeline(
            backend: MockOCRBackend<Int>(returning: observations),
            layoutOptions: .receipt
        )
        let layout = try await pipeline.document(in: 1)
        XCTAssertEqual(layout.lines.count, 1)
        XCTAssertEqual(layout.lines[0].spacedText, "コーヒー ¥480")
    }
}
