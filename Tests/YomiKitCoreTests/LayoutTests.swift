import XCTest
@testable import YomiKitCore

final class OrientationClassifierTests: XCTestCase {

    func testWideBoxesAreHorizontal() {
        let observations = [
            Fixtures.obs("こんにちは", x: 0, y: 0, w: 100, h: 16),
            Fixtures.obs("世界", x: 0, y: 30, w: 40, h: 16),
        ]
        XCTAssertEqual(OrientationClassifier().classify(observations), .horizontal)
    }

    func testTallBoxesAreVertical() {
        XCTAssertEqual(
            OrientationClassifier().classify(Fixtures.tategakiColumns),
            .vertical
        )
    }

    func testLargeAreaOutvotesSmallNoise() {
        let observations = [
            // One big vertical body column.
            Fixtures.obs("縦書き本文の長い列", x: 300, y: 20, w: 24, h: 400),
            // Two small horizontal fragments (page number, furigana noise).
            Fixtures.obs("12", x: 20, y: 500, w: 30, h: 12),
            Fixtures.obs("ページ", x: 60, y: 500, w: 50, h: 12),
        ]
        XCTAssertEqual(OrientationClassifier().classify(observations), .vertical)
    }

    func testEmptyInputDefaultsToHorizontal() {
        XCTAssertEqual(OrientationClassifier().classify([]), .horizontal)
    }
}

final class LineClustererTests: XCTestCase {

    func testHorizontalFragmentsMergeIntoLinesAndSortByX() {
        let observations = [
            Fixtures.obs("世界", x: 60, y: 0, w: 40, h: 16),
            Fixtures.obs("こんにちは", x: 0, y: 1, w: 55, h: 16),
            Fixtures.obs("二行目", x: 0, y: 30, w: 60, h: 16),
        ]
        let lines = LineClusterer().cluster(observations, orientation: .horizontal)
            .sorted { $0.boundingBox.minY < $1.boundingBox.minY }
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].text, "こんにちは世界")
        XCTAssertEqual(lines[0].spacedText, "こんにちは 世界")
        XCTAssertEqual(lines[1].text, "二行目")
    }

    func testWideGapSplitsLinesUnlessInfinite() {
        let observations = [
            Fixtures.obs("左", x: 0, y: 0, w: 30, h: 16),
            Fixtures.obs("右", x: 300, y: 0, w: 30, h: 16),
        ]
        let strict = LineClusterer(maxGapFactor: 1.5)
            .cluster(observations, orientation: .horizontal)
        XCTAssertEqual(strict.count, 2)

        let receiptStyle = LineClusterer(maxGapFactor: .infinity)
            .cluster(observations, orientation: .horizontal)
        XCTAssertEqual(receiptStyle.count, 1)
        XCTAssertEqual(receiptStyle[0].spacedText, "左 右")
    }

    func testVerticalColumnsClusterAlongY() {
        let observations = [
            Fixtures.obs("下", x: 100, y: 60, w: 20, h: 40),
            Fixtures.obs("上", x: 101, y: 10, w: 20, h: 40),
            Fixtures.obs("別の列", x: 40, y: 10, w: 20, h: 90),
        ]
        let lines = LineClusterer().cluster(observations, orientation: .vertical)
            .sorted { $0.boundingBox.minX > $1.boundingBox.minX }
        XCTAssertEqual(lines.count, 2)
        // Within a vertical line, members read top → bottom.
        XCTAssertEqual(lines[0].text, "上下")
        XCTAssertEqual(lines[1].text, "別の列")
    }

    func testConfidenceIsAveraged() {
        let observations = [
            TextObservation(
                text: "a",
                boundingBox: BoundingBox(x: 0, y: 0, width: 10, height: 10),
                confidence: 1.0
            ),
            TextObservation(
                text: "b",
                boundingBox: BoundingBox(x: 12, y: 0, width: 10, height: 10),
                confidence: 0.5
            ),
        ]
        let lines = LineClusterer().cluster(observations, orientation: .horizontal)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].confidence, 0.75, accuracy: 1e-9)
    }
}

final class BlockClustererTests: XCTestCase {

    func testParagraphGapSplitsBlocks() {
        let lineA1 = TextLine(
            observations: [Fixtures.obs("段落一の一", x: 0, y: 0, w: 100, h: 16)],
            orientation: .horizontal
        )
        let lineA2 = TextLine(
            observations: [Fixtures.obs("段落一の二", x: 0, y: 20, w: 100, h: 16)],
            orientation: .horizontal
        )
        // 60px gap >> 1.2 × 16px line height → new block.
        let lineB = TextLine(
            observations: [Fixtures.obs("段落二", x: 0, y: 96, w: 100, h: 16)],
            orientation: .horizontal
        )
        let blocks = BlockClusterer().cluster([lineB, lineA2, lineA1], orientation: .horizontal)
        XCTAssertEqual(blocks.count, 2)
        let sorted = blocks.sorted { $0.boundingBox.minY < $1.boundingBox.minY }
        XCTAssertEqual(sorted[0].text, "段落一の一\n段落一の二")
        XCTAssertEqual(sorted[1].text, "段落二")
    }

    func testSideBySideColumnsStaySeparate() {
        let left = TextLine(
            observations: [Fixtures.obs("左", x: 0, y: 0, w: 100, h: 16)],
            orientation: .horizontal
        )
        let right = TextLine(
            observations: [Fixtures.obs("右", x: 140, y: 0, w: 100, h: 16)],
            orientation: .horizontal
        )
        let blocks = BlockClusterer().cluster([left, right], orientation: .horizontal)
        XCTAssertEqual(blocks.count, 2)
    }

    func testVerticalBlockOrdersLinesRightToLeft() {
        let lines = Fixtures.tategakiColumns.map {
            TextLine(observations: [$0], orientation: .vertical)
        }
        let blocks = BlockClusterer().cluster(lines, orientation: .vertical)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].lines.map(\.text), Fixtures.tategakiExpectedOrder)
    }
}

final class ReadingOrderSorterTests: XCTestCase {

    func testHorizontalTitleThenColumns() {
        let title = BoundingBox(x: 50, y: 20, width: 300, height: 24)
        let left = BoundingBox(x: 50, y: 70, width: 140, height: 200)
        let right = BoundingBox(x: 210, y: 70, width: 140, height: 200)
        let order = ReadingOrderSorter().orderedIndices(
            of: [right, left, title],
            orientation: .horizontal
        )
        XCTAssertEqual(order, [2, 1, 0])
    }

    func testVerticalColumnsReadRightToLeft() {
        let boxes = Fixtures.tategakiColumns.map(\.boundingBox)
        let order = ReadingOrderSorter().orderedIndices(of: boxes, orientation: .vertical)
        // Fixture stores columns left → right; reading order is the reverse.
        XCTAssertEqual(order, [3, 2, 1, 0])
    }

    func testVerticalSectionsTopFirstThenRightToLeft() {
        let boxes = Fixtures.tategakiTwoSections.map(\.boundingBox)
        let ordered = ReadingOrderSorter()
            .sorted(Fixtures.tategakiTwoSections, boxes: \.boundingBox, orientation: .vertical)
        XCTAssertEqual(boxes.count, 4)
        XCTAssertEqual(ordered.map(\.text), ["上段右", "上段左", "下段右", "下段左"])
    }

    func testFallbackWithoutGapsIsPositional() {
        // Overlapping boxes: no projection gap on either axis.
        let a = BoundingBox(x: 0, y: 0, width: 100, height: 100)
        let b = BoundingBox(x: 50, y: 50, width: 100, height: 100)
        let order = ReadingOrderSorter().orderedIndices(of: [b, a], orientation: .horizontal)
        XCTAssertEqual(order, [1, 0])
    }
}

final class LayoutAnalyzerTests: XCTestCase {

    func testTategakiEndToEnd() {
        let layout = LayoutAnalyzer().analyze(Fixtures.tategakiColumns)
        XCTAssertEqual(layout.orientation, .vertical)
        XCTAssertEqual(layout.lines.map(\.text), Fixtures.tategakiExpectedOrder)
        XCTAssertEqual(
            layout.text,
            "吾輩は猫である\n名前はまだ無い\nどこで生れたか\nとんと見当がつかぬ"
        )
    }

    func testTategakiTitleColumnReadFirst() {
        let layout = LayoutAnalyzer().analyze(Fixtures.tategakiTitleAndBody)
        XCTAssertEqual(layout.orientation, .vertical)
        XCTAssertEqual(
            layout.lines.map(\.text),
            ["題名", "本文一列目", "本文二列目", "本文三列目"]
        )
    }

    /// Full tategaki page from *fragment*-level observations: columns must
    /// first be re-assembled from jittered fragments, the heading block set
    /// off by its gutter must come first, and body columns read right → left.
    func testTategakiNovelPageFromFragments() {
        let layout = LayoutAnalyzer().analyze(Fixtures.tategakiNovelPage)
        XCTAssertEqual(layout.orientation, .vertical)
        XCTAssertEqual(layout.lines.map(\.text), Fixtures.tategakiNovelPageExpectedOrder)
        // The heading is its own block, read before the six-column body.
        XCTAssertEqual(layout.blocks.count, 2)
        XCTAssertEqual(layout.blocks[0].text, "第一章")
        XCTAssertEqual(layout.blocks[1].lines.count, 6)
    }

    func testHorizontalTwoColumnPage() {
        let layout = LayoutAnalyzer().analyze(Fixtures.horizontalTwoColumns)
        XCTAssertEqual(layout.orientation, .horizontal)
        XCTAssertEqual(
            layout.lines.map(\.text),
            ["見出しのテキスト", "左段落一行目", "左段落二行目", "右段落一行目", "右段落二行目"]
        )
    }

    func testOrientationOverride() {
        let layout = LayoutAnalyzer(options: LayoutOptions(orientation: .horizontal))
            .analyze(Fixtures.tategakiColumns)
        XCTAssertEqual(layout.orientation, .horizontal)
    }

    func testLowConfidenceObservationsAreDropped() {
        var noisy = Fixtures.tategakiColumns
        noisy.append(
            TextObservation(
                text: "ノイズ",
                boundingBox: BoundingBox(x: 100, y: 500, width: 60, height: 16),
                confidence: 0.1
            )
        )
        let layout = LayoutAnalyzer(options: LayoutOptions(minConfidence: 0.5)).analyze(noisy)
        XCTAssertEqual(layout.lines.map(\.text), Fixtures.tategakiExpectedOrder)
    }

    func testEmptyInput() {
        let layout = LayoutAnalyzer().analyze([])
        XCTAssertTrue(layout.blocks.isEmpty)
        XCTAssertEqual(layout.text, "")
    }
}
