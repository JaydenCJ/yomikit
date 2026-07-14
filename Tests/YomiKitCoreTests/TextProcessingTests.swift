import XCTest
@testable import YomiKitCore

final class JapaneseTextNormalizerTests: XCTestCase {

    func testFullwidthASCIIToHalfwidth() {
        XCTAssertEqual(
            JapaneseTextNormalizer.halfwidthASCII(from: "１２３ＡＢＣａｂｃ！？（）"),
            "123ABCabc!?()"
        )
        // Ideographic space becomes a plain space.
        XCTAssertEqual(JapaneseTextNormalizer.halfwidthASCII(from: "Ａ　Ｂ"), "A B")
        // Kana and kanji are untouched.
        XCTAssertEqual(JapaneseTextNormalizer.halfwidthASCII(from: "合計です"), "合計です")
    }

    func testHalfwidthKanaToFullwidth() {
        XCTAssertEqual(JapaneseTextNormalizer.fullwidthKana(from: "ｱｲｽｸﾘｰﾑ"), "アイスクリーム")
        // Voiced marks compose: ｷﾞ → ギ, ｻﾞ → ザ.
        XCTAssertEqual(JapaneseTextNormalizer.fullwidthKana(from: "ｷﾞｮｳｻﾞ"), "ギョウザ")
        // Semi-voiced marks compose: ﾊﾟ → パ.
        XCTAssertEqual(JapaneseTextNormalizer.fullwidthKana(from: "ﾊﾟﾝ"), "パン")
        // ｳ + ﾞ → ヴ.
        XCTAssertEqual(JapaneseTextNormalizer.fullwidthKana(from: "ｳﾞｧｲｵﾘﾝ"), "ヴァイオリン")
        // Half-width punctuation.
        XCTAssertEqual(JapaneseTextNormalizer.fullwidthKana(from: "｢ﾃｽﾄ｣､ﾃﾝ｡"), "「テスト」、テン。")
        // A dangling voiced mark stays as a standalone mark.
        XCTAssertEqual(JapaneseTextNormalizer.fullwidthKana(from: "ﾞ"), "゛")
    }

    func testCollapseWhitespace() {
        XCTAssertEqual(
            JapaneseTextNormalizer.collapseWhitespace(in: "a  b\t c　d"),
            "a b c d"
        )
        XCTAssertEqual(
            JapaneseTextNormalizer.collapseWhitespace(in: "one\ntwo  three"),
            "one\ntwo three"
        )
    }

    func testCombinedNormalization() {
        XCTAssertEqual(
            JapaneseTextNormalizer.normalize("ﾎﾟｲﾝﾄ　１００Ｐ", options: .all),
            "ポイント 100P"
        )
    }
}

final class KanjiNumberParserTests: XCTestCase {

    func testPositionalDigits() {
        XCTAssertEqual(KanjiNumberParser.parse("二〇二六"), 2026)
        XCTAssertEqual(KanjiNumberParser.parse("〇"), 0)
        XCTAssertEqual(KanjiNumberParser.parse("五"), 5)
    }

    func testUnitNumerals() {
        XCTAssertEqual(KanjiNumberParser.parse("十"), 10)
        XCTAssertEqual(KanjiNumberParser.parse("百五"), 105)
        XCTAssertEqual(KanjiNumberParser.parse("三百四十二"), 342)
        XCTAssertEqual(KanjiNumberParser.parse("一万二千三百四十五"), 12345)
        XCTAssertEqual(KanjiNumberParser.parse("五億"), 500_000_000)
        XCTAssertEqual(KanjiNumberParser.parse("千二百万"), 12_000_000)
    }

    func testMixedArabicAndKanji() {
        XCTAssertEqual(KanjiNumberParser.parse("3千"), 3000)
        XCTAssertEqual(KanjiNumberParser.parse("1万2000"), 12000)
    }

    func testInvalidInput() {
        XCTAssertNil(KanjiNumberParser.parse(""))
        XCTAssertNil(KanjiNumberParser.parse("abc"))
        XCTAssertNil(KanjiNumberParser.parse("百円"))
    }
}

final class JapaneseDateParserTests: XCTestCase {

    func testWesternFormats() {
        XCTAssertEqual(JapaneseDateParser.parse("2026年7月8日"), YMDDate(year: 2026, month: 7, day: 8))
        XCTAssertEqual(JapaneseDateParser.parse("2026/07/08"), YMDDate(year: 2026, month: 7, day: 8))
        XCTAssertEqual(JapaneseDateParser.parse("2026-7-8"), YMDDate(year: 2026, month: 7, day: 8))
        XCTAssertEqual(JapaneseDateParser.parse("2026.07.08"), YMDDate(year: 2026, month: 7, day: 8))
    }

    func testEraFormats() {
        XCTAssertEqual(JapaneseDateParser.parse("令和8年7月8日"), YMDDate(year: 2026, month: 7, day: 8))
        XCTAssertEqual(JapaneseDateParser.parse("令和元年5月1日"), YMDDate(year: 2019, month: 5, day: 1))
        XCTAssertEqual(JapaneseDateParser.parse("平成30年1月5日"), YMDDate(year: 2018, month: 1, day: 5))
        XCTAssertEqual(JapaneseDateParser.parse("R8.7.8"), YMDDate(year: 2026, month: 7, day: 8))
        XCTAssertEqual(JapaneseDateParser.parse("H30/1/5"), YMDDate(year: 2018, month: 1, day: 5))
    }

    func testTwoDigitYear() {
        XCTAssertEqual(JapaneseDateParser.parse("26/07/08"), YMDDate(year: 2026, month: 7, day: 8))
    }

    func testFullwidthInput() {
        XCTAssertEqual(
            JapaneseDateParser.parse("２０２６年７月８日"),
            YMDDate(year: 2026, month: 7, day: 8)
        )
    }

    func testEmbeddedInLine() {
        XCTAssertEqual(
            JapaneseDateParser.parse("お買上日: 2026年7月8日(火) 18:42"),
            YMDDate(year: 2026, month: 7, day: 8)
        )
    }

    func testInvalidDatesRejected() {
        XCTAssertNil(JapaneseDateParser.parse("2026年13月40日"))
        XCTAssertNil(JapaneseDateParser.parse("2026/02/30"))
        XCTAssertNil(JapaneseDateParser.parse("date-free text"))
    }

    func testLeapYearValidation() {
        XCTAssertEqual(JapaneseDateParser.parse("2024/02/29"), YMDDate(year: 2024, month: 2, day: 29))
        XCTAssertNil(JapaneseDateParser.parse("2026/02/29"))
    }

    func testIsoStringPadding() {
        XCTAssertEqual(YMDDate(year: 2026, month: 7, day: 8).isoString, "2026-07-08")
        XCTAssertEqual(YMDDate(year: 800, month: 12, day: 31).isoString, "0800-12-31")
    }

    func testWarekiConverter() {
        XCTAssertEqual(WarekiConverter.gregorianYear(era: "令和", year: 8), 2026)
        XCTAssertEqual(WarekiConverter.gregorianYear(era: "昭和", year: 64), 1989)
        XCTAssertEqual(WarekiConverter.gregorianYear(era: "明治", year: 1), 1868)
        XCTAssertNil(WarekiConverter.gregorianYear(era: "架空", year: 3))
        XCTAssertNil(WarekiConverter.gregorianYear(era: "令和", year: 0))
    }

    func testParseTime() {
        XCTAssertEqual(JapaneseDateParser.parseTime("18:42")?.hour, 18)
        XCTAssertEqual(JapaneseDateParser.parseTime("18:42")?.minute, 42)
        XCTAssertEqual(JapaneseDateParser.parseTime("9:05")?.hour, 9)
        XCTAssertNil(JapaneseDateParser.parseTime("25:00"))
        XCTAssertNil(JapaneseDateParser.parseTime("no time"))
    }
}

final class AmountParserTests: XCTestCase {

    func testMarkedAmounts() {
        XCTAssertEqual(AmountParser.parse("¥1,234"), 1234)
        XCTAssertEqual(AmountParser.parse("1,234円"), 1234)
        XCTAssertEqual(AmountParser.parse("\\980"), 980)
        XCTAssertEqual(AmountParser.parse("￥５００"), 500)
    }

    func testNegativeAmounts() {
        XCTAssertEqual(AmountParser.parse("-500"), -500)
        XCTAssertEqual(AmountParser.parse("▲500"), -500)
        XCTAssertEqual(AmountParser.parse("値引 -1,000円"), -1000)
    }

    func testPrefersMarkedAmountOnMixedLine() {
        // "500ml" is a bare number; the marked ¥216 must win.
        XCTAssertEqual(AmountParser.parse("お茶 500ml ¥216"), 216)
    }

    func testTakesLastAmountWhenNoneMarked() {
        XCTAssertEqual(AmountParser.parse("コード 12 金額 345"), 345)
    }

    func testNoAmount() {
        XCTAssertNil(AmountParser.parse("ありがとうございました"))
    }

    func testAmountsInOrder() {
        let matches = AmountParser.amounts(in: "8%対象 ¥652 消費税 ¥52")
        XCTAssertEqual(matches.map(\.amount), [8, 652, 52])
        XCTAssertEqual(matches.map(\.hasCurrencyMarker), [false, true, true])
    }
}

final class CTCGreedyDecoderTests: XCTestCase {

    private let decoder = CTCGreedyDecoder(vocabulary: ["", "あ", "い", "う"], blankIndex: 0)

    func testCollapseRepeatsAndBlanks() {
        XCTAssertEqual(
            decoder.decode(classIndices: [0, 1, 1, 0, 2, 2, 0, 0, 3]).text,
            "あいう"
        )
    }

    func testRepeatedCharacterNeedsBlankBetween() {
        // あ あ with no blank collapses; あ [blank] あ survives.
        XCTAssertEqual(decoder.decode(classIndices: [1, 1, 1]).text, "あ")
        XCTAssertEqual(decoder.decode(classIndices: [1, 0, 1]).text, "ああ")
    }

    func testOutOfRangeIndicesAreSkipped() {
        XCTAssertEqual(decoder.decode(classIndices: [1, 99, 2]).text, "あい")
    }

    func testLogitsArgmaxDecoding() {
        let logits: [[Double]] = [
            [0.1, 0.8, 0.05, 0.05],  // あ
            [0.9, 0.05, 0.03, 0.02], // blank
            [0.1, 0.1, 0.7, 0.1],    // い
            [0.1, 0.1, 0.7, 0.1],    // い (repeat, collapsed)
            [0.05, 0.05, 0.1, 0.8],  // う
        ]
        let decoded = decoder.decode(logits: logits)
        XCTAssertEqual(decoded.text, "あいう")
        // Mean of emitted probabilities: (0.8 + 0.7 + 0.8) / 3.
        XCTAssertEqual(decoded.confidence, 0.7666, accuracy: 0.001)
    }

    func testEmptyInput() {
        XCTAssertEqual(decoder.decode(classIndices: []).text, "")
        XCTAssertEqual(decoder.decode(logits: []).text, "")
    }
}
