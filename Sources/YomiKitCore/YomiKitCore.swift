/// YomiKitCore — platform-independent document understanding for Japanese
/// OCR output.
///
/// The module takes positioned text observations (from Apple Vision, a
/// custom Core ML model, or any OCR engine) and produces structure:
///
/// * ``LayoutAnalyzer`` — vertical/horizontal layout analysis, line and
///   block clustering, reading order (tategaki columns right→left).
/// * ``TableReconstructor`` — row/column alignment inference and structured
///   ``Table`` output, including spanning cells.
/// * ``ReceiptFieldExtractor`` — store name, date (wareki-aware), totals,
///   tax-rate lines and items from Japanese receipts.
/// * ``JapaneseTextNormalizer`` and friends — width normalization, kanji
///   numerals, era dates, amounts.
/// * ``MarkdownRenderer`` / ``JSONExporter`` — structured output.
/// * ``OCRBackend`` / ``MockOCRBackend`` / ``DocumentPipeline`` — the
///   recognition abstraction and the end-to-end orchestration built on it.
///
/// Everything in this module is pure Swift with no platform dependencies,
/// so it builds and tests on Linux as well as on Apple platforms.
public enum YomiKitCore {
    /// The package version.
    public static let version = "0.1.0"
}
