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

    /// Parse a Hugo config file from disk. `@concurrent` pins the blocking
    /// `String(contentsOf:)` read to the concurrent executor rather than relying on the
    /// current `NonisolatedNonsendingByDefault` value.
    @concurrent
    func parseConfig(at url: URL) async throws -> HugoConfig {
        let content = try String(contentsOf: url, encoding: .utf8)

        let format = ConfigFormat(filename: url.lastPathComponent) ?? .toml
        let dictionary = try parse(content: content, format: format)

        return HugoConfig(from: dictionary, format: format, url: url, rawContent: content,
                          orderedRootKeys: rootKeyOrder(of: content, format: format))
    }

    /// Parse from a string rather than a file - the resulting config gets a placeholder URL.
    func parseConfig(content: String, format: ConfigFormat) throws -> HugoConfig {
        let dictionary = try parse(content: content, format: format)
        // Use a placeholder URL for string-based parsing (not associated with a file)
        let placeholderURL = URL(fileURLWithPath: "/dev/null")
        return HugoConfig(from: dictionary, format: format, url: placeholderURL, rawContent: content,
                          orderedRootKeys: rootKeyOrder(of: content, format: format))
    }

    /// Document order of the root-level keys (CONFIG-SCHEMA-SPEC §2.7), captured before the
    /// config collapses into an unordered dictionary. YAML uses `Yams.compose` (ordered
    /// mapping nodes); TOML needs a line scan, since TOMLKit wraps toml++ whose tables are
    /// alphabetical `std::map`; JSON returns nil (its writer sorts anyway). Best-effort:
    /// `ConfigValueStore` reconciles the list, so a scan miss degrades to sorted.
    private func rootKeyOrder(of content: String, format: ConfigFormat) -> [String]? {
        switch format {
        case .toml:
            return tomlRootKeyOrder(content)
        case .yaml:
            guard let node = try? Yams.compose(yaml: content), case let .mapping(mapping) = node else {
                return nil
            }
            return mapping.compactMap { $0.key.string }
        case .json:
            return nil
        }
    }

    /// First-seen order of root-level TOML keys: bare `key = …` lines before
    /// any table header, plus the first path segment of `[table]` /
    /// `[[array]]` headers and dotted keys. Skips comments and the interior
    /// of multiline strings.
    private func tomlRootKeyOrder(_ content: String) -> [String] {
        var keys: [String] = []
        var seen = Set<String>()
        var multilineDelimiter: String?

        func record(_ rawKey: Substring) {
            let key = rawKey
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !key.isEmpty, seen.insert(key).inserted {
                keys.append(key)
            }
        }

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if let delimiter = multilineDelimiter {
                if line.contains(delimiter) { multilineDelimiter = nil }
                continue
            }
            if line.isEmpty || line.hasPrefix("#") { continue }

            if line.hasPrefix("[") {
                let name = line.drop(while: { $0 == "[" })
                let end = name.firstIndex(where: { $0 == "." || $0 == "]" }) ?? name.endIndex
                record(name[..<end])
            } else if let equals = line.firstIndex(of: "=") {
                let keyPart = line[..<equals]
                let dot = keyPart.firstIndex(of: ".") ?? keyPart.endIndex
                record(keyPart[..<dot])

                let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                for delimiter in ["\"\"\"", "'''"] where value.hasPrefix(delimiter) {
                    if !value.dropFirst(3).contains(delimiter) {
                        multilineDelimiter = delimiter
                    }
                }
            }
        }
        return keys
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

    /// Serialize a HugoConfig back to string. Sparse by design: a key is written iff it's
    /// present in `config.store`, never injected just because a computed accessor exists.
    /// Presence is structural, so no field-by-field checks are needed - it snapshots.
    func serialize(_ config: HugoConfig) throws -> String {
        // Menus are the one typed materialization outside the store; commit
        // them before snapshotting so a form-mode save reflects the latest
        // in-memory edits (single write path, CONFIG-SCHEMA-SPEC §2.9 item 5).
        config.commitMenus()
        let dictionary = config.store.snapshotRoot()
        return try serialize(dictionary: dictionary, format: config.sourceFormat, rootKeyOrder: config.store.orderedRootKeys)
    }

    private func serialize(dictionary: [String: Any], format: ConfigFormat, rootKeyOrder: [String]? = nil) throws -> String {
        switch format {
        case .toml:
            return try serializeToTOML(dictionary, rootKeyOrder: rootKeyOrder)
        case .yaml:
            return try serializeToYAML(dictionary)
        case .json:
            return try serializeToJSON(dictionary)
        }
    }

    /// Root-level key order is honored for TOML only (CONFIG-SCHEMA-SPEC §2.7):
    /// TOMLKit/Yams both preserve document order, but Victor's own TOML writer
    /// (`TOMLHelper`) sorts alphabetically by default, so it's the one writer
    /// that needs an explicit order hint. YAML/JSON writers are unchanged —
    /// best-effort only, per spec.
    private func serializeToTOML(_ dictionary: [String: Any], rootKeyOrder: [String]? = nil) throws -> String {
        return TOMLHelper.serializeToTOML(dictionary, rootKeyOrder: rootKeyOrder)
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
