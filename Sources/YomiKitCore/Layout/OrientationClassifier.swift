/// Infers the dominant writing direction of a page from bounding-box
/// geometry alone.
///
/// The heuristic: OCR engines emit text runs that are elongated along the
/// reading axis. Horizontal (yokogaki) runs are wide and short; vertical
/// (tategaki) runs are tall and narrow. Near-square runs (single characters,
/// very short fragments) carry no signal and are ignored. Evidence is
/// weighted by box area so a large body-text block outvotes small noise.
public struct OrientationClassifier: Sendable {

    /// Aspect ratio (long side / short side) above which a run is treated
    /// as directional evidence. Runs closer to square are ignored.
    public var minAspectRatio: Double

    public init(minAspectRatio: Double = 1.6) {
        self.minAspectRatio = minAspectRatio
    }

    /// Classifies the dominant orientation of a set of observations.
    /// Returns `.horizontal` when there is no usable evidence, since
    /// horizontal writing is the safer default for modern documents.
    public func classify(_ observations: [TextObservation]) -> TextOrientation {
        var horizontalWeight = 0.0
        var verticalWeight = 0.0

        for observation in observations {
            let box = observation.boundingBox
            guard box.width > 0, box.height > 0 else { continue }
            if box.width / box.height >= minAspectRatio {
                horizontalWeight += box.area
            } else if box.height / box.width >= minAspectRatio {
                verticalWeight += box.area
            }
        }

        if verticalWeight > horizontalWeight {
            return .vertical
        }
        return .horizontal
    }

    /// Classifies a single proposed text region by its aspect ratio alone.
    ///
    /// Recognition backends use this to decide how to feed a region crop to
    /// a fixed-size line-recognition model: a clearly tall region is a
    /// vertical (tategaki) column and should be rotated into the model's
    /// horizontal input instead of being squashed (see
    /// `CoreMLTextRecognizer.Configuration.verticalRegionHandling` in the
    /// YomiKit target). Returns `nil` for near-square or degenerate regions,
    /// which carry no directional signal.
    public func classifyRegion(width: Double, height: Double) -> TextOrientation? {
        guard width > 0, height > 0 else { return nil }
        if width / height >= minAspectRatio {
            return .horizontal
        }
        if height / width >= minAspectRatio {
            return .vertical
        }
        return nil
    }
}
