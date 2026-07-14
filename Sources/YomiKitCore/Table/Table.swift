/// One logical cell of a reconstructed table.
public struct TableCell: Sendable, Hashable, Codable {
    /// Zero-based row index of the cell's top-left anchor.
    public var row: Int
    /// Zero-based column index of the cell's top-left anchor.
    public var column: Int
    /// Number of rows this cell covers (≥ 1).
    public var rowSpan: Int
    /// Number of columns this cell covers (≥ 1).
    public var columnSpan: Int
    /// Concatenated text of all fragments assigned to the cell.
    public var text: String
    /// Union of the member fragments' boxes.
    public var boundingBox: BoundingBox

    public init(
        row: Int,
        column: Int,
        rowSpan: Int = 1,
        columnSpan: Int = 1,
        text: String,
        boundingBox: BoundingBox
    ) {
        self.row = row
        self.column = column
        self.rowSpan = rowSpan
        self.columnSpan = columnSpan
        self.text = text
        self.boundingBox = boundingBox
    }
}

/// A structured table reconstructed from OCR fragments.
public struct Table: Sendable, Hashable, Codable {
    public var rowCount: Int
    public var columnCount: Int
    /// Cells sorted by (row, column). Positions covered by a span have no
    /// cell of their own.
    public var cells: [TableCell]

    public init(rowCount: Int, columnCount: Int, cells: [TableCell]) {
        self.rowCount = rowCount
        self.columnCount = columnCount
        self.cells = cells.sorted { ($0.row, $0.column) < ($1.row, $1.column) }
    }

    /// The cell anchored at the given position, if any.
    public func cell(atRow row: Int, column: Int) -> TableCell? {
        cells.first { $0.row == row && $0.column == column }
    }

    /// The cell covering the given position, taking spans into account.
    public func cell(covering row: Int, column: Int) -> TableCell? {
        cells.first {
            row >= $0.row && row < $0.row + $0.rowSpan
                && column >= $0.column && column < $0.column + $0.columnSpan
        }
    }

    /// The table as a dense text grid. Anchor positions carry the cell text;
    /// positions covered by a span (or with no cell) are empty strings.
    public var grid: [[String]] {
        var grid = Array(
            repeating: [String](repeating: "", count: columnCount),
            count: rowCount
        )
        for cell in cells where cell.row < rowCount && cell.column < columnCount {
            grid[cell.row][cell.column] = cell.text
        }
        return grid
    }
}
