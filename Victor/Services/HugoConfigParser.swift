import Foundation
import Yams
import TOMLKit

/// Service for parsing and serializing Hugo configuration files
/// Stateless aside from `private init()` — safe to hand across actor boundaries.
final class HugoConfigParser: @unchecked Sendable {
    static let shared = HugoConfigParser()

    private init() {}

    // MARK: - Detection

    /// Find the Hugo config file in a site directory
    func findConfigFile(in siteURL: URL) -> URL? {
        let fileManager = FileManager.default

        // Check for single-file configs in order of precedence: basename-major
        // (any hugo.* beats any config.*), extensions toml/yaml/yml/json —
        // matching Hugo's DefaultConfigNames × ValidConfigFileExtensions
        let configNames = [
            "hugo.toml", "hugo.yaml", "hugo.yml", "hugo.json",
            "config.toml", "config.yaml", "config.yml", "config.json"
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
    /// `parseConfig` carries no actor annotation (`HugoConfigParser` is a plain
    /// `@unchecked Sendable` class), so `Task.detached` here was redundant - removed
    /// rather than converted to a helper (victor-tdt audit). `@concurrent` (SE-0461,
    /// verified to compile in this project's Swift 6.0 language mode with no
    /// upcoming-feature flag) compiler-pins the blocking `String(contentsOf:)` read off
    /// the concurrent executor regardless of the `NonisolatedNonsendingByDefault`
    /// setting, rather than relying on today's default the way a bare `nonisolated
    /// async` function would.
    @concurrent
    func parseConfig(at url: URL) async throws -> HugoConfig {
        let content = try String(contentsOf: url, encoding: .utf8)

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

    /// Parse content based on format.
    /// The result is normalized once at this boundary — Yams nests
    /// [AnyHashable: Any] dictionaries that can't serialize back — so every
    /// consumer only ever sees [String: Any] (CONFIG-SCHEMA-SPEC §2.2).
    private func parse(content: String, format: ConfigFormat) throws -> [String: Any] {
        let dictionary: [String: Any]
        switch format {
        case .toml:
            dictionary = try parseTOML(content)
        case .yaml:
            dictionary = try parseYAML(content)
        case .json:
            dictionary = try parseJSON(content)
        }
        return SerializationHelper.normalizeForSerialization(dictionary) as? [String: Any] ?? dictionary
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

    /// Serialize a HugoConfig back to string.
    /// Sparse by design: a key is written only when the source file had it or
    /// the user changed it — never injected because Victor has a typed field
    /// for it (design-doc issues #1/#2).
    func serialize(_ config: HugoConfig) throws -> String {
        var dictionary: [String: Any] = [:]

        // Root scalars
        if config.shouldSerializeRootKey("baseURL", currentValue: config.baseURL) {
            dictionary["baseURL"] = config.baseURL
        }
        if config.shouldSerializeRootKey("title", currentValue: config.title) {
            dictionary["title"] = config.title
        }
        if config.shouldSerializeRootKey("languageCode", currentValue: config.languageCode) {
            dictionary["languageCode"] = config.languageCode
        }

        // Optional strings: empty means "not set", so presence alone doesn't
        // force an empty value back into the file
        // Theme can be a string or array - preserve original format
        if let theme = config.theme, !theme.isEmpty,
           config.shouldSerializeRootKey("theme", currentValue: theme) {
            if config.themeIsArray || theme.contains(", ") {
                // Array format - split by comma
                dictionary["theme"] = theme.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                // String format
                dictionary["theme"] = theme
            }
        }
        if let copyright = config.copyright, !copyright.isEmpty,
           config.shouldSerializeRootKey("copyright", currentValue: copyright) {
            dictionary["copyright"] = copyright
        }
        if let timeZone = config.timeZone, !timeZone.isEmpty,
           config.shouldSerializeRootKey("timeZone", currentValue: timeZone) {
            dictionary["timeZone"] = timeZone
        }

        // Booleans and numbers: explicit false/default values are preserved
        // when the file declared them, but never injected when it didn't
        if config.shouldSerializeRootKey("buildDrafts", currentValue: config.buildDrafts) {
            dictionary["buildDrafts"] = config.buildDrafts
        }
        if config.shouldSerializeRootKey("buildFuture", currentValue: config.buildFuture) {
            dictionary["buildFuture"] = config.buildFuture
        }
        if config.shouldSerializeRootKey("buildExpired", currentValue: config.buildExpired) {
            dictionary["buildExpired"] = config.buildExpired
        }
        if config.shouldSerializeRootKey("enableRobotsTXT", currentValue: config.enableRobotsTXT) {
            dictionary["enableRobotsTXT"] = config.enableRobotsTXT
        }
        if config.shouldSerializeRootKey("summaryLength", currentValue: config.summaryLength) {
            dictionary["summaryLength"] = config.summaryLength
        }
        if config.shouldSerializeRootKey("defaultContentLanguage", currentValue: config.defaultContentLanguage) {
            dictionary["defaultContentLanguage"] = config.defaultContentLanguage
        }

        // Taxonomies: explicitly-declared defaults round-trip (issue #2)
        if !config.taxonomies.isEmpty,
           config.shouldSerializeRootKey("taxonomies", currentValue: config.taxonomies) {
            dictionary["taxonomies"] = config.taxonomies
        }

        // Menus, under the same key spelling the file used (issue #3)
        if !config.menus.isEmpty {
            var menuDict: [String: [[String: Any]]] = [:]
            for (menuName, items) in config.menus {
                menuDict[menuName] = items.map { $0.toDictionary() }
            }
            dictionary[config.menuKeySpelling] = menuDict
        }

        // Permalinks
        if !config.permalinks.isEmpty {
            dictionary["permalinks"] = config.permalinks
        }

        // Params - normalize for proper serialization
        if !config.params.isEmpty {
            dictionary["params"] = SerializationHelper.normalizeForSerialization(config.params)
        }

        // Custom fields - need to normalize types for proper serialization
        for (key, value) in config.customFields {
            dictionary[key] = SerializationHelper.normalizeForSerialization(value)
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
        return TOMLHelper.serializeToTOML(dictionary)
    }

    private func serializeToYAML(_ dictionary: [String: Any]) throws -> String {
        return try SerializationHelper.serializeToYAMLValidated(dictionary)
    }

    private func serializeToJSON(_ dictionary: [String: Any]) throws -> String {
        return try SerializationHelper.serializeToJSON(dictionary)
    }

    // MARK: - TOML Helpers
    // Now using TOMLHelper for conversion

    // MARK: - Raw Content

    /// Read raw file content from disk
    /// Same reasoning as `parseConfig` above: `Task.detached` was redundant here, and
    /// `@concurrent` now compiler-pins the blocking read off the actor.
    @concurrent
    func readRawContent(from url: URL) async throws -> String {
        try String(contentsOf: url, encoding: .utf8)
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
