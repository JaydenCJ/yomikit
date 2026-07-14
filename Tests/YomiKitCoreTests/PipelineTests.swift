import XCTest
@testable import YomiKitCore

/// End-to-end orchestration tests: the whole recognize → analyze → extract
/// → export chain driven by a deterministic ``MockOCRBackend``. These run
/// on every platform, including Linux.
final class PipelineTests: XCTestCase {

    private struct StubError: Error, Sendable, Equatable {}

    func testReceiptEndToEnd() async throws {
        let backend = MockOCRBackend<String>(returning: Fixtures.receiptObservations)
        let pipeline = DocumentPipeline(backend: backend)

        let receipt = try await pipeline.receipt(in: "receipt.png")
        XCTAssertEqual(receipt.storeName, "スーパーマルヤマ 川崎店")
        XCTAssertEqual(receipt.date?.isoString, "2026-07-08")
        XCTAssertEqual(receipt.items.count, 5)
        XCTAssertEqual(receipt.total, 814)
        XCTAssertEqual(receipt.change, 186)
    }

    func testTategakiDocumentEndToEnd() async throws {
        let backend = MockOCRBackend<String>(returning: Fixtures.tategakiColumns)
        let pipeline = DocumentPipeline(backend: backend)

        let layout = try await pipeline.document(in: "novel-page.png")
        XCTAssertEqual(layout.orientation, .vertical)
        XCTAssertEqual(layout.lines.map(\.text), Fixtures.tategakiExpectedOrder)
    }

    func testTableEndToEnd() async throws {
        let backend = MockOCRBackend<String>(returning: Fixtures.table3x3)
        let pipeline = DocumentPipeline(backend: backend)

        let table = try await pipeline.table(in: "table.png")
        XCTAssertEqual(table.rowCount, 3)
        XCTAssertEqual(table.columnCount, 3)
        XCTAssertEqual(table.grid[1], ["りんご", "3", "¥450"])
    }

    func testMarkdownAndJSONExports() async throws {
        let backend = MockOCRBackend<String>(returning: Fixtures.tategakiColumns)
        let pipeline = DocumentPipeline(backend: backend)

        let markdown = try await pipeline.markdown(in: "novel-page.png")
        XCTAssertEqual(
            markdown,
            "吾輩は猫である\n名前はまだ無い\nどこで生れたか\nとんと見当がつかぬ"
        )

        let json = try await pipeline.json(in: "novel-page.png")
        XCTAssertTrue(json.contains("\"orientation\" : \"vertical\""))
        XCTAssertTrue(json.contains("吾輩は猫である"))
    }

    func testCustomLayoutOptionsAreApplied() async throws {
        let backend = MockOCRBackend<String>(returning: Fixtures.tategakiColumns)
        let pipeline = DocumentPipeline(
            backend: backend,
            layoutOptions: LayoutOptions(orientation: .horizontal)
        )
        let layout = try await pipeline.document(in: "any")
        XCTAssertEqual(layout.orientation, .horizontal)
    }

    func testHandlerBackendRoutesByImageIdentifier() async throws {
        let backend = MockOCRBackend<String> { name in
            switch name {
            case "receipt": return Fixtures.receiptObservations
            case "table": return Fixtures.table3x3
            default: return []
            }
        }
        let pipeline = DocumentPipeline(backend: backend)

        let receipt = try await pipeline.receipt(in: "receipt")
        XCTAssertEqual(receipt.total, 814)
        let table = try await pipeline.table(in: "table")
        XCTAssertEqual(table.rowCount, 3)
        let empty = try await pipeline.document(in: "unknown")
        XCTAssertTrue(empty.blocks.isEmpty)
    }

    func testBackendErrorsPropagate() async {
        let backend = MockOCRBackend<String>(throwing: StubError())
        let pipeline = DocumentPipeline(backend: backend)
        do {
            _ = try await pipeline.document(in: "any")
            XCTFail("expected the backend error to propagate")
        } catch let error as StubError {
            XCTAssertEqual(error, StubError())
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testTypeErasedBackendForwards() async throws {
        let erased = AnyOCRBackend(MockOCRBackend<String>(returning: Fixtures.table3x3))
        let observations = try await erased.recognize(in: "table")
        XCTAssertEqual(observations.count, Fixtures.table3x3.count)
    }
}

/// The minimal usage example from the README, covered verbatim so the
/// documentation cannot drift from actual behavior.
final class READMEExampleTests: XCTestCase {

    func testReadmeMinimalExample() {
        let receipt = ReceiptFieldExtractor().extract(fromLines: [
            "スーパーマルヤマ 川崎店",
            "2026年7月8日(火) 18:42",
            "おにぎり ツナマヨ ¥138",
            "合計 ¥138",
        ])
        XCTAssertEqual(receipt.storeName, "スーパーマルヤマ 川崎店")
        XCTAssertEqual(receipt.date?.isoString, "2026-07-08")
        XCTAssertEqual(receipt.total, 138)
    }
}
