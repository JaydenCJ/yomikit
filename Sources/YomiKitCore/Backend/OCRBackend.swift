/// A recognition backend: an engine that turns an image into positioned
/// ``TextObservation`` values in YomiKit's top-left-origin coordinate space.
///
/// The backend is the only inference-dependent piece of YomiKit. Everything
/// downstream (layout analysis, tables, receipts, exporters) is pure logic
/// that consumes observations, so any engine that can produce text with
/// bounding boxes plugs into the whole pipeline:
///
/// * `VisionTextRecognizer` (YomiKit target) — Apple Vision, Japanese-first.
/// * `CoreMLTextRecognizer` (YomiKit target) — custom Core ML models
///   converted with `tools/convert_recognizer.py`.
/// * ``MockOCRBackend`` — deterministic scripted results for tests and for
///   running the pipeline on Linux, where no OCR engine is available.
///
/// The `Image` associated type is deliberately opaque to the core module:
/// Apple backends use `CGImage`, a test backend can use `String` labels or
/// raw bytes. YomiKitCore never inspects pixels.
public protocol OCRBackend<Image>: Sendable {
    /// The image representation this backend consumes.
    associatedtype Image: Sendable

    /// Recognizes text in `image` and returns observations in pixel
    /// coordinates with a top-left origin.
    func recognize(in image: Image) async throws -> [TextObservation]
}

/// A type-erased ``OCRBackend`` over a fixed image type.
///
/// Useful for storing heterogeneous backends behind one property, e.g. a
/// scanner that can switch between Vision and a custom Core ML model at
/// runtime.
public struct AnyOCRBackend<Image: Sendable>: OCRBackend {
    private let recognizeHandler: @Sendable (Image) async throws -> [TextObservation]

    /// Wraps `base`, forwarding all recognition calls to it.
    public init<Backend: OCRBackend>(_ base: Backend) where Backend.Image == Image {
        recognizeHandler = { try await base.recognize(in: $0) }
    }

    public func recognize(in image: Image) async throws -> [TextObservation] {
        try await recognizeHandler(image)
    }
}
