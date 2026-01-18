import Foundation
import Yams

/// Helper for YAML and JSON serialization/deserialization
/// Provides reusable utilities for format conversion in parsers
enum SerializationHelper {

    // MARK: - YAML

    /// Parse YAML string to dictionary
    /// - Parameter content: YAML content string
    /// - Returns: Parsed dictionary
    /// - Throws: Error if parsing fails
    static func parseYAML(_ content: String) throws -> [String: Any] {
        guard let yaml = try Yams.load(yaml: content) as? [String: Any] else {
            throw ParsingError.yamlParsingFailed("Could not parse as dictionary")
        }
        return yaml
    }

    /// Serialize dictionary to YAML string
    /// - Parameter dict: Dictionary to serialize
    /// - Returns: YAML string
    /// - Throws: Error if serialization fails
    static func serializeToYAML(_ dict: [String: Any]) throws -> String {
        return try Yams.dump(object: dict, width: -1)
    }

    // MARK: - JSON

    /// Parse JSON string to dictionary
    /// - Parameter content: JSON content string
    /// - Returns: Parsed dictionary
    /// - Throws: Error if parsing fails
    static func parseJSON(_ content: String) throws -> [String: Any] {
        guard let data = content.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParsingError.jsonParsingFailed("Could not parse as dictionary")
        }
        return json
    }

    /// Serialize dictionary to JSON string
    /// - Parameters:
    ///   - dict: Dictionary to serialize
    ///   - prettyPrinted: Whether to format with indentation
    /// - Returns: JSON string
    /// - Throws: Error if serialization fails
    static func serializeToJSON(_ dict: [String: Any], prettyPrinted: Bool = true) throws -> String {
        let options: JSONSerialization.WritingOptions = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        let data = try JSONSerialization.data(withJSONObject: dict, options: options)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw ParsingError.jsonSerializationFailed("Could not encode JSON data as string")
        }
        return jsonString
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
