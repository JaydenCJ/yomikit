#if canImport(CoreML) && canImport(Vision)
import CoreGraphics
import CoreML
import CoreVideo
import Foundation
import Vision
import YomiKitCore

/// Loads Core ML models for use with ``CoreMLTextRecognizer``.
public enum CoreMLModelLoader {

    public enum LoadError: Error, Sendable {
        case unreadableModel(String)
    }

    /// Loads a model from disk. Compiled models (`.mlmodelc`) are loaded
    /// directly; source models (`.mlmodel` / `.mlpackage`) are compiled
    /// on device first.
    public static func load(
        contentsOf url: URL,
        configuration: MLModelConfiguration = MLModelConfiguration()
    ) async throws -> MLModel {
        if url.pathExtension == "mlmodelc" {
            return try MLModel(contentsOf: url, configuration: configuration)
        }
        let compiledURL = try await MLModel.compileModel(at: url)
        return try MLModel(contentsOf: compiledURL, configuration: configuration)
    }
}

/// Text recognition with a custom Core ML recognition model (for example a
/// model converted with `tools/convert_recognizer.py`). Conforms to
/// ``OCRBackend`` so it plugs into ``DocumentPipeline`` and ``YomiScanner``.
///
/// Pipeline: Vision proposes text regions → each region is cropped and
/// scaled to the model's input size (tall tategaki columns are rotated
/// first, see ``Configuration/verticalRegionHandling``) → the model
/// produces per-timestep class logits → ``CTCGreedyDecoder`` (YomiKitCore)
/// turns them into text.
public final class CoreMLTextRecognizer: OCRBackend, @unchecked Sendable {

    /// How to feed a clearly tall (vertical / tategaki column) region into
    /// a fixed-size horizontal line-recognition model.
    ///
    /// Squashing a tall column into a wide input destroys the glyphs, so
    /// by default tall regions are rotated a quarter turn before scaling.
    /// Whether glyphs then appear in the orientation your model was trained
    /// on depends on the training data — pick the direction that matches
    /// it, or `.none` if the model handles vertical lines natively.
    public enum VerticalRegionHandling: Sendable {
        /// Feed tall regions unchanged (they are squashed into the
        /// horizontal input size).
        case none
        /// Rotate tall regions 90° counterclockwise, so the top of the
        /// column becomes the left edge and reading order is preserved
        /// along the model's time axis. This is the default.
        case rotateCounterclockwise
        /// Rotate tall regions 90° clockwise, so the top of the column
        /// becomes the right edge.
        case rotateClockwise
    }

    public struct Configuration: Sendable {
        /// Name of the model's image input feature.
        public var inputName: String
        /// Name of the model's logits output feature
        /// (shape `[T, C]` or `[1, T, C]`).
        public var outputName: String
        /// The fixed input size the model expects.
        public var inputWidth: Int
        public var inputHeight: Int
        /// Class index → character mapping. Load it from the
        /// `<output>-vocab.json` file exported by the conversion script
        /// with ``YomiKitCore/RecognizerVocabulary`` and pass it to the
        /// `Configuration(vocabulary: RecognizerVocabulary)` initializer.
        public var vocabulary: [String]
        /// CTC blank class index.
        public var blankIndex: Int
        /// Padding added around detected regions before cropping, as a
        /// fraction of the region size.
        public var regionPadding: Double
        /// How tall (tategaki column) regions are fed to the model.
        /// The tall/wide decision is made by
        /// ``YomiKitCore/OrientationClassifier/classifyRegion(width:height:)``.
        public var verticalRegionHandling: VerticalRegionHandling

        public init(
            inputName: String = "image",
            outputName: String = "logits",
            inputWidth: Int = 320,
            inputHeight: Int = 48,
            vocabulary: [String],
            blankIndex: Int = 0,
            regionPadding: Double = 0.05,
            verticalRegionHandling: VerticalRegionHandling = .rotateCounterclockwise
        ) {
            self.inputName = inputName
            self.outputName = outputName
            self.inputWidth = inputWidth
            self.inputHeight = inputHeight
            self.vocabulary = vocabulary
            self.blankIndex = blankIndex
            self.regionPadding = regionPadding
            self.verticalRegionHandling = verticalRegionHandling
        }

        /// Creates a configuration from the vocabulary file exported by
        /// `tools/convert_recognizer.py` (`<output>-vocab.json`), loaded
        /// with ``YomiKitCore/RecognizerVocabulary``:
        ///
        /// ```swift
        /// let vocab = try RecognizerVocabulary(contentsOf: vocabURL)
        /// let config = CoreMLTextRecognizer.Configuration(vocabulary: vocab)
        /// ```
        public init(
            inputName: String = "image",
            outputName: String = "logits",
            inputWidth: Int = 320,
            inputHeight: Int = 48,
            vocabulary: RecognizerVocabulary,
            regionPadding: Double = 0.05,
            verticalRegionHandling: VerticalRegionHandling = .rotateCounterclockwise
        ) {
            self.init(
                inputName: inputName,
                outputName: outputName,
                inputWidth: inputWidth,
                inputHeight: inputHeight,
                vocabulary: vocabulary.vocabulary,
                blankIndex: vocabulary.blankIndex,
                regionPadding: regionPadding,
                verticalRegionHandling: verticalRegionHandling
            )
        }
    }

    public enum RecognitionError: Error, Sendable {
        case pixelBufferCreationFailed
        case missingOutput(String)
        case unexpectedOutputShape([Int])
    }

    private let model: MLModel
    private let configuration: Configuration
    private let decoder: CTCGreedyDecoder
    private let regionClassifier = OrientationClassifier()

    public init(model: MLModel, configuration: Configuration) {
        self.model = model
        self.configuration = configuration
        self.decoder = CTCGreedyDecoder(
            vocabulary: configuration.vocabulary,
            blankIndex: configuration.blankIndex
        )
    }

    /// Convenience: load the model from disk and build a recognizer.
    public convenience init(modelAt url: URL, configuration: Configuration) async throws {
        let model = try await CoreMLModelLoader.load(contentsOf: url)
        self.init(model: model, configuration: configuration)
    }

    public func recognize(in image: CGImage) async throws -> [TextObservation] {
        let regions = try detectTextRegions(in: image)
        var observations: [TextObservation] = []
        observations.reserveCapacity(regions.count)

        for region in regions {
            guard let crop = image.cropping(to: region) else { continue }
            let decoded = try recognizeLine(in: crop, rotation: rotation(for: region))
            guard !decoded.text.isEmpty else { continue }
            observations.append(
                TextObservation(
                    text: decoded.text,
                    boundingBox: BoundingBox(
                        x: region.origin.x,
                        y: region.origin.y,
                        width: region.size.width,
                        height: region.size.height
                    ),
                    confidence: decoded.confidence
                )
            )
        }
        return observations
    }

    // MARK: - Region proposal (Vision text detection)

    private func detectTextRegions(in image: CGImage) throws -> [CGRect] {
        let request = VNDetectTextRectanglesRequest()
        request.reportCharacterBoxes = false
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let width = Double(image.width)
        let height = Double(image.height)
        let padding = configuration.regionPadding

        return (request.results ?? []).map { observation in
            let box = BoundingBox(
                normalizedVisionRect: observation.boundingBox,
                imageWidth: width,
                imageHeight: height
            )
            let padX = box.width * padding
            let padY = box.height * padding
            let x = max(0, box.x - padX)
            let y = max(0, box.y - padY)
            return CGRect(
                x: x,
                y: y,
                width: min(width - x, box.width + 2 * padX),
                height: min(height - y, box.height + 2 * padY)
            )
        }
    }

    // MARK: - Single-line recognition

    /// A quarter-turn rotation applied while rendering a region crop into
    /// the model's fixed input size.
    private enum QuarterRotation {
        case none
        case clockwise
        case counterclockwise
    }

    /// Decides how a region crop should be rotated before recognition:
    /// clearly tall regions are tategaki columns and get the configured
    /// vertical handling; wide or near-square regions pass through as-is.
    /// The tall/wide decision is pure ``OrientationClassifier`` logic and
    /// is unit-tested in YomiKitCore.
    private func rotation(for region: CGRect) -> QuarterRotation {
        let orientation = regionClassifier.classifyRegion(
            width: Double(region.width),
            height: Double(region.height)
        )
        guard orientation == .vertical else { return .none }
        switch configuration.verticalRegionHandling {
        case .none: return .none
        case .rotateClockwise: return .clockwise
        case .rotateCounterclockwise: return .counterclockwise
        }
    }

    private func recognizeLine(
        in image: CGImage,
        rotation: QuarterRotation
    ) throws -> CTCGreedyDecoder.DecodedText {
        let pixelBuffer = try makePixelBuffer(
            from: image,
            width: configuration.inputWidth,
            height: configuration.inputHeight,
            rotation: rotation
        )
        let input = try MLDictionaryFeatureProvider(dictionary: [
            configuration.inputName: MLFeatureValue(pixelBuffer: pixelBuffer)
        ])
        let output = try model.prediction(from: input)
        guard let logitsValue = output.featureValue(for: configuration.outputName),
            let multiArray = logitsValue.multiArrayValue
        else {
            throw RecognitionError.missingOutput(configuration.outputName)
        }
        return decoder.decode(logits: try logitsMatrix(from: multiArray))
    }

    /// Reads an MLMultiArray of shape `[T, C]` or `[1, T, C]` into a
    /// row-major `[[Double]]`.
    private func logitsMatrix(from multiArray: MLMultiArray) throws -> [[Double]] {
        var shape = multiArray.shape.map(\.intValue)
        var offsetDimensions = 0
        while shape.count > 2, shape.first == 1 {
            shape.removeFirst()
            offsetDimensions += 1
        }
        guard shape.count == 2 else {
            throw RecognitionError.unexpectedOutputShape(multiArray.shape.map(\.intValue))
        }
        let timesteps = shape[0]
        let classes = shape[1]
        var matrix = Array(repeating: [Double](repeating: 0, count: classes), count: timesteps)
        for t in 0..<timesteps {
            for c in 0..<classes {
                var indices = [NSNumber](repeating: 0, count: offsetDimensions)
                indices.append(NSNumber(value: t))
                indices.append(NSNumber(value: c))
                matrix[t][c] = multiArray[indices].doubleValue
            }
        }
        return matrix
    }

    // MARK: - Pixel buffer preparation

    private func makePixelBuffer(
        from image: CGImage,
        width: Int,
        height: Int,
        rotation: QuarterRotation
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw RecognitionError.pixelBufferCreationFailed
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else {
            throw RecognitionError.pixelBufferCreationFailed
        }
        context.interpolationQuality = .high
        // The bitmap context uses Quartz coordinates (origin bottom-left,
        // y up); the raster's top row is device y = height. Rotations are
        // described below in visual (top-down raster) terms.
        switch rotation {
        case .none:
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        case .counterclockwise:
            // Visual 90° CCW: the top of the source column ends up at the
            // left edge, so top-to-bottom reading order becomes the model's
            // left-to-right time axis.
            context.translateBy(x: CGFloat(width), y: 0)
            context.rotate(by: .pi / 2)
            context.draw(image, in: CGRect(x: 0, y: 0, width: height, height: width))
        case .clockwise:
            // Visual 90° CW: the top of the source column ends up at the
            // right edge.
            context.translateBy(x: 0, y: CGFloat(height))
            context.rotate(by: -.pi / 2)
            context.draw(image, in: CGRect(x: 0, y: 0, width: height, height: width))
        }
        return buffer
    }
}
#endif
