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
        return convertTOMLToDict(table)
    }

    // MARK: - Serialization

    /// Serialize a DataFile back to string
    func serialize(_ dataFile: DataFile) throws -> String {
        let normalized = normalizeForSerialization(dataFile.data)
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
        // Use width: -1 to prevent line wrapping
        let output = try Yams.dump(object: data, width: -1, allowUnicode: true)

        // Round-trip validation
        _ = try Yams.load(yaml: output)

        return output
    }

    private func serializeToJSON(_ data: Any) throws -> String {
        let jsonData = try JSONSerialization.data(
            withJSONObject: data,
            options: [.prettyPrinted, .sortedKeys]
        )
        guard let output = String(data: jsonData, encoding: .utf8) else {
            throw DataFileError.serializationFailed
        }
        return output
    }

    private func serializeToTOML(_ dictionary: [String: Any]) throws -> String {
        var lines: [String] = []
        serializeTOMLTable(dictionary, path: [], lines: &lines)
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - TOML Serialization Helpers

    private func serializeTOMLTable(_ dict: [String: Any], path: [String], lines: inout [String]) {
        var simpleValues: [(String, Any)] = []
        var nestedTables: [(String, [String: Any])] = []
        var arrayOfTables: [(String, [[String: Any]])] = []

        for (key, value) in dict.sorted(by: { $0.key < $1.key }) {
            if let arrayValue = value as? [Any] {
                if let dictArray = arrayValue as? [[String: Any]], !dictArray.isEmpty {
                    arrayOfTables.append((key, dictArray))
                } else {
                    simpleValues.append((key, value))
                }
            } else if let dictValue = value as? [String: Any] {
                nestedTables.append((key, dictValue))
            } else {
                simpleValues.append((key, value))
            }
        }

        // Write table header if not at root and have simple values
        if !path.isEmpty && !simpleValues.isEmpty {
            if !lines.isEmpty {
                lines.append("")
            }
            lines.append("[\(path.joined(separator: "."))]")
        }

        // Write simple values
        for (key, value) in simpleValues {
            lines.append(formatTOMLValue(key: key, value: value))
        }

        // Write nested tables
        for (key, nestedDict) in nestedTables {
            serializeTOMLTable(nestedDict, path: path + [key], lines: &lines)
        }

        // Write arrays of tables
        for (key, dictArray) in arrayOfTables {
            let tablePath = path + [key]
            let tablePathStr = tablePath.joined(separator: ".")

            for tableDict in dictArray {
                if !lines.isEmpty {
                    lines.append("")
                }
                lines.append("[[\(tablePathStr)]]")

                for (itemKey, itemValue) in tableDict.sorted(by: { $0.key < $1.key }) {
                    if let nestedDict = itemValue as? [String: Any] {
                        serializeTOMLTable(nestedDict, path: tablePath + [itemKey], lines: &lines)
                    } else {
                        lines.append(formatTOMLValue(key: itemKey, value: itemValue))
                    }
                }
            }
        }
    }

    private func formatTOMLValue(key: String, value: Any) -> String {
        if let stringValue = value as? String {
            let escaped = stringValue
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\(key) = \"\(escaped)\""
        } else if let boolValue = value as? Bool {
            return "\(key) = \(boolValue)"
        } else if let intValue = value as? Int {
            return "\(key) = \(intValue)"
        } else if let doubleValue = value as? Double {
            return "\(key) = \(doubleValue)"
        } else if let arrayValue = value as? [Any] {
            let formatted = arrayValue.map { formatTOMLArrayElement($0) }.joined(separator: ", ")
            return "\(key) = [\(formatted)]"
        }
        return "\(key) = \"\(String(describing: value))\""
    }

    private func formatTOMLArrayElement(_ value: Any) -> String {
        if let stringValue = value as? String {
            let escaped = stringValue
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        } else if let boolValue = value as? Bool {
            return "\(boolValue)"
        } else if let intValue = value as? Int {
            return "\(intValue)"
        } else if let doubleValue = value as? Double {
            return "\(doubleValue)"
        }
        return "\"\(String(describing: value))\""
    }

    // MARK: - TOML Parsing Helpers

    private func convertTOMLToDict(_ table: TOMLTable) -> [String: Any] {
        var result: [String: Any] = [:]
        for key in table.keys {
            if let converted = convertTOMLValue(table[key]) {
                result[key] = converted
            }
        }
        return result
    }

    private func convertTOMLValue(_ value: Any?) -> Any? {
        guard let value = value else { return nil }

        if let tomlValue = value as? TOMLValue {
            if let str = tomlValue.string { return str }
            if let bool = tomlValue.bool { return bool }
            if let int = tomlValue.int { return Int(int) }
            if let double = tomlValue.double { return double }
            if let date = tomlValue.date { return "\(date)" }
            if let time = tomlValue.time { return "\(time)" }
            if let dateTime = tomlValue.dateTime { return "\(dateTime)" }
            if let array = tomlValue.array {
                return array.compactMap { convertTOMLValue($0) }
            }
            if let table = tomlValue.table {
                return convertTOMLToDict(table)
            }
        }

        if let table = value as? TOMLTable {
            return convertTOMLToDict(table)
        }

        if let array = value as? [Any] {
            return array.compactMap { convertTOMLValue($0) }
        }

        // Native Swift types
        if let stringValue = value as? String { return stringValue }
        if let boolValue = value as? Bool { return boolValue }
        if let intValue = value as? Int { return intValue }
        if let int64Value = value as? Int64 { return Int(int64Value) }
        if let doubleValue = value as? Double { return doubleValue }

        return value
    }

    // MARK: - Normalization

    /// Recursively normalize values for serialization
    private func normalizeForSerialization(_ value: Any) -> Any {
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
