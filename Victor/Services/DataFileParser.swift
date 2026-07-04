import Foundation
import Yams
import TOMLKit

/// Service for parsing and serializing Hugo data files (YAML/JSON/TOML)
/// Stateless aside from `private init()` — safe to hand across actor boundaries.
final class DataFileParser: @unchecked Sendable {
    static let shared = DataFileParser()

    private init() {}

    // MARK: - Parsing

    /// Parse a data file from disk
    /// - Parameter url: The file URL
    /// - Returns: A DataFile instance
    /// `@MainActor`: constructs a `DataFile`, which is itself `@MainActor`-isolated
    /// (WP3.5 Cluster 13) — this method already only ever runs from `@MainActor` callers.
    @MainActor
    func parseDataFile(at url: URL) async throws -> DataFile {
        let content = try await Task.detached {
            try String(contentsOf: url, encoding: .utf8)
        }.value

        guard let format = DataFormat.from(url: url) else {
            throw DataFileError.unsupportedFormat
        }

        let data = try parse(content: content, format: format)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let lastModified = attributes[.modificationDate] as? Date ?? Date()

        return DataFile(
            url: url,
            format: format,
            data: data,
            rawContent: content,
            lastModified: lastModified
        )
    }

    /// Parse content string into data structure
    /// - Parameters:
    ///   - content: The file content
    ///   - format: The data format
    /// - Returns: Parsed data (dictionary or array)
    func parse(content: String, format: DataFormat) throws -> Any {
        switch format {
        case .yaml:
            return try parseYAML(content)
        case .json:
            return try parseJSON(content)
        case .toml:
            return try parseTOML(content)
        }
    }

    private func parseYAML(_ content: String) throws -> Any {
        guard let result = try Yams.load(yaml: content) else {
            throw DataFileError.invalidFormat
        }
        // Yams can return dictionary, array, or scalar
        return result
    }

    private func parseJSON(_ content: String) throws -> Any {
        guard let data = content.data(using: .utf8) else {
            throw DataFileError.invalidFormat
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    private func parseTOML(_ content: String) throws -> Any {
        // TOML always has a root table (dictionary)
        let table = try TOMLTable(string: content)
        return TOMLHelper.convertTOMLToDict(table)
    }

    // MARK: - Serialization

    /// Serialize a DataFile back to string
    /// `@MainActor`: reads the `@MainActor`-isolated `DataFile.data` (WP3.5 Cluster 13).
    @MainActor
    func serialize(_ dataFile: DataFile) throws -> String {
        let normalized = SerializationHelper.normalizeForSerialization(dataFile.data)
        return try serialize(data: normalized, format: dataFile.format)
    }

    /// Serialize data to string in specified format
    func serialize(data: Any, format: DataFormat) throws -> String {
        switch format {
        case .yaml:
            return try serializeToYAML(data)
        case .json:
            return try serializeToJSON(data)
        case .toml:
            guard let dict = data as? [String: Any] else {
                throw DataFileError.tomlRequiresDictionary
            }
            return try serializeToTOML(dict)
        }
    }

    private func serializeToYAML(_ data: Any) throws -> String {
        guard let dict = data as? [String: Any] else {
            throw DataFileError.serializationFailed
        }

        return try SerializationHelper.serializeToYAMLValidated(dict)
    }

    private func serializeToJSON(_ data: Any) throws -> String {
        guard let dict = data as? [String: Any] else {
            throw DataFileError.serializationFailed
        }
        return try SerializationHelper.serializeToJSON(dict)
    }

    private func serializeToTOML(_ dictionary: [String: Any]) throws -> String {
        return TOMLHelper.serializeToTOML(dictionary)
    }

    // MARK: - File Operations

    /// Save a DataFile to disk
    /// `@MainActor`: touches the `@MainActor`-isolated `DataFile` (WP3.5 Cluster 13).
    @MainActor
    func save(_ dataFile: DataFile) async throws {
        let content = try serialize(dataFile)
        // Capture only the Sendable url primitive - never `dataFile` itself -
        // before entering Task.detached (WP3.5 Cluster 13 line-level fix).
        let url = dataFile.url
        try await Task.detached {
            try content.write(to: url, atomically: true, encoding: .utf8)
        }.value
        dataFile.updateRawContent(content)
        dataFile.markAsSaved()
    }
}

// MARK: - Errors

enum DataFileError: LocalizedError {
    case unsupportedFormat
    case invalidFormat
    case serializationFailed
    case tomlRequiresDictionary

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Unsupported data file format"
        case .invalidFormat:
            return "Invalid data file format"
        case .serializationFailed:
            return "Failed to serialize data file"
        case .tomlRequiresDictionary:
            return "TOML format requires a dictionary root structure"
        }
    }
}
