import YomiKitCore

/// Shared synthetic fixtures modeling realistic OCR output geometry.
enum Fixtures {

    static func obs(
        _ text: String,
        x: Double,
        y: Double,
        w: Double,
        h: Double = 16
    ) -> TextObservation {
        TextObservation(
            text: text,
            boundingBox: BoundingBox(x: x, y: y, width: w, height: h)
        )
    }

    // MARK: - Receipt (convenience-store style, tax-excluded pricing)

    /// A supermarket receipt as raw observations. Item/price fragments are
    /// separated by wide gaps, the store name uses a larger font, amounts
    /// use both `¥1,000`-style separators and bare digits, the discount is
    /// negative, and there are two tax rates (8% reduced / 10%).
    static var receiptObservations: [TextObservation] {
        [
            // Store name: larger font.
            obs("スーパーマルヤマ", x: 60, y: 10, w: 180, h: 28),
            obs("川崎店", x: 250, y: 12, w: 70, h: 24),
            obs("東京都品川区東品川1-2-3", x: 40, y: 48, w: 240, h: 14),
            obs("TEL:03-1234-5678", x: 60, y: 70, w: 180, h: 14),
            obs("2026年7月8日(火)", x: 20, y: 94, w: 170),
            obs("18:42", x: 250, y: 94, w: 60),
            obs("レジ#003", x: 20, y: 118, w: 90),
            obs("担当:佐藤", x: 150, y: 118, w: 100),
            obs("おにぎり ツナマヨ", x: 10, y: 142, w: 170),
            obs("¥138", x: 320, y: 142, w: 50),
            obs("サンドイッチ ハム", x: 10, y: 166, w: 170),
            obs("¥298", x: 320, y: 166, w: 50),
            obs("お茶 500ml", x: 10, y: 190, w: 110),
            obs("×2", x: 200, y: 190, w: 30),
            obs("¥216", x: 320, y: 190, w: 50),
            obs("洗剤 ハイパワー", x: 10, y: 214, w: 150),
            obs("¥120", x: 320, y: 214, w: 50),
            obs("お値引き", x: 10, y: 238, w: 90),
            obs("-20", x: 330, y: 238, w: 40),
            obs("小計", x: 10, y: 262, w: 50),
            obs("¥752", x: 310, y: 262, w: 60),
            obs("消費税等", x: 10, y: 286, w: 90),
            obs("¥62", x: 320, y: 286, w: 50),
            obs("合計", x: 10, y: 310, w: 50),
            obs("¥814", x: 310, y: 310, w: 60),
            obs("(8%対象 ¥652", x: 10, y: 334, w: 140),
            obs("消費税 ¥52)", x: 180, y: 334, w: 120),
            obs("(10%対象 ¥100", x: 10, y: 358, w: 150),
            obs("消費税 ¥10)", x: 180, y: 358, w: 120),
            obs("お預り", x: 10, y: 382, w: 70),
            obs("¥1,000", x: 300, y: 382, w: 70),
            obs("お釣り", x: 10, y: 406, w: 70),
            obs("¥186", x: 310, y: 406, w: 50),
            obs("買上点数 4点", x: 10, y: 430, w: 130),
            obs("ありがとうございました", x: 40, y: 454, w: 230),
        ]
    }

    /// The same receipt as pre-ordered plain-text lines, with full-width
    /// characters as OCR often produces them.
    static let receiptLines: [String] = [
        "スーパーマルヤマ 川崎店",
        "東京都品川区東品川1-2-3",
        "TEL:03-1234-5678",
        "２０２６年７月８日(火) 18:42",
        "レジ#003 担当:佐藤",
        "おにぎり ツナマヨ ￥１３８",
        "サンドイッチ ハム ¥298",
        "お茶 500ml ×2 ¥216",
        "洗剤 ハイパワー ¥120",
        "お値引き -20",
        "小計 ¥752",
        "消費税等 ¥62",
        "合計 ¥814",
        "(8%対象 ¥652 消費税 ¥52)",
        "(10%対象 ¥100 消費税 ¥10)",
        "お預り ¥1,000",
        "お釣り ¥186",
        "買上点数 4点",
        "ありがとうございました",
    ]

    // MARK: - Vertical (tategaki) page

    /// A single tategaki block: four columns read right → left.
    /// Column x positions (left edges): 350, 310, 270, 230.
    static var tategakiColumns: [TextObservation] {
        [
            obs("とんと見当がつかぬ", x: 230, y: 40, w: 30, h: 270),
            obs("どこで生れたか", x: 270, y: 40, w: 30, h: 210),
            obs("名前はまだ無い", x: 310, y: 40, w: 30, h: 210),
            obs("吾輩は猫である", x: 350, y: 40, w: 30, h: 210),
        ]
    }

    /// Expected reading order for ``tategakiColumns``.
    static let tategakiExpectedOrder = [
        "吾輩は猫である",
        "名前はまだ無い",
        "どこで生れたか",
        "とんと見当がつかぬ",
    ]

    /// Tategaki page with a separate title column on the far right and a
    /// three-column body block. The title must be read first.
    static var tategakiTitleAndBody: [TextObservation] {
        [
            obs("本文一列目", x: 300, y: 40, w: 24, h: 300),
            obs("本文二列目", x: 260, y: 40, w: 24, h: 300),
            obs("本文三列目", x: 220, y: 40, w: 24, h: 300),
            obs("題名", x: 370, y: 40, w: 24, h: 360),
        ]
    }

    /// A fuller tategaki novel page modeled at *fragment* granularity, the
    /// way real backends emit observations: a heading column set off by a
    /// wide gutter, then six body columns, each broken into two vertical
    /// fragments with 1–2 px of x jitter and uneven fragment heights.
    /// Exercises column re-assembly from fragments, not just whole-column
    /// ordering. Body column left edges (right → left): 390, 358, 326, 294,
    /// 262, 230; heading at 450 behind a 36 px gutter.
    static var tategakiNovelPage: [TextObservation] {
        [
            // Column 3 fragments (deliberately out of input order).
            obs("どこで", x: 326, y: 60, w: 24, h: 130),
            obs("生れたか", x: 327, y: 210, w: 24, h: 150),
            // Column 1.
            obs("吾輩は", x: 390, y: 60, w: 24, h: 150),
            obs("猫である。", x: 391, y: 228, w: 24, h: 170),
            // Column 6.
            obs("薄暗い", x: 230, y: 60, w: 24, h: 120),
            obs("じめじめした", x: 230, y: 206, w: 24, h: 192),
            // Heading column, separated by a wide gutter.
            obs("第一章", x: 450, y: 40, w: 26, h: 200),
            // Column 2.
            obs("名前は", x: 358, y: 60, w: 24, h: 140),
            obs("まだ無い。", x: 357, y: 224, w: 24, h: 174),
            // Column 4.
            obs("とんと", x: 294, y: 60, w: 24, h: 130),
            obs("見当が", x: 294, y: 212, w: 24, h: 130),
            // Column 5.
            obs("つかぬ。", x: 262, y: 60, w: 24, h: 160),
            obs("何でも", x: 261, y: 240, w: 24, h: 120),
        ]
    }

    /// Expected line texts for ``tategakiNovelPage``: heading first, then
    /// body columns right → left, fragments joined top → bottom.
    static let tategakiNovelPageExpectedOrder = [
        "第一章",
        "吾輩は猫である。",
        "名前はまだ無い。",
        "どこで生れたか",
        "とんと見当が",
        "つかぬ。何でも",
        "薄暗いじめじめした",
    ]

    /// Tategaki page with two stacked sections (newspaper "dan"): the whole
    /// top section is read before the bottom one, right → left inside each.
    static var tategakiTwoSections: [TextObservation] {
        [
            // Bottom section.
            obs("下段右", x: 330, y: 300, w: 26, h: 180),
            obs("下段左", x: 290, y: 300, w: 26, h: 180),
            // Top section.
            obs("上段右", x: 330, y: 40, w: 26, h: 180),
            obs("上段左", x: 290, y: 40, w: 26, h: 180),
        ]
    }

    // MARK: - Horizontal multi-column page

    /// Horizontal page: full-width title, then two columns separated by a
    /// wide gutter (left column read fully before the right column).
    static var horizontalTwoColumns: [TextObservation] {
        [
            obs("右段落一行目", x: 240, y: 70, w: 140, h: 18),
            obs("左段落一行目", x: 40, y: 70, w: 140, h: 18),
            obs("見出しのテキスト", x: 40, y: 20, w: 340, h: 24),
            obs("左段落二行目", x: 40, y: 96, w: 140, h: 18),
            obs("右段落二行目", x: 240, y: 96, w: 140, h: 18),
        ]
    }

    // MARK: - Table

    /// A clean 3×3 table with y jitter of up to 3px.
    static var table3x3: [TextObservation] {
        [
            obs("品名", x: 20, y: 20, w: 80, h: 20),
            obs("数量", x: 140, y: 22, w: 60, h: 20),
            obs("金額", x: 240, y: 21, w: 80, h: 20),
            obs("りんご", x: 20, y: 60, w: 80, h: 20),
            obs("3", x: 140, y: 63, w: 60, h: 20),
            obs("¥450", x: 240, y: 61, w: 80, h: 20),
            obs("みかん", x: 20, y: 100, w: 80, h: 20),
            obs("5", x: 140, y: 102, w: 60, h: 20),
            obs("¥600", x: 240, y: 99, w: 80, h: 20),
        ]
    }

    /// Table whose header cell spans columns 2–3; body rows are 3 columns.
    static var tableWithColumnSpan: [TextObservation] {
        [
            obs("月", x: 20, y: 20, w: 80, h: 20),
            obs("売上高", x: 140, y: 20, w: 180, h: 20), // spans the two numeric columns
            obs("1月", x: 20, y: 60, w: 80, h: 20),
            obs("120", x: 140, y: 60, w: 60, h: 20),
            obs("140", x: 260, y: 60, w: 60, h: 20),
            obs("2月", x: 20, y: 100, w: 80, h: 20),
            obs("150", x: 140, y: 100, w: 60, h: 20),
            obs("170", x: 260, y: 100, w: 60, h: 20),
        ]
    }
}
