import XCTest
@testable import YomiKitCore

final class ReceiptExtractionTests: XCTestCase {

    func testFullReceiptFromObservations() {
        let receipt = ReceiptFieldExtractor().extract(from: Fixtures.receiptObservations)

        // Store name: the tallest line near the top.
        XCTAssertEqual(receipt.storeName, "スーパーマルヤマ 川崎店")

        // Date and time, normalized.
        XCTAssertEqual(receipt.date, YMDDate(year: 2026, month: 7, day: 8))
        XCTAssertEqual(receipt.date?.isoString, "2026-07-08")
        XCTAssertEqual(receipt.time, "18:42")

        // Items, including a quantity line and a negative discount.
        XCTAssertEqual(receipt.items.count, 5)
        XCTAssertEqual(receipt.items[0], ReceiptItem(name: "おにぎり ツナマヨ", price: 138))
        XCTAssertEqual(receipt.items[1], ReceiptItem(name: "サンドイッチ ハム", price: 298))
        XCTAssertEqual(receipt.items[2], ReceiptItem(name: "お茶 500ml", price: 216, quantity: 2))
        XCTAssertEqual(receipt.items[3], ReceiptItem(name: "洗剤 ハイパワー", price: 120))
        XCTAssertEqual(receipt.items[4], ReceiptItem(name: "お値引き", price: -20))
        XCTAssertEqual(receipt.itemsTotal, 752)

        // Amounts.
        XCTAssertEqual(receipt.subtotal, 752)
        XCTAssertEqual(receipt.total, 814)
        XCTAssertEqual(receipt.tendered, 1000)
        XCTAssertEqual(receipt.change, 186)
        XCTAssertEqual(receipt.declaredItemCount, 4)

        // Tax lines: overall 消費税等, then one line per rate.
        XCTAssertEqual(receipt.taxLines.count, 3)
        let rate8 = receipt.taxLines.first { $0.rate == 8 }
        XCTAssertEqual(rate8?.taxableAmount, 652)
        XCTAssertEqual(rate8?.taxAmount, 52)
        let rate10 = receipt.taxLines.first { $0.rate == 10 }
        XCTAssertEqual(rate10?.taxableAmount, 100)
        XCTAssertEqual(rate10?.taxAmount, 10)
        let overall = receipt.taxLines.first { $0.rate == nil }
        XCTAssertEqual(overall?.taxAmount, 62)
    }

    func testFullReceiptFromPlainLinesWithFullwidthDigits() {
        let receipt = ReceiptFieldExtractor().extract(fromLines: Fixtures.receiptLines)

        XCTAssertEqual(receipt.storeName, "スーパーマルヤマ 川崎店")
        XCTAssertEqual(receipt.date?.isoString, "2026-07-08")
        XCTAssertEqual(receipt.time, "18:42")
        // Full-width ￥１３８ is normalized before parsing.
        XCTAssertEqual(receipt.items.first, ReceiptItem(name: "おにぎり ツナマヨ", price: 138))
        XCTAssertEqual(receipt.subtotal, 752)
        XCTAssertEqual(receipt.total, 814)
        XCTAssertEqual(receipt.tendered, 1000)
        XCTAssertEqual(receipt.change, 186)
    }

    func testWarekiDateOnReceipt() {
        let receipt = ReceiptFieldExtractor().extract(fromLines: [
            "コンビニヤマダ",
            "令和8年7月8日 09:15",
            "コーヒー ¥150",
            "合計 ¥150",
        ])
        XCTAssertEqual(receipt.date?.isoString, "2026-07-08")
        XCTAssertEqual(receipt.time, "09:15")
        XCTAssertEqual(receipt.storeName, "コンビニヤマダ")
        XCTAssertEqual(receipt.total, 150)
        XCTAssertEqual(receipt.items, [ReceiptItem(name: "コーヒー", price: 150)])
    }

    func testAmountOnFollowingLine() {
        let receipt = ReceiptFieldExtractor().extract(fromLines: [
            "喫茶ドリーム",
            "合計",
            "¥1,234",
        ])
        XCTAssertEqual(receipt.total, 1234)
    }

    func testTenderedTotalLineIsNotMistakenForTotal() {
        let receipt = ReceiptFieldExtractor().extract(fromLines: [
            "店名",
            "合計 ¥500",
            "お預り合計 ¥1,000",
        ])
        XCTAssertEqual(receipt.total, 500)
        XCTAssertEqual(receipt.tendered, 1000)
    }

    func testReducedRateMarkerIsDetected() {
        let receipt = ReceiptFieldExtractor().extract(fromLines: [
            "店名",
            "8%対象(軽減税率) ¥1,080",
        ])
        XCTAssertEqual(receipt.taxLines.count, 1)
        XCTAssertEqual(receipt.taxLines[0].rate, 8)
        XCTAssertTrue(receipt.taxLines[0].isReducedRate)
        XCTAssertEqual(receipt.taxLines[0].taxableAmount, 1080)
    }

    func testTaxLinesWithSameRateAreMerged() {
        let receipt = ReceiptFieldExtractor().extract(fromLines: [
            "店名",
            "10%対象 ¥2,200",
            "内消費税(10%) ¥200",
        ])
        XCTAssertEqual(receipt.taxLines.count, 1)
        XCTAssertEqual(receipt.taxLines[0].rate, 10)
        XCTAssertEqual(receipt.taxLines[0].taxableAmount, 2200)
        XCTAssertEqual(receipt.taxLines[0].taxAmount, 200)
    }

    func testAddressAndPhoneLinesDoNotBecomeItems() {
        let receipt = ReceiptFieldExtractor().extract(fromLines: [
            "店名",
            "東京都品川区東品川1-2-3",
            "TEL:03-1234-5678",
            "パン ¥100",
            "合計 ¥100",
        ])
        XCTAssertEqual(receipt.items, [ReceiptItem(name: "パン", price: 100)])
    }

    func testEmptyInput() {
        let receipt = ReceiptFieldExtractor().extract(fromLines: [])
        XCTAssertNil(receipt.storeName)
        XCTAssertNil(receipt.total)
        XCTAssertTrue(receipt.items.isEmpty)
    }
}
