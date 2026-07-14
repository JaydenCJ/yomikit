/// A deterministic ``OCRBackend`` that returns scripted observations
/// instead of running a model.
///
/// This is the test double for the whole package: pipeline orchestration
/// (recognize → layout → extract → export) is verified against it on every
/// platform, including Linux where no real OCR engine exists. It is also
/// useful in apps, e.g. for previews and UI tests that need stable OCR
/// results without model files.
///
/// ```swift
/// let backend = MockOCRBackend<String>(returning: observations)
/// let pipeline = DocumentPipeline(backend: backend)
/// let receipt = try await pipeline.receipt(in: "receipt.png")
/// ```
public struct MockOCRBackend<Image: Sendable>: OCRBackend {
    private let handler: @Sendable (Image) throws -> [TextObservation]

    /// A backend that returns the same observations for every image.
    public init(returning observations: [TextObservation]) {
        handler = { _ in observations }
    }

    /// A backend that throws `error` for every image.
    public init(throwing error: some Error & Sendable) {
        handler = { _ in throw error }
    }

    /// A backend driven by a custom handler, for scripting different
    /// results per input (e.g. keyed by an image identifier).
    public init(handler: @escaping @Sendable (Image) throws -> [TextObservation]) {
        self.handler = handler
    }

    public func recognize(in image: Image) async throws -> [TextObservation] {
        try handler(image)
    }
}
