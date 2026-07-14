/// Renders analyzed documents, tables and receipts as Markdown.
public enum MarkdownRenderer {

    /// Renders a document layout as Markdown paragraphs in reading order.
    public static func render(_ layout: DocumentLayout) -> String {
        layout.blocks
            .map { block in block.lines.map(\.text).joined(separator: "\n") }
            .joined(separator: "\n\n")
    }

    /// Renders a table as a GitHub-flavored Markdown pipe table. The first
    /// row is used as the header row. Cells spanning several columns are
    /// written into their anchor position (Markdown has no native spans).
    public static func render(_ table: Table) -> String {
        guard table.rowCount > 0, table.columnCount > 0 else { return "" }
        let grid = table.grid

        func renderRow(_ row: [String]) -> String {
            "| " + row.map(escapeCell).joined(separator: " | ") + " |"
        }

        var lines: [String] = []
        lines.append(renderRow(grid[0]))
        lines.append("| " + Array(repeating: "---", count: table.columnCount).joined(separator: " | ") + " |")
        for row in grid.dropFirst() {
            lines.append(renderRow(row))
        }
        return lines.joined(separator: "\n")
    }

    /// Renders a receipt as a compact Markdown summary.
    public static func render(_ receipt: Receipt) -> String {
        var lines: [String] = []
        if let storeName = receipt.storeName {
            lines.append("# \(storeName)")
            lines.append("")
        }
        var meta: [String] = []
        if let date = receipt.date { meta.append(date.isoString) }
        if let time = receipt.time { meta.append(time) }
        if !meta.isEmpty {
            lines.append(meta.joined(separator: " "))
            lines.append("")
        }
        if !receipt.items.isEmpty {
            lines.append("| Item | Qty | Price |")
            lines.append("| --- | --- | --- |")
            for item in receipt.items {
                let quantity = item.quantity.map(String.init) ?? ""
                lines.append("| \(escapeCell(item.name)) | \(quantity) | \(item.price) |")
            }
            lines.append("")
        }
        var summary: [String] = []
        if let subtotal = receipt.subtotal { summary.append("Subtotal: \(subtotal)") }
        if let total = receipt.total { summary.append("**Total: \(total)**") }
        for tax in receipt.taxLines {
            var parts: [String] = []
            if let rate = tax.rate {
                parts.append("\(rate)%\(tax.isReducedRate ? " (reduced)" : "")")
            }
            if let taxable = tax.taxableAmount { parts.append("taxable \(taxable)") }
            if let amount = tax.taxAmount { parts.append("tax \(amount)") }
            if !parts.isEmpty { summary.append("Tax: " + parts.joined(separator: ", ")) }
        }
        if let tendered = receipt.tendered { summary.append("Tendered: \(tendered)") }
        if let change = receipt.change { summary.append("Change: \(change)") }
        lines.append(contentsOf: summary)
        return lines.joined(separator: "\n").trimmingTrailingNewlines()
    }

    private static func escapeCell(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .joined(separator: "<br>")
            .replacing("|", with: "\\|")
    }
}

extension String {
    fileprivate func trimmingTrailingNewlines() -> String {
        var result = Substring(self)
        while result.last == "\n" {
            result = result.dropLast()
        }
        return String(result)
    }
}
