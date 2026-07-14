/// One purchased item on a receipt.
public struct ReceiptItem: Sendable, Hashable, Codable {
    /// Item name as printed (normalized).
    public var name: String
    /// Line price in yen. Negative for discounts (`値引`, `割引`).
    public var price: Int
    /// Quantity when the line declares one (`×2`, `2個`, `2点`).
    public var quantity: Int?

    public init(name: String, price: Int, quantity: Int? = nil) {
        self.name = name
        self.price = price
        self.quantity = quantity
    }
}

/// A tax summary line (`8%対象 ¥1,080` / `消費税(10%) ¥200` …).
public struct ReceiptTaxLine: Sendable, Hashable, Codable {
    /// Tax rate in percent (8, 10, …); `nil` when the line only mentions
    /// 消費税 without a rate.
    public var rate: Int?
    /// Whether the line is marked as the reduced rate (軽減税率 / ※).
    public var isReducedRate: Bool
    /// The taxable base amount (対象額), when printed.
    public var taxableAmount: Int?
    /// The tax amount itself (消費税額), when printed.
    public var taxAmount: Int?

    public init(
        rate: Int?,
        isReducedRate: Bool = false,
        taxableAmount: Int? = nil,
        taxAmount: Int? = nil
    ) {
        self.rate = rate
        self.isReducedRate = isReducedRate
        self.taxableAmount = taxableAmount
        self.taxAmount = taxAmount
    }
}

/// Structured fields extracted from a Japanese receipt.
public struct Receipt: Sendable, Hashable, Codable {
    /// Store name (店名), when identified.
    public var storeName: String?
    /// Purchase date, normalized to a Gregorian calendar date (wareki
    /// era dates are converted).
    public var date: YMDDate?
    /// Purchase time as `HH:MM`, when printed.
    public var time: String?
    /// Line items in order of appearance.
    public var items: [ReceiptItem]
    /// 小計 line, in yen.
    public var subtotal: Int?
    /// 合計 line, in yen.
    public var total: Int?
    /// Tax summary lines (one per rate, merged).
    public var taxLines: [ReceiptTaxLine]
    /// お預り (cash tendered), in yen.
    public var tendered: Int?
    /// お釣り (change), in yen.
    public var change: Int?
    /// Declared item count (買上点数), when printed.
    public var declaredItemCount: Int?
    /// All input lines after normalization, in reading order.
    public var rawLines: [String]

    public init(
        storeName: String? = nil,
        date: YMDDate? = nil,
        time: String? = nil,
        items: [ReceiptItem] = [],
        subtotal: Int? = nil,
        total: Int? = nil,
        taxLines: [ReceiptTaxLine] = [],
        tendered: Int? = nil,
        change: Int? = nil,
        declaredItemCount: Int? = nil,
        rawLines: [String] = []
    ) {
        self.storeName = storeName
        self.date = date
        self.time = time
        self.items = items
        self.subtotal = subtotal
        self.total = total
        self.taxLines = taxLines
        self.tendered = tendered
        self.change = change
        self.declaredItemCount = declaredItemCount
        self.rawLines = rawLines
    }

    /// Sum of item prices — handy for validating against ``subtotal``.
    public var itemsTotal: Int {
        items.map(\.price).reduce(0, +)
    }
}
