/// Character-width and whitespace normalization for Japanese OCR output.
///
/// OCR engines frequently mix full-width ASCII (`１２３ＡＢＣ`) with
/// half-width katakana (`ｶﾀｶﾅ`) on receipts and business documents. Field
/// extraction becomes much simpler after normalizing to the conventional
/// forms: half-width ASCII and full-width kana.
public enum JapaneseTextNormalizer {

    public struct Options: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// Convert full-width ASCII (U+FF01…U+FF5E) and the ideographic
        /// space (U+3000) to their half-width counterparts.
        public static let asciiToHalfwidth = Options(rawValue: 1 << 0)
        /// Convert half-width katakana (U+FF61…U+FF9F) to full-width,
        /// composing voiced/semi-voiced marks (`ｶﾞ` → `ガ`).
        public static let kanaToFullwidth = Options(rawValue: 1 << 1)
        /// Collapse runs of spaces/tabs into a single space and trim ends.
        public static let collapseWhitespace = Options(rawValue: 1 << 2)

        public static let `default`: Options = [.asciiToHalfwidth, .kanaToFullwidth]
        public static let all: Options = [.asciiToHalfwidth, .kanaToFullwidth, .collapseWhitespace]
    }

    /// Applies the selected normalizations in a fixed, safe order.
    public static func normalize(_ text: String, options: Options = .default) -> String {
        var result = text
        if options.contains(.kanaToFullwidth) {
            result = fullwidthKana(from: result)
        }
        if options.contains(.asciiToHalfwidth) {
            result = halfwidthASCII(from: result)
        }
        if options.contains(.collapseWhitespace) {
            result = collapseWhitespace(in: result)
        }
        return result
    }

    /// Converts full-width ASCII letters, digits and punctuation to
    /// half-width; the ideographic space becomes a regular space.
    public static func halfwidthASCII(from text: String) -> String {
        String(
            text.map { character -> Character in
                guard let scalar = character.unicodeScalars.first,
                    character.unicodeScalars.count == 1
                else { return character }
                switch scalar.value {
                case 0xFF01...0xFF5E:
                    // Full-width form block is a fixed offset from ASCII.
                    return Character(UnicodeScalar(scalar.value - 0xFEE0)!)
                case 0x3000:
                    return " "
                default:
                    return character
                }
            }
        )
    }

    /// Converts half-width katakana to full-width katakana, composing
    /// voiced (`ﾞ`) and semi-voiced (`ﾟ`) sound marks with the preceding
    /// kana where a precomposed form exists.
    ///
    /// Iterates Unicode scalars, not `Character`s: the half-width sound
    /// marks (U+FF9E/U+FF9F) are grapheme-extending, so `ｷﾞ` is a single
    /// grapheme cluster and a per-`Character` loop would never see the
    /// mark on its own.
    public static func fullwidthKana(from text: String) -> String {
        var output: [Character] = []
        output.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars {
            let character = Character(scalar)
            switch character {
            case "ﾞ":
                if let last = output.last, let voiced = voicedMap[last] {
                    output[output.count - 1] = voiced
                } else {
                    output.append("゛")
                }
            case "ﾟ":
                if let last = output.last, let semiVoiced = semiVoicedMap[last] {
                    output[output.count - 1] = semiVoiced
                } else {
                    output.append("゜")
                }
            default:
                output.append(kanaMap[character] ?? character)
            }
        }
        return String(output)
    }

    /// Collapses runs of spaces and tabs to one space and trims each line.
    public static func collapseWhitespace(in text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.map { line in
            line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "　" })
                .joined(separator: " ")
        }
        .joined(separator: "\n")
    }

    // MARK: - Tables

    /// Half-width katakana and punctuation → full-width.
    static let kanaMap: [Character: Character] = [
        "｡": "。", "｢": "「", "｣": "」", "､": "、", "･": "・",
        "ｦ": "ヲ", "ｧ": "ァ", "ｨ": "ィ", "ｩ": "ゥ", "ｪ": "ェ", "ｫ": "ォ",
        "ｬ": "ャ", "ｭ": "ュ", "ｮ": "ョ", "ｯ": "ッ", "ｰ": "ー",
        "ｱ": "ア", "ｲ": "イ", "ｳ": "ウ", "ｴ": "エ", "ｵ": "オ",
        "ｶ": "カ", "ｷ": "キ", "ｸ": "ク", "ｹ": "ケ", "ｺ": "コ",
        "ｻ": "サ", "ｼ": "シ", "ｽ": "ス", "ｾ": "セ", "ｿ": "ソ",
        "ﾀ": "タ", "ﾁ": "チ", "ﾂ": "ツ", "ﾃ": "テ", "ﾄ": "ト",
        "ﾅ": "ナ", "ﾆ": "ニ", "ﾇ": "ヌ", "ﾈ": "ネ", "ﾉ": "ノ",
        "ﾊ": "ハ", "ﾋ": "ヒ", "ﾌ": "フ", "ﾍ": "ヘ", "ﾎ": "ホ",
        "ﾏ": "マ", "ﾐ": "ミ", "ﾑ": "ム", "ﾒ": "メ", "ﾓ": "モ",
        "ﾔ": "ヤ", "ﾕ": "ユ", "ﾖ": "ヨ",
        "ﾗ": "ラ", "ﾘ": "リ", "ﾙ": "ル", "ﾚ": "レ", "ﾛ": "ロ",
        "ﾜ": "ワ", "ﾝ": "ン",
    ]

    /// Base kana → voiced (dakuten) form.
    static let voicedMap: [Character: Character] = [
        "カ": "ガ", "キ": "ギ", "ク": "グ", "ケ": "ゲ", "コ": "ゴ",
        "サ": "ザ", "シ": "ジ", "ス": "ズ", "セ": "ゼ", "ソ": "ゾ",
        "タ": "ダ", "チ": "ヂ", "ツ": "ヅ", "テ": "デ", "ト": "ド",
        "ハ": "バ", "ヒ": "ビ", "フ": "ブ", "ヘ": "ベ", "ホ": "ボ",
        "ウ": "ヴ",
    ]

    /// Base kana → semi-voiced (handakuten) form.
    static let semiVoicedMap: [Character: Character] = [
        "ハ": "パ", "ヒ": "ピ", "フ": "プ", "ヘ": "ペ", "ホ": "ポ",
    ]
}
