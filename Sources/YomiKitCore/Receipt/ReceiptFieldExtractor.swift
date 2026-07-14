/// Extracts structured fields from Japanese receipt text using keyword
/// heuristics and pattern matching over normalized lines.
///
/// The extractor is deliberately rule-based: receipts are a closed domain
/// where keyword conventions (合計 / 小計 / お預り / 8%対象 …) are stable
/// across chains, and rules stay fully on-device and auditable.
public struct ReceiptFieldExtractor: Sendable {

    public init() {}

    // MARK: - Entry points

    /// Extracts receipt fields from raw OCR observations. Uses receipt-tuned
    /// layout analysis (single column, unlimited in-line gaps) and prefers
    /// the tallest line near the top as the store name, since store names
    /// are usually printed in a larger font.
    public func extract(from observations: [TextObservation]) -> Receipt {
        let layout = LayoutAnalyzer(options: .receipt).analyze(observations)
        let lines = layout.lines
        let texts = lines.map { normalize($0.spacedText) }

        // Tallest line among the leading lines is the store-name candidate.
        var storeHint: Int?
        let head = min(5, lines.count)
        if head > 0 {
            let tallest = (0..<head).max {
                lines[$0].boundingBox.height < lines[$1].boundingBox.height
            }
            if let tallest, isPlausibleStoreName(texts[tallest]) {
                storeHint = tallest
            }
        }
        return extract(lines: texts, storeNameHint: storeHint)
    }

    /// Extracts receipt fields from pre-ordered text lines.
    public func extract(fromLines lines: [String]) -> Receipt {
        extract(lines: lines.map(normalize), storeNameHint: nil)
    }

    // MARK: - Core extraction

    private func extract(lines: [String], storeNameHint: Int?) -> Receipt {
        var receipt = Receipt(rawLines: lines)

        enum AmountTarget {
            case total, subtotal, tendered, change
        }
        var pendingTarget: AmountTarget?
        var partialTaxLines: [ReceiptTaxLine] = []
        var itemRegionEnded = false

        for (index, rawLine) in lines.enumerated() {
            let line = rawLine
            guard !line.isEmpty else { continue }

            // Date and time can appear anywhere; first hit wins.
            if receipt.date == nil, let date = JapaneseDateParser.parse(line) {
                receipt.date = date
            }
            if receipt.time == nil, let time = JapaneseDateParser.parseTime(line) {
                receipt.time = String(format2: time.hour) + ":" + String(format2: time.minute)
            }

            // A keyword line whose amount is printed on the following line.
            if let target = pendingTarget {
                if let amount = standaloneAmount(in: line) {
                    switch target {
                    case .total: receipt.total = amount
                    case .subtotal: receipt.subtotal = amount
                    case .tendered: receipt.tendered = amount
                    case .change: receipt.change = amount
                    }
                    pendingTarget = nil
                    continue
                }
                pendingTarget = nil
            }

            // Order matters: お預り合計 must hit "tendered", not "total".
            if line.contains("預") && (line.contains("お預") || line.contains("預り") || line.contains("預かり")) {
                if let amount = AmountParser.parse(stripRates(from: line)) {
                    receipt.tendered = amount
                } else {
                    pendingTarget = .tendered
                }
                itemRegionEnded = true
                continue
            }
            if line.contains("釣") || line.contains("おつり") {
                if let amount = AmountParser.parse(stripRates(from: line)) {
                    receipt.change = amount
                } else {
                    pendingTarget = .change
                }
                itemRegionEnded = true
                continue
            }
            if line.contains("小計") {
                if let amount = AmountParser.parse(stripRates(from: line)) {
                    receipt.subtotal = amount
                } else {
                    pendingTarget = .subtotal
                }
                itemRegionEnded = true
                continue
            }
            if isTaxLine(line) {
                partialTaxLines.append(parseTaxLine(line))
                itemRegionEnded = true
                continue
            }
            if line.contains("合計") || line.contains("総計") || line.contains("お会計")
                || line.contains("ご請求")
            {
                if let amount = AmountParser.parse(stripRates(from: line)) {
                    // The last total line wins (税込合計 reprints appear later).
                    receipt.total = amount
                } else {
                    pendingTarget = .total
                }
                itemRegionEnded = true
                continue
            }
            if line.contains("点数") {
                if let match = line.firstMatch(of: /(\d+)\s*点?/), let count = Int(match.1) {
                    receipt.declaredItemCount = count
                }
                continue
            }

            // Item lines: name + trailing amount, outside the summary region.
            // Lines carrying a date are header metadata, never items.
            if !itemRegionEnded, !isNoiseLine(line), index > 0 || lines.count == 1,
                JapaneseDateParser.parse(line) == nil
            {
                if let item = parseItem(from: line) {
                    receipt.items.append(item)
                }
            }
        }

        receipt.taxLines = Self.mergeTaxLines(partialTaxLines)
        receipt.storeName = pickStoreName(lines: lines, hint: storeNameHint)
        return receipt
    }

    // MARK: - Store name

    private func pickStoreName(lines: [String], hint: Int?) -> String? {
        if let hint, hint < lines.count, isPlausibleStoreName(lines[hint]) {
            return lines[hint]
        }
        // First plausible line before any summary keyword.
        for line in lines.prefix(6) {
            if line.contains("合計") || line.contains("小計") { break }
            if isPlausibleStoreName(line) {
                return line
            }
        }
        return nil
    }

    private func isPlausibleStoreName(_ line: String) -> Bool {
        guard !line.isEmpty else { return false }
        let stopwords = [
            "TEL", "Tel", "tel", "電話", "FAX", "〒", "領収", "レシート", "レジ",
            "ありがとう", "ございま", "いらっしゃい", "ようこそ", "またお越し",
            "担当", "責任者", "店番", "No.", "NO.", "#", "会員", "ポイント",
        ]
        if stopwords.contains(where: { line.contains($0) }) { return false }
        if JapaneseDateParser.parse(line) != nil { return false }
        if JapaneseDateParser.parseTime(line) != nil { return false }
        // A line that is mostly an amount is not a name.
        if standaloneAmount(in: line) != nil { return false }
        return true
    }

    // MARK: - Tax lines

    private func isTaxLine(_ line: String) -> Bool {
        if line.contains("対象"), line.contains(/\d{1,2}\s*%/) { return true }
        return line.contains("消費税") || line.contains("内税") || line.contains("外税")
    }

    private func parseTaxLine(_ line: String) -> ReceiptTaxLine {
        var rate: Int?
        if let match = line.firstMatch(of: /(\d{1,2})\s*%/) {
            rate = Int(match.1)
        }
        let isReduced = line.contains("軽減") || line.contains("※")

        let amounts = AmountParser.amounts(in: stripRates(from: line)).map(\.amount)
        var taxable: Int?
        var tax: Int?
        let mentionsTaxable = line.contains("対象")
        let mentionsTax = line.contains("税")
        if mentionsTaxable && mentionsTax && amounts.count >= 2 {
            // e.g. 8%対象 ¥1,080 (内税 ¥80)
            taxable = amounts.first
            tax = amounts.last
        } else if mentionsTaxable {
            taxable = amounts.last
        } else {
            tax = amounts.last
        }
        return ReceiptTaxLine(rate: rate, isReducedRate: isReduced, taxableAmount: taxable, taxAmount: tax)
    }

    /// Merges partial tax lines that refer to the same rate
    /// (e.g. `8%対象 ¥1,080` and a later `内消費税等(8%) ¥80`).
    static func mergeTaxLines(_ lines: [ReceiptTaxLine]) -> [ReceiptTaxLine] {
        var merged: [ReceiptTaxLine] = []
        for line in lines {
            if let index = merged.firstIndex(where: { $0.rate == line.rate }) {
                merged[index].isReducedRate = merged[index].isReducedRate || line.isReducedRate
                merged[index].taxableAmount = merged[index].taxableAmount ?? line.taxableAmount
                merged[index].taxAmount = merged[index].taxAmount ?? line.taxAmount
            } else {
                merged.append(line)
            }
        }
        return merged
    }

    // MARK: - Items

    private func parseItem(from line: String) -> ReceiptItem? {
        var working = line

        // Quantity: ×2 / x2 / 2個 / 2点
        var quantity: Int?
        if let match = working.firstMatch(of: /[x×]\s*(\d+)/) {
            quantity = Int(match.1)
            working.removeSubrange(match.range)
        } else if let match = working.firstMatch(of: /(\d+)\s*[個点]/) {
            quantity = Int(match.1)
            working.removeSubrange(match.range)
        }
        // Unit-price markers (@138) are informational; drop them.
        while let match = working.firstMatch(of: /@\s*\d{1,3}(?:,\d{3})*/) {
            working.removeSubrange(match.range)
        }

        let pattern = /([¥￥\\])?\s*([-−▲△])?(\d{1,3}(?:,\d{3})+|\d+)\s*(円)?/
        guard let last = working.matches(of: pattern).last else { return nil }

        // The price must be the rightmost content on the line.
        let suffix = working[last.range.upperBound...]
        guard suffix.allSatisfy({ $0 == " " || $0 == "\t" }) else { return nil }

        let digits = last.3.split(separator: ",").joined()
        guard let magnitude = Int(digits) else { return nil }
        let hasMarker = last.1 != nil || last.4 != nil
        // Unmarked single-digit trailing numbers are usually address or
        // code fragments (…1-2-3), not prices.
        guard hasMarker || digits.count >= 2 else { return nil }
        let price = last.2 != nil ? -magnitude : magnitude

        var name = String(working[..<last.range.lowerBound])
        name = trimName(name)
        guard !name.isEmpty else { return nil }
        // Names that are nothing but digits/punctuation are noise (time
        // fragments, code prefixes), not products.
        guard name.contains(where: { !$0.isNumber }) else { return nil }
        // Sanity bound to reject phone-number fragments and similar noise.
        guard abs(price) <= 10_000_000 else { return nil }

        return ReceiptItem(name: name, price: price, quantity: quantity)
    }

    private func isNoiseLine(_ line: String) -> Bool {
        let stopwords = [
            "TEL", "Tel", "tel", "電話", "FAX", "〒", "レジ", "領収", "レシート",
            "ありがとう", "ございま", "いらっしゃい", "またお越し", "ポイント",
            "会員", "カード", "取引", "端末", "No.", "NO.",
        ]
        return stopwords.contains { line.contains($0) }
    }

    private func trimName(_ name: String) -> String {
        var trimmed = Substring(name)
        let junk: Set<Character> = [" ", "\t", "・", ":", "：", "*", "＊", "␣", "…", ".", "-"]
        while let last = trimmed.last, junk.contains(last) {
            trimmed = trimmed.dropLast()
        }
        while let first = trimmed.first, first == " " || first == "\t" || first == "*" || first == "＊" {
            trimmed = trimmed.dropFirst()
        }
        return String(trimmed)
    }

    // MARK: - Helpers

    private func normalize(_ line: String) -> String {
        JapaneseTextNormalizer.normalize(line, options: .all)
    }

    /// Strips rate tokens (8%, 10%) so they are not mistaken for amounts.
    private func stripRates(from line: String) -> String {
        line.replacing(/\d{1,2}\s*%/, with: "")
    }

    /// Returns the amount when the line is (almost) nothing but an amount.
    private func standaloneAmount(in line: String) -> Int? {
        let pattern = /^\s*([¥￥\\])?\s*([-−▲△])?(\d{1,3}(?:,\d{3})+|\d+)\s*(円)?\s*$/
        guard let match = line.firstMatch(of: pattern) else { return nil }
        let digits = match.3.split(separator: ",").joined()
        guard let magnitude = Int(digits) else { return nil }
        return match.2 != nil ? -magnitude : magnitude
    }
}

extension String {
    /// Zero-pads an integer to two digits ("7" → "07").
    fileprivate init(format2 value: Int) {
        self = value < 10 ? "0\(value)" : "\(value)"
    }
}
