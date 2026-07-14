/// Parses Japanese numerals written with kanji, including mixed
/// kanji/Arabic forms that are common on receipts and invoices.
///
/// Supported forms:
/// * Positional digit kanji: `二〇二六` → 2026
/// * Unit-based numerals: `一万二千三百四十五` → 12345, `百五` → 105
/// * Mixed Arabic + myriad units: `1万2000` → 12000, `3千` → 3000
/// * `元` is not handled here (era-specific; see ``WarekiConverter``).
public enum KanjiNumberParser {

    static let digits: [Character: Int] = [
        "〇": 0, "零": 0, "一": 1, "二": 2, "三": 3, "四": 4,
        "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
        "0": 0, "1": 1, "2": 2, "3": 3, "4": 4,
        "5": 5, "6": 6, "7": 7, "8": 8, "9": 9,
    ]

    /// Small multipliers that combine within a myriad section.
    static let smallUnits: [Character: Int] = ["十": 10, "百": 100, "千": 1000]

    /// Myriad multipliers that close a section.
    static let largeUnits: [Character: Int] = ["万": 10_000, "億": 100_000_000, "兆": 1_000_000_000_000]

    /// Parses a numeral string. Returns `nil` when the string is empty or
    /// contains any character that is not part of a Japanese numeral.
    public static func parse(_ text: String) -> Int? {
        let characters = Array(text)
        guard !characters.isEmpty else { return nil }

        // Pure digit sequences (kanji or Arabic) are positional: 二〇二六 → 2026.
        if characters.allSatisfy({ digits[$0] != nil }) {
            var value = 0
            for character in characters {
                value = value * 10 + digits[character]!
            }
            return value
        }

        var total = 0        // Completed myriad sections.
        var section = 0      // Current section below 万.
        var current = 0      // Digits accumulated since the last unit.
        var sawAnything = false

        for character in characters {
            if let digit = digits[character] {
                current = current * 10 + digit
                sawAnything = true
            } else if let unit = smallUnits[character] {
                // A bare unit means 1 of it: 十 → 10.
                section += (current == 0 ? 1 : current) * unit
                current = 0
                sawAnything = true
            } else if let unit = largeUnits[character] {
                section += current
                // A bare large unit also means 1 of it: 万 → 10000.
                total += (section == 0 ? 1 : section) * unit
                section = 0
                current = 0
                sawAnything = true
            } else {
                return nil
            }
        }

        guard sawAnything else { return nil }
        return total + section + current
    }
}
