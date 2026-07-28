import Foundation
import Yams

/// Helper for YAML and JSON serialization/deserialization
/// Provides reusable utilities for format conversion in parsers
enum SerializationHelper {

    // MARK: - YAML

    /// Throws if the document isn't a top-level mapping.
    static func parseYAML(_ content: String) throws -> [String: Any] {
        guard let yaml = try Yams.load(yaml: content) as? [String: Any] else {
            throw ParsingError.yamlParsingFailed("Could not parse as dictionary")
        }
        return yaml
    }

    /// Accepts a mapping or a sequence at the root - both are valid YAML documents.
    static func serializeToYAML(_ value: Any) throws -> String {
        return try Yams.dump(object: value, width: -1)
    }

    // MARK: - JSON

    /// Throws if the document isn't a top-level object.
    static func parseJSON(_ content: String) throws -> [String: Any] {
        guard let data = content.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParsingError.jsonParsingFailed("Could not parse as dictionary")
        }
        return json
    }

    /// Accepts an object or an array at the root. Keys are always sorted, so output is
    /// stable across runs.
    static func serializeToJSON(_ value: Any, prettyPrinted: Bool = true) throws -> String {
        let options: JSONSerialization.WritingOptions = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        let data = try JSONSerialization.data(withJSONObject: value, options: options)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw ParsingError.jsonSerializationFailed("Could not encode JSON data as string")
        }
        return jsonString
    }

    // MARK: - Normalization

    /// Recursively normalize values for serialization
    /// Converts `[AnyHashable: Any]` (returned by Yams) to `[String: Any]`
    static func normalizeForSerialization(_ value: Any) -> Any {
        if let dict = value as? [AnyHashable: Any] {
            var normalized: [String: Any] = [:]
            for (key, val) in dict {
                let stringKey = (key as? String) ?? String(describing: key)
                normalized[stringKey] = normalizeForSerialization(val)
            }
            return normalized
        } else if let dict = value as? [String: Any] {
            var normalized: [String: Any] = [:]
            for (key, val) in dict {
                normalized[key] = normalizeForSerialization(val)
            }
            return normalized
        } else if let array = value as? [Any] {
            return array.map { normalizeForSerialization($0) }
        }
        return value
    }

    // MARK: - Validated Serialization

    /// Serialize to YAML, then parse it back - throwing rather than emitting YAML we can't reread.
    static func serializeToYAMLValidated(_ value: Any) throws -> String {
        let output = try serializeToYAML(value)

        // Round-trip validation: ensure output is parseable
        do {
            _ = try Yams.load(yaml: output)
        } catch {
            print("[SerializationHelper] YAML round-trip validation failed!")
            print("[SerializationHelper] Serialized output:\n\(output)")
            print("[SerializationHelper] Parse error: \(error)")
            throw error
        }

        return output
    }

    // MARK: - Errors

    enum ParsingError: LocalizedError {
        case yamlParsingFailed(String)
        case yamlSerializationFailed(String)
        case jsonParsingFailed(String)
        case jsonSerializationFailed(String)

        var errorDescription: String? {
            switch self {
            case .yamlParsingFailed(let message):
                return "YAML parsing failed: \(message)"
            case .yamlSerializationFailed(let message):
                return "YAML serialization failed: \(message)"
            case .jsonParsingFailed(let message):
                return "JSON parsing failed: \(message)"
            case .jsonSerializationFailed(let message):
                return "JSON serialization failed: \(message)"
            }
        }
    }
}
