/// Extracts monetary amounts (Japanese yen) from OCR text.
///
/// Handles `¥1,234`, `\1,234`, `1,234円`, full-width digits, negative
/// discounts written as `-123` or `▲123`, and thousands separators.
public enum AmountParser {

    /// A monetary amount found in text.
    public struct Match: Sendable, Hashable {
        /// Amount in yen. Negative for discounts.
        public var amount: Int
        /// Whether the amount carried an explicit currency marker
        /// (`¥` / `\` prefix or `円` suffix). Marked amounts are more
        /// trustworthy when a line contains several numbers.
        public var hasCurrencyMarker: Bool

        public init(amount: Int, hasCurrencyMarker: Bool) {
            self.amount = amount
            self.hasCurrencyMarker = hasCurrencyMarker
        }
    }

    /// All amounts in `text`, in order of appearance.
    public static func amounts(in text: String) -> [Match] {
        let normalized = JapaneseTextNormalizer.normalize(text)
        var results: [Match] = []

        let pattern = /([¥￥\\])?\s*([-−▲△])?\s*(\d{1,3}(?:,\d{3})+|\d+)\s*(円)?/
        for match in normalized.matches(of: pattern) {
            let digits = match.3.split(separator: ",").joined()
            guard let magnitude = Int(digits) else { continue }
            let isNegative = match.2 != nil
            let hasMarker = match.1 != nil || match.4 != nil
            results.append(
                Match(amount: isNegative ? -magnitude : magnitude, hasCurrencyMarker: hasMarker)
            )
        }
        return results
    }

    /// The most plausible single amount in `text`:
    /// prefers currency-marked amounts; among equals takes the last one,
    /// because on receipts the amount column is rightmost.
    public static func parse(_ text: String) -> Int? {
        let all = amounts(in: text)
        if let marked = all.last(where: { $0.hasCurrencyMarker }) {
            return marked.amount
        }
        return all.last?.amount
    }
}
