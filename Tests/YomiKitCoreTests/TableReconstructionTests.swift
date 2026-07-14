import XCTest
@testable import YomiKitCore

final class TableReconstructionTests: XCTestCase {

    func testClean3x3GridWithJitter() {
        let table = TableReconstructor().reconstruct(Fixtures.table3x3)
        XCTAssertEqual(table.rowCount, 3)
        XCTAssertEqual(table.columnCount, 3)
        XCTAssertEqual(
            table.grid,
            [
                ["品名", "数量", "金額"],
                ["りんご", "3", "¥450"],
                ["みかん", "5", "¥600"],
            ]
        )
    }

    func testMissingCellLeavesEmptyPosition() {
        var observations = Fixtures.table3x3
        // Remove the quantity of the last row (row 2, column 1).
        observations.removeAll { $0.text == "5" }
        let table = TableReconstructor().reconstruct(observations)
        XCTAssertEqual(table.rowCount, 3)
        XCTAssertEqual(table.columnCount, 3)
        XCTAssertEqual(table.grid[2], ["みかん", "", "¥600"])
        XCTAssertNil(table.cell(atRow: 2, column: 1))
    }

    func testHeaderColumnSpanIsDetected() {
        let table = TableReconstructor().reconstruct(Fixtures.tableWithColumnSpan)
        XCTAssertEqual(table.rowCount, 3)
        XCTAssertEqual(table.columnCount, 3)

        let header = table.cell(atRow: 0, column: 1)
        XCTAssertEqual(header?.text, "売上高")
        XCTAssertEqual(header?.columnSpan, 2)
        XCTAssertEqual(header?.rowSpan, 1)

        // The spanning cell covers (0,2) even though no cell is anchored there.
        XCTAssertNil(table.cell(atRow: 0, column: 2))
        XCTAssertEqual(table.cell(covering: 0, column: 2)?.text, "売上高")

        XCTAssertEqual(table.grid[1], ["1月", "120", "140"])
        XCTAssertEqual(table.grid[2], ["2月", "150", "170"])
    }

    func testFragmentsWithinOneCellAreJoined() {
        var observations = Fixtures.table3x3
        // Split the header cell "金額" into two adjacent fragments.
        observations.removeAll { $0.text == "金額" }
        observations.append(Fixtures.obs("金", x: 240, y: 21, w: 20, h: 20))
        observations.append(Fixtures.obs("額", x: 264, y: 21, w: 20, h: 20))
        let table = TableReconstructor().reconstruct(observations)
        XCTAssertEqual(table.rowCount, 3)
        XCTAssertEqual(table.columnCount, 3)
        XCTAssertEqual(table.grid[0], ["品名", "数量", "金額"])
    }

    func testCellsAreSortedByRowThenColumn() {
        let table = TableReconstructor().reconstruct(Fixtures.table3x3)
        let positions = table.cells.map { [$0.row, $0.column] }
        XCTAssertEqual(positions, positions.sorted { ($0[0], $0[1]) < ($1[0], $1[1]) })
    }

    func testEmptyInputProducesEmptyTable() {
        let table = TableReconstructor().reconstruct([])
        XCTAssertEqual(table.rowCount, 0)
        XCTAssertEqual(table.columnCount, 0)
        XCTAssertTrue(table.cells.isEmpty)
    }
}
