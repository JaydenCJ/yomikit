import Foundation

/// Serializes YomiKit result types (all `Codable`) to JSON strings with
/// stable, diff-friendly formatting.
public enum JSONExporter {

    public enum ExportError: Error, Sendable {
        case notUTF8Representable
    }

    /// Encodes any encodable value as JSON.
    /// - Parameters:
    ///   - value: The value to encode (e.g. ``DocumentLayout``, ``Table``,
    ///     ``Receipt``).
    ///   - prettyPrinted: Human-readable formatting with sorted keys.
    public static func encode(_ value: some Encodable, prettyPrinted: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.sortedKeys]
        }
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw ExportError.notUTF8Representable
        }
        return string
    }
}
