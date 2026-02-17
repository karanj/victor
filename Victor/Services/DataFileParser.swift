import Foundation
import Yams
import TOMLKit

/// Service for parsing and serializing Hugo data files (YAML/JSON/TOML)
class DataFileParser {
    static let shared = DataFileParser()

    private init() {}

    // MARK: - Parsing

    /// Parse a data file from disk
    /// - Parameter url: The file URL
    /// - Returns: A DataFile instance
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
    func save(_ dataFile: DataFile) async throws {
        let content = try serialize(dataFile)
        try await Task.detached {
            try content.write(to: dataFile.url, atomically: true, encoding: .utf8)
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
