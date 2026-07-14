#if canImport(Vision)
import CoreGraphics
import Vision
import YomiKitCore

/// The one-line entry point on Apple platforms: image in, structured
/// Japanese document out.
///
/// ```swift
/// let scanner = YomiScanner()
/// let receipt = try await scanner.receipt(in: cgImage)
/// let layout = try await scanner.document(in: cgImage)   // tategaki-aware
/// let table = try await scanner.table(in: cgImage)
/// ```
///
/// `YomiScanner` is a thin `CGImage`-typed wrapper around
/// ``YomiKitCore/DocumentPipeline``. It defaults to Apple Vision configured
/// for Japanese; pass a ``CoreMLTextRecognizer`` (or any custom
/// ``YomiKitCore/OCRBackend``) to use your own model.
public struct YomiScanner: Sendable {

    /// The underlying platform-independent pipeline.
    public var pipeline: DocumentPipeline<AnyOCRBackend<CGImage>>

    /// Creates a scanner with a custom recognition backend.
    public init<Backend: OCRBackend>(
        recognizer: Backend,
        layoutOptions: LayoutOptions = .default
    ) where Backend.Image == CGImage {
        pipeline = DocumentPipeline(
            backend: AnyOCRBackend(recognizer),
            layoutOptions: layoutOptions
        )
    }

    /// Creates a scanner backed by Apple Vision configured for Japanese.
    public init(layoutOptions: LayoutOptions = .default) {
        self.init(recognizer: VisionTextRecognizer(), layoutOptions: layoutOptions)
    }

    /// Recognizes text and reconstructs the page layout (vertical/horizontal
    /// detection, line/block clustering, reading order).
    public func document(in image: CGImage) async throws -> DocumentLayout {
        try await pipeline.document(in: image)
    }

    /// Recognizes a receipt and extracts structured fields.
    public func receipt(in image: CGImage) async throws -> Receipt {
        try await pipeline.receipt(in: image)
    }

    /// Recognizes a table region and reconstructs rows and columns.
    /// Pass an image cropped to the table for best results.
    public func table(in image: CGImage) async throws -> Table {
        try await pipeline.table(in: image)
    }

    /// Recognizes a document and renders it as Markdown.
    public func markdown(in image: CGImage) async throws -> String {
        try await pipeline.markdown(in: image)
    }

    /// Recognizes a document and returns pretty-printed JSON.
    public func json(in image: CGImage) async throws -> String {
        try await pipeline.json(in: image)
    }
}
#endif
