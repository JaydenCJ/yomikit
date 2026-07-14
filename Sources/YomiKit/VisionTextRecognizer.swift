#if canImport(Vision)
import CoreGraphics
import Vision
import YomiKitCore

/// Text recognition backed by Apple's Vision framework, configured for
/// Japanese documents by default. Conforms to ``OCRBackend`` so it plugs
/// into ``DocumentPipeline`` and ``YomiScanner``.
///
/// Vision reports normalized bounding boxes with a bottom-left origin; this
/// wrapper converts them to YomiKit's top-left-origin pixel coordinates
/// before handing them to the core pipeline.
public struct VisionTextRecognizer: OCRBackend {

    public struct Configuration: Sendable {
        /// Language priority for recognition. Japanese first by default.
        public var recognitionLanguages: [String]
        /// Vision's language-correction pass. Disable for strings that are
        /// not natural language (product codes, prices).
        public var usesLanguageCorrection: Bool
        /// Use the accurate (slower) recognition path.
        public var accurate: Bool
        /// Minimum text height relative to the image height (0...1), or
        /// `nil` for Vision's default.
        public var minimumTextHeight: Float?

        public init(
            recognitionLanguages: [String] = ["ja-JP", "en-US"],
            usesLanguageCorrection: Bool = true,
            accurate: Bool = true,
            minimumTextHeight: Float? = nil
        ) {
            self.recognitionLanguages = recognitionLanguages
            self.usesLanguageCorrection = usesLanguageCorrection
            self.accurate = accurate
            self.minimumTextHeight = minimumTextHeight
        }
    }

    public var configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public func recognize(in image: CGImage) async throws -> [TextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = configuration.accurate ? .accurate : .fast
        request.recognitionLanguages = configuration.recognitionLanguages
        request.usesLanguageCorrection = configuration.usesLanguageCorrection
        if let minimumTextHeight = configuration.minimumTextHeight {
            request.minimumTextHeight = minimumTextHeight
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let results = request.results ?? []
        let width = Double(image.width)
        let height = Double(image.height)

        return results.compactMap { observation -> TextObservation? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return TextObservation(
                text: candidate.string,
                boundingBox: BoundingBox(
                    normalizedVisionRect: observation.boundingBox,
                    imageWidth: width,
                    imageHeight: height
                ),
                confidence: Double(candidate.confidence)
            )
        }
    }
}

extension BoundingBox {
    /// Converts a Vision normalized rect (bottom-left origin, 0...1) into
    /// pixel coordinates with a top-left origin.
    public init(normalizedVisionRect rect: CGRect, imageWidth: Double, imageHeight: Double) {
        self.init(
            x: rect.origin.x * imageWidth,
            y: (1.0 - rect.origin.y - rect.size.height) * imageHeight,
            width: rect.size.width * imageWidth,
            height: rect.size.height * imageHeight
        )
    }
}
#endif
