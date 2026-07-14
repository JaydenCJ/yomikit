/// The end-to-end orchestration: recognition backend in, structured
/// Japanese document out.
///
/// `DocumentPipeline` is platform-independent — it works with any
/// ``OCRBackend``, so the same pipeline runs with Apple Vision on iOS, a
/// custom Core ML model on macOS, or a ``MockOCRBackend`` in tests and on
/// Linux. The Apple-layer `YomiScanner` is a thin `CGImage` wrapper around
/// this type.
///
/// ```swift
/// let pipeline = DocumentPipeline(backend: MockOCRBackend<String>(returning: observations))
/// let layout = try await pipeline.document(in: "page-1")
/// let receipt = try await pipeline.receipt(in: "receipt")
/// let markdown = try await pipeline.markdown(in: "page-1")
/// ```
public struct DocumentPipeline<Backend: OCRBackend>: Sendable {

    /// The recognition backend that produces raw observations.
    public var backend: Backend

    /// Layout options used by ``document(in:)`` and ``markdown(in:)``.
    public var layoutOptions: LayoutOptions

    /// The table reconstructor used by ``table(in:)``.
    public var tableReconstructor: TableReconstructor

    /// The receipt extractor used by ``receipt(in:)``.
    public var receiptExtractor: ReceiptFieldExtractor

    public init(
        backend: Backend,
        layoutOptions: LayoutOptions = .default,
        tableReconstructor: TableReconstructor = TableReconstructor(),
        receiptExtractor: ReceiptFieldExtractor = ReceiptFieldExtractor()
    ) {
        self.backend = backend
        self.layoutOptions = layoutOptions
        self.tableReconstructor = tableReconstructor
        self.receiptExtractor = receiptExtractor
    }

    /// Raw recognition results, unprocessed.
    public func observations(in image: Backend.Image) async throws -> [TextObservation] {
        try await backend.recognize(in: image)
    }

    /// Recognizes text and reconstructs the page layout (vertical/horizontal
    /// detection, line/block clustering, reading order).
    public func document(in image: Backend.Image) async throws -> DocumentLayout {
        let observations = try await backend.recognize(in: image)
        return LayoutAnalyzer(options: layoutOptions).analyze(observations)
    }

    /// Recognizes a receipt and extracts structured fields.
    public func receipt(in image: Backend.Image) async throws -> Receipt {
        let observations = try await backend.recognize(in: image)
        return receiptExtractor.extract(from: observations)
    }

    /// Recognizes a table region and reconstructs rows and columns.
    /// Pass an image cropped to the table for best results.
    public func table(in image: Backend.Image) async throws -> Table {
        let observations = try await backend.recognize(in: image)
        return tableReconstructor.reconstruct(observations)
    }

    /// Recognizes a document and renders it as Markdown.
    public func markdown(in image: Backend.Image) async throws -> String {
        MarkdownRenderer.render(try await document(in: image))
    }

    /// Recognizes a document and returns pretty-printed JSON.
    public func json(in image: Backend.Image) async throws -> String {
        try JSONExporter.encode(try await document(in: image))
    }
}
