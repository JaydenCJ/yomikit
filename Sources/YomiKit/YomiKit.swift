// YomiKit — Apple platform layer.
//
// This target wires Apple Vision / Core ML recognition into the
// platform-independent YomiKitCore pipeline. All platform-specific sources
// are guarded with `#if canImport(...)` so the package still compiles (as a
// core re-export) on Linux, where only YomiKitCore is functional.

@_exported import YomiKitCore

/// Package-level metadata that is available on every platform.
public enum YomiKitInfo {
    /// The package version.
    public static let version = "0.1.0"

    /// Whether the current build has the Vision-backed recognizer available.
    public static var hasVisionSupport: Bool {
        #if canImport(Vision)
        return true
        #else
        return false
        #endif
    }

    /// Whether the current build can load custom Core ML models.
    public static var hasCoreMLSupport: Bool {
        #if canImport(CoreML)
        return true
        #else
        return false
        #endif
    }
}
