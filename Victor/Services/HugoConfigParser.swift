import Foundation
import Yams
import TOMLKit

/// Service for parsing and serializing Hugo configuration files
class HugoConfigParser {
    static let shared = HugoConfigParser()

    private init() {}

    // MARK: - Detection

    /// Find the Hugo config file in a site directory
    func findConfigFile(in siteURL: URL) -> URL? {
        let fileManager = FileManager.default

        // Check for single-file configs in order of precedence
        let configNames = [
            "hugo.toml", "hugo.yaml", "hugo.json",
            "config.toml", "config.yaml", "config.json"
        ]

        for name in configNames {
            let url = siteURL.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    // MARK: - Parsing

    /// Parse a Hugo config file
    func parseConfig(at url: URL) async throws -> HugoConfig {
        let content = try await Task.detached {
            try String(contentsOf: url, encoding: .utf8)
        }.value

        let format = ConfigFormat(filename: url.lastPathComponent) ?? .toml
        let dictionary = try parse(content: content, format: format)

        return HugoConfig(from: dictionary, format: format, url: url, rawContent: content)
    }

    /// Parse content based on format
    private func parse(content: String, format: ConfigFormat) throws -> [String: Any] {
        switch format {
        case .toml:
            return try parseTOML(content)
        case .yaml:
            return try parseYAML(content)
        case .json:
            return try parseJSON(content)
        }
    }

    private func parseTOML(_ content: String) throws -> [String: Any] {
        let table = try TOMLTable(string: content)
        return convertTOMLToDict(table)
    }

    private func parseYAML(_ content: String) throws -> [String: Any] {
        guard let result = try Yams.load(yaml: content) as? [String: Any] else {
            throw ConfigError.invalidFormat
        }
        return result
    }

    private func parseJSON(_ content: String) throws -> [String: Any] {
        guard let data = content.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigError.invalidFormat
        }
        return result
    }

    // MARK: - Serialization

    /// Serialize a HugoConfig back to string
    func serialize(_ config: HugoConfig) throws -> String {
        var dictionary: [String: Any] = [:]

        // Required fields
        if !config.baseURL.isEmpty {
            dictionary["baseURL"] = config.baseURL
        }
        if !config.title.isEmpty {
            dictionary["title"] = config.title
        }
        if !config.languageCode.isEmpty {
            dictionary["languageCode"] = config.languageCode
        }

        // Optional fields
        // Theme can be a string or array - preserve original format
        if let theme = config.theme, !theme.isEmpty {
            if config.themeIsArray || theme.contains(", ") {
                // Array format - split by comma
                dictionary["theme"] = theme.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                // String format
                dictionary["theme"] = theme
            }
        }
        if let copyright = config.copyright, !copyright.isEmpty {
            dictionary["copyright"] = copyright
        }
        if config.buildDrafts {
            dictionary["buildDrafts"] = true
        }
        if config.buildFuture {
            dictionary["buildFuture"] = true
        }
        if config.buildExpired {
            dictionary["buildExpired"] = true
        }
        if config.enableRobotsTXT {
            dictionary["enableRobotsTXT"] = true
        }
        if config.summaryLength != 70 {
            dictionary["summaryLength"] = config.summaryLength
        }
        if config.defaultContentLanguage != "en" {
            dictionary["defaultContentLanguage"] = config.defaultContentLanguage
        }
        if let timeZone = config.timeZone, !timeZone.isEmpty {
            dictionary["timeZone"] = timeZone
        }

        // Taxonomies (if different from default)
        let defaultTaxonomies = ["category": "categories", "tag": "tags"]
        if config.taxonomies != defaultTaxonomies {
            dictionary["taxonomies"] = config.taxonomies
        }

        // Menus
        if !config.menus.isEmpty {
            var menusDict: [String: [[String: Any]]] = [:]
            for (menuName, items) in config.menus {
                menusDict[menuName] = items.map { $0.toDictionary() }
            }
            dictionary["menus"] = menusDict
        }

        // Params
        if !config.params.isEmpty {
            dictionary["params"] = config.params
        }

        // Custom fields
        for (key, value) in config.customFields {
            dictionary[key] = value
        }

        return try serialize(dictionary: dictionary, format: config.sourceFormat)
    }

    private func serialize(dictionary: [String: Any], format: ConfigFormat) throws -> String {
        switch format {
        case .toml:
            return try serializeToTOML(dictionary)
        case .yaml:
            return try serializeToYAML(dictionary)
        case .json:
            return try serializeToJSON(dictionary)
        }
    }

    private func serializeToTOML(_ dictionary: [String: Any]) throws -> String {
        var lines: [String] = []
        var tables: [(String, [String: Any])] = []

        // First pass: simple values
        for (key, value) in dictionary.sorted(by: { $0.key < $1.key }) {
            if let dictValue = value as? [String: Any] {
                tables.append((key, dictValue))
            } else {
                lines.append(formatTOMLValue(key: key, value: value))
            }
        }

        // Second pass: tables
        for (tableName, tableDict) in tables {
            lines.append("")
            lines.append("[\(tableName)]")
            for (key, value) in tableDict.sorted(by: { $0.key < $1.key }) {
                if let nestedDict = value as? [String: Any] {
                    // Handle nested tables
                    lines.append("")
                    lines.append("[\(tableName).\(key)]")
                    for (nestedKey, nestedValue) in nestedDict.sorted(by: { $0.key < $1.key }) {
                        lines.append(formatTOMLValue(key: nestedKey, value: nestedValue))
                    }
                } else {
                    lines.append(formatTOMLValue(key: key, value: value))
                }
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func formatTOMLValue(key: String, value: Any) -> String {
        if let stringValue = value as? String {
            // Escape special characters in strings
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

    private func serializeToYAML(_ dictionary: [String: Any]) throws -> String {
        return try Yams.dump(object: dictionary)
    }

    private func serializeToJSON(_ dictionary: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: dictionary,
            options: [.prettyPrinted, .sortedKeys]
        )
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - TOML Helpers

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

        // Handle TOMLValue - TOMLKit wraps values in this type
        // TOMLValue has optional properties for each type
        if let tomlValue = value as? TOMLValue {
            // Check each possible type in order
            if let str = tomlValue.string {
                return str
            }
            if let bool = tomlValue.bool {
                return bool
            }
            if let int = tomlValue.int {
                return Int(int)
            }
            if let double = tomlValue.double {
                return double
            }
            if let date = tomlValue.date {
                return "\(date)"
            }
            if let time = tomlValue.time {
                return "\(time)"
            }
            if let dateTime = tomlValue.dateTime {
                return "\(dateTime)"
            }
            if let array = tomlValue.array {
                return array.compactMap { convertTOMLValue($0) }
            }
            if let table = tomlValue.table {
                return convertTOMLToDict(table)
            }
        }

        // Handle nested tables
        if let table = value as? TOMLTable {
            var dict: [String: Any] = [:]
            for key in table.keys {
                if let converted = convertTOMLValue(table[key]) {
                    dict[key] = converted
                }
            }
            return dict
        }

        // Handle arrays
        if let array = value as? [Any] {
            return array.compactMap { convertTOMLValue($0) }
        }

        // For native Swift types (fallback)
        if let stringValue = value as? String {
            return stringValue
        }
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let intValue = value as? Int {
            return intValue
        }
        if let int64Value = value as? Int64 {
            return Int(int64Value)
        }
        if let doubleValue = value as? Double {
            return doubleValue
        }

        // Fallback for any other type
        return value
    }

    // MARK: - Raw Content

    /// Read raw file content from disk
    func readRawContent(from url: URL) async throws -> String {
        try await Task.detached {
            try String(contentsOf: url, encoding: .utf8)
        }.value
    }
}

// MARK: - Errors

enum ConfigError: LocalizedError {
    case invalidFormat
    case fileNotFound
    case serializationFailed

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid configuration file format"
        case .fileNotFound:
            return "Configuration file not found"
        case .serializationFailed:
            return "Failed to serialize configuration"
        }
    }
}
