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

    /// Parse a Hugo config file from disk
    func parseConfig(at url: URL) async throws -> HugoConfig {
        let content = try await Task.detached {
            try String(contentsOf: url, encoding: .utf8)
        }.value

        let format = ConfigFormat(filename: url.lastPathComponent) ?? .toml
        let dictionary = try parse(content: content, format: format)

        return HugoConfig(from: dictionary, format: format, url: url, rawContent: content)
    }

    /// Parse a Hugo config from a string
    /// - Parameters:
    ///   - content: The config file content as a string
    ///   - format: The format of the config (TOML, YAML, or JSON)
    /// - Returns: A HugoConfig object
    func parseConfig(content: String, format: ConfigFormat) throws -> HugoConfig {
        let dictionary = try parse(content: content, format: format)
        // Use a placeholder URL for string-based parsing (not associated with a file)
        let placeholderURL = URL(fileURLWithPath: "/dev/null")
        return HugoConfig(from: dictionary, format: format, url: placeholderURL, rawContent: content)
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
        return TOMLHelper.convertTOMLToDict(table)
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

        // Debug: log customFields types
        print("[HugoConfigParser] Building dictionary for serialization...")
        print("[HugoConfigParser] customFields keys: \(config.customFields.keys.sorted())")
        for (key, value) in config.customFields {
            print("[HugoConfigParser]   \(key): \(type(of: value))")
        }

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

        // Always include boolean fields - don't omit false values
        // Hugo's defaults may differ from ours, so explicit is safer
        dictionary["buildDrafts"] = config.buildDrafts
        dictionary["buildFuture"] = config.buildFuture
        dictionary["buildExpired"] = config.buildExpired
        dictionary["enableRobotsTXT"] = config.enableRobotsTXT

        // Always include these even if they match "defaults" - the user may have set them explicitly
        dictionary["summaryLength"] = config.summaryLength
        dictionary["defaultContentLanguage"] = config.defaultContentLanguage
        if let timeZone = config.timeZone, !timeZone.isEmpty {
            dictionary["timeZone"] = timeZone
        }

        // Taxonomies (if different from default)
        let defaultTaxonomies = ["category": "categories", "tag": "tags"]
        if config.taxonomies != defaultTaxonomies {
            dictionary["taxonomies"] = config.taxonomies
        }

        // Menus (use "menu" as it's more common in Hugo configs)
        if !config.menus.isEmpty {
            var menuDict: [String: [[String: Any]]] = [:]
            for (menuName, items) in config.menus {
                menuDict[menuName] = items.map { $0.toDictionary() }
            }
            dictionary["menu"] = menuDict
        }

        // Params - normalize for proper serialization
        if !config.params.isEmpty {
            dictionary["params"] = normalizeForSerialization(config.params)
        }

        // Custom fields - need to normalize types for proper serialization
        for (key, value) in config.customFields {
            dictionary[key] = normalizeForSerialization(value)
        }

        return try serialize(dictionary: dictionary, format: config.sourceFormat)
    }

    /// Recursively normalize values for serialization
    /// Converts Dictionary<AnyHashable, Any> to [String: Any] and handles nested structures
    private func normalizeForSerialization(_ value: Any) -> Any {
        if let dict = value as? [AnyHashable: Any] {
            // Convert AnyHashable keys to String keys
            var normalized: [String: Any] = [:]
            for (key, val) in dict {
                if let stringKey = key as? String {
                    normalized[stringKey] = normalizeForSerialization(val)
                } else {
                    normalized[String(describing: key)] = normalizeForSerialization(val)
                }
            }
            return normalized
        } else if let dict = value as? [String: Any] {
            // Already String keys, but recurse into values
            var normalized: [String: Any] = [:]
            for (key, val) in dict {
                normalized[key] = normalizeForSerialization(val)
            }
            return normalized
        } else if let array = value as? [Any] {
            return array.map { normalizeForSerialization($0) }
        } else {
            return value
        }
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

        // Serialize recursively, starting at root level
        serializeTOMLTable(dictionary, path: [], lines: &lines)

        return lines.joined(separator: "\n") + "\n"
    }

    /// Recursively serialize a TOML table
    /// - Parameters:
    ///   - dict: The dictionary to serialize
    ///   - path: The current path (e.g., ["menu", "main"] for [menu.main])
    ///   - lines: The output lines array
    private func serializeTOMLTable(_ dict: [String: Any], path: [String], lines: inout [String]) {
        // Separate simple values, tables, and arrays of tables
        var simpleValues: [(String, Any)] = []
        var nestedTables: [(String, [String: Any])] = []
        var arrayOfTables: [(String, [[String: Any]])] = []

        for (key, value) in dict.sorted(by: { $0.key < $1.key }) {
            if let arrayValue = value as? [Any] {
                // Check if this is an array of dictionaries (array of tables)
                if let dictArray = arrayValue as? [[String: Any]], !dictArray.isEmpty {
                    arrayOfTables.append((key, dictArray))
                } else {
                    // Simple array (strings, numbers, etc.)
                    simpleValues.append((key, value))
                }
            } else if let dictValue = value as? [String: Any] {
                nestedTables.append((key, dictValue))
            } else {
                simpleValues.append((key, value))
            }
        }

        // Write table header if we're not at root and have simple values
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
            let newPath = path + [key]
            serializeTOMLTable(nestedDict, path: newPath, lines: &lines)
        }

        // Write arrays of tables using [[table.name]] syntax
        for (key, dictArray) in arrayOfTables {
            let tablePath = path + [key]
            let tablePathStr = tablePath.joined(separator: ".")

            for tableDict in dictArray {
                if !lines.isEmpty {
                    lines.append("")
                }
                lines.append("[[\(tablePathStr)]]")

                // Write each key-value in the table
                for (itemKey, itemValue) in tableDict.sorted(by: { $0.key < $1.key }) {
                    if let nestedDict = itemValue as? [String: Any] {
                        // Nested table within array of tables
                        serializeTOMLTable(nestedDict, path: tablePath + [itemKey], lines: &lines)
                    } else if let nestedArray = itemValue as? [[String: Any]] {
                        // Nested array of tables within array of tables
                        for nestedTableDict in nestedArray {
                            lines.append("")
                            lines.append("[[\(tablePath.joined(separator: ".")).\(itemKey)]]")
                            for (nk, nv) in nestedTableDict.sorted(by: { $0.key < $1.key }) {
                                lines.append(formatTOMLValue(key: nk, value: nv))
                            }
                        }
                    } else {
                        lines.append(formatTOMLValue(key: itemKey, value: itemValue))
                    }
                }
            }
        }
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
            // Only for simple arrays (not arrays of tables)
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
        let output = try SerializationHelper.serializeToYAML(dictionary)

        // Verify the output is parseable (round-trip validation)
        do {
            _ = try Yams.load(yaml: output)
        } catch {
            print("[HugoConfigParser] YAML round-trip FAILED!")
            print("[HugoConfigParser] Serialized output:\n\(output)")
            print("[HugoConfigParser] Parse error: \(error)")
            throw error
        }

        return output
    }

    private func serializeToJSON(_ dictionary: [String: Any]) throws -> String {
        return try SerializationHelper.serializeToJSON(dictionary)
    }

    // MARK: - TOML Helpers
    // Now using TOMLHelper for conversion

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
