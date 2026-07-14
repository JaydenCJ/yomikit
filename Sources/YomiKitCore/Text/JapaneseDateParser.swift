/// A calendar date without a time zone, used for normalized output.
public struct YMDDate: Sendable, Hashable, Codable, Comparable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// ISO 8601 `yyyy-MM-dd`.
    public var isoString: String {
        func pad(_ value: Int, to width: Int) -> String {
            let string = String(value)
            return String(repeating: "0", count: max(0, width - string.count)) + string
        }
        return "\(pad(year, to: 4))-\(pad(month, to: 2))-\(pad(day, to: 2))"
    }

    /// Whether the combination is a real calendar date (Gregorian).
    public var isValid: Bool {
        guard (1...12).contains(month), day >= 1 else { return false }
        return day <= YMDDate.daysInMonth(month: month, year: year)
    }

    static func daysInMonth(month: Int, year: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2:
            let isLeap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return isLeap ? 29 : 28
        default: return 0
        }
    }

    public static func < (lhs: YMDDate, rhs: YMDDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// Converts Japanese era (wareki) years to Gregorian years.
public enum WarekiConverter {

    /// Era name/abbreviation → Gregorian year of the era's year 0
    /// (era year N corresponds to `offset + N`).
    static let eras: [(names: [String], offset: Int)] = [
        (["令和", "㋿", "R"], 2018),
        (["平成", "㍻", "H"], 1988),
        (["昭和", "㍼", "S"], 1925),
        (["大正", "㍽", "T"], 1911),
        (["明治", "㍾", "M"], 1867),
    ]

    /// Returns the Gregorian year for an era name and era year.
    /// `gregorianYear(era: "令和", year: 8)` → `2026`. Era year must be ≥ 1
    /// (use 1 for 元年).
    public static func gregorianYear(era: String, year: Int) -> Int? {
        guard year >= 1 else { return nil }
        for (names, offset) in eras where names.contains(era) {
            return offset + year
        }
        return nil
    }
}

/// Extracts and normalizes dates written in the formats commonly found on
/// Japanese receipts and documents.
public enum JapaneseDateParser {

    /// Finds the first date in `text` and returns it normalized.
    ///
    /// Recognized forms (full-width characters are normalized first):
    /// * `2026年7月8日`, `2026/07/08`, `2026-07-08`, `2026.7.8`
    /// * Era forms: `令和8年7月8日`, `令和元年5月1日`, `R8.7.8`, `H30/1/5`
    /// * Two-digit years: `26/07/08` (interpreted as 2000-relative)
    public static func parse(_ text: String) -> YMDDate? {
        let normalized = JapaneseTextNormalizer.normalize(text)

        // Era-based dates take priority: their trailing part (8.7.8) would
        // otherwise be misread by the two-digit-year pattern.
        if let match = normalized.firstMatch(
            of: /(令和|平成|昭和|大正|明治|㋿|㍻|㍼|㍽|㍾|[RHSTM])\s*(\d{1,2}|元)\s*[年.\-\/]\s*(\d{1,2})\s*[月.\-\/]\s*(\d{1,2})\s*日?/
        ) {
            let eraYear = match.2 == "元" ? 1 : Int(match.2)
            if let eraYear,
                let year = WarekiConverter.gregorianYear(era: String(match.1), year: eraYear),
                let month = Int(match.3),
                let day = Int(match.4)
            {
                let date = YMDDate(year: year, month: month, day: day)
                if date.isValid { return date }
            }
        }

        // Four-digit Gregorian year.
        if let match = normalized.firstMatch(
            of: /(\d{4})\s*[年\/\-.]\s*(\d{1,2})\s*[月\/\-.]\s*(\d{1,2})\s*日?/
        ) {
            if let year = Int(match.1), let month = Int(match.2), let day = Int(match.3) {
                let date = YMDDate(year: year, month: month, day: day)
                if date.isValid { return date }
            }
        }

        // Two-digit year (receipt style): 26/07/08. Avoid matching inside
        // longer digit runs via boundary checks in the pattern.
        if let match = normalized.firstMatch(
            of: /(?:^|[^\d])(\d{2})[\/.](\d{1,2})[\/.](\d{1,2})(?:[^\d]|$)/
        ) {
            if let yy = Int(match.1), let month = Int(match.2), let day = Int(match.3) {
                let date = YMDDate(year: 2000 + yy, month: month, day: day)
                if date.isValid { return date }
            }
        }

        return nil
    }

    /// Finds the first `HH:MM` time in `text`; returns `nil` when absent
    /// or out of range.
    public static func parseTime(_ text: String) -> (hour: Int, minute: Int)? {
        let normalized = JapaneseTextNormalizer.normalize(text)
        guard let match = normalized.firstMatch(of: /(\d{1,2}):(\d{2})/) else { return nil }
        guard let hour = Int(match.1), let minute = Int(match.2),
            (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        return (hour, minute)
    }
}
