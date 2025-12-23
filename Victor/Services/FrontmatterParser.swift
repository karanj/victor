import Foundation
import Yams
import TOMLKit

// MARK: - Frontmatter Errors

/// Errors that can occur during frontmatter parsing and serialization
enum FrontmatterError: LocalizedError {
    case yamlParsingFailed(String)
    case tomlParsingFailed(String)
    case jsonParsingFailed(String)
    case yamlSerializationFailed(String)
    case jsonSerializationFailed(String)

    var errorDescription: String? {
        switch self {
        case .yamlParsingFailed(let detail):
            return "Failed to parse YAML frontmatter: \(detail)"
        case .tomlParsingFailed(let detail):
            return "Failed to parse TOML frontmatter: \(detail)"
        case .jsonParsingFailed(let detail):
            return "Failed to parse JSON frontmatter: \(detail)"
        case .yamlSerializationFailed(let detail):
            return "Failed to serialize YAML frontmatter: \(detail)"
        case .jsonSerializationFailed(let detail):
            return "Failed to serialize JSON frontmatter: \(detail)"
        }
    }
}

/// Service for parsing and serializing Hugo frontmatter
/// Note: No @MainActor - parsing is CPU-intensive but doesn't require main thread
class FrontmatterParser {
    static let shared = FrontmatterParser()

    /// Cached date formatter for Hugo dates (avoids creating new formatter on each call)
    private static let hugoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private init() {}

    // MARK: - Parsing

    /// Parse content and extract frontmatter + markdown
    /// - Parameter content: The full file content including frontmatter and markdown
    /// - Returns: A tuple with optional frontmatter and the markdown content
    /// - Note: This method swallows parsing errors and returns frontmatter with rawContent only.
    ///         Use `parseContentThrowing(_:)` if you want to handle parsing errors explicitly.
    func parseContent(_ content: String) -> (frontmatter: Frontmatter?, markdown: String) {
        // Try to extract frontmatter
        guard let (rawFrontmatter, markdown, format) = extractFrontmatter(from: content) else {
            // No frontmatter found
            return (nil, content)
        }

        // Parse frontmatter based on format
        let frontmatter = parseFrontmatter(raw: rawFrontmatter, format: format)
        return (frontmatter, markdown)
    }

    /// Parse content and extract frontmatter + markdown (throwing variant)
    /// - Parameter content: The full file content including frontmatter and markdown
    /// - Returns: A tuple with optional frontmatter and the markdown content
    /// - Throws: `FrontmatterError` if parsing fails
    /// - Note: Use this method when you want to handle parsing errors explicitly and show them to users
    func parseContentThrowing(_ content: String) throws -> (frontmatter: Frontmatter?, markdown: String) {
        // Try to extract frontmatter
        guard let (rawFrontmatter, markdown, format) = extractFrontmatter(from: content) else {
            // No frontmatter found - not an error
            return (nil, content)
        }

        // Parse frontmatter based on format (throws on error)
        let frontmatter = try parseFrontmatterThrowing(raw: rawFrontmatter, format: format)
        return (frontmatter, markdown)
    }

    /// Extract frontmatter from content
    private func extractFrontmatter(from content: String) -> (raw: String, markdown: String, format: FrontmatterFormat)? {
        let lines = content.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return nil }

        let firstLine = lines[0]

        // Detect YAML (---)
        if firstLine.trimmingCharacters(in: .whitespaces) == "---" {
            return extractDelimitedFrontmatter(
                from: lines,
                delimiter: "---",
                format: .yaml,
                includeDelimiters: true
            )
        }

        // Detect TOML (+++)
        if firstLine.trimmingCharacters(in: .whitespaces) == "+++" {
            return extractDelimitedFrontmatter(
                from: lines,
                delimiter: "+++",
                format: .toml,
                includeDelimiters: true
            )
        }

        // Detect JSON ({)
        if firstLine.trimmingCharacters(in: .whitespaces).hasPrefix("{") {
            return extractJSONFrontmatter(from: content)
        }

        return nil
    }

    /// Extract YAML or TOML frontmatter with delimiters
    private func extractDelimitedFrontmatter(
        from lines: [String],
        delimiter: String,
        format: FrontmatterFormat,
        includeDelimiters: Bool
    ) -> (raw: String, markdown: String, format: FrontmatterFormat)? {
        guard lines.count >= 3 else { return nil }

        // Find closing delimiter
        var endIndex = -1
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == delimiter {
                endIndex = i
                break
            }
        }

        guard endIndex > 0 else { return nil }

        // Extract frontmatter content
        let frontmatterLines = Array(lines[1..<endIndex])
        let frontmatterContent = frontmatterLines.joined(separator: "\n")

        // Include delimiters in raw content
        let rawFrontmatter = includeDelimiters
            ? delimiter + "\n" + frontmatterContent + "\n" + delimiter
            : frontmatterContent

        // Extract markdown (everything after closing delimiter)
        let markdownLines = Array(lines[(endIndex + 1)...])
        let markdown = markdownLines.joined(separator: "\n")

        return (rawFrontmatter, markdown, format)
    }

    /// Extract JSON frontmatter
    private func extractJSONFrontmatter(from content: String) -> (raw: String, markdown: String, format: FrontmatterFormat)? {
        // Find matching closing brace
        var braceCount = 0
        var endIndex = -1

        for (index, char) in content.enumerated() {
            if char == "{" {
                braceCount += 1
            } else if char == "}" {
                braceCount -= 1
                if braceCount == 0 {
                    endIndex = index
                    break
                }
            }
        }

        guard endIndex > 0 else { return nil }

        let rawFrontmatter = String(content[...content.index(content.startIndex, offsetBy: endIndex)])
        let markdown = String(content[content.index(content.startIndex, offsetBy: endIndex + 1)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (rawFrontmatter, markdown, .json)
    }

    /// Parse frontmatter into structured model (non-throwing, logs errors)
    private func parseFrontmatter(raw: String, format: FrontmatterFormat) -> Frontmatter {
        let frontmatter = Frontmatter(rawContent: raw, format: format)

        // Extract content without delimiters for parsing
        let contentToParse = stripDelimiters(from: raw, format: format)

        // Try to parse, but don't fail if parsing errors occur
        // This preserves backwards compatibility where parsing errors were silent
        do {
            switch format {
            case .yaml:
                try parseYAML(contentToParse, into: frontmatter)
            case .toml:
                try parseTOML(contentToParse, into: frontmatter)
            case .json:
                try parseJSON(raw, into: frontmatter)
            }
        } catch {
            // Log the error for debugging, but return the frontmatter with rawContent
            // This allows users to still see/edit the raw frontmatter even if parsing fails
            print("⚠️ Frontmatter parsing error: \(error.localizedDescription)")
        }

        return frontmatter
    }

    /// Parse frontmatter into structured model (throwing variant)
    private func parseFrontmatterThrowing(raw: String, format: FrontmatterFormat) throws -> Frontmatter {
        let frontmatter = Frontmatter(rawContent: raw, format: format)

        // Extract content without delimiters for parsing
        let contentToParse = stripDelimiters(from: raw, format: format)

        // Parse and propagate errors
        switch format {
        case .yaml:
            try parseYAML(contentToParse, into: frontmatter)
        case .toml:
            try parseTOML(contentToParse, into: frontmatter)
        case .json:
            try parseJSON(raw, into: frontmatter)
        }

        return frontmatter
    }

    /// Strip delimiters from frontmatter content
    private func stripDelimiters(from content: String, format: FrontmatterFormat) -> String {
        switch format {
        case .yaml:
            return content
                .replacingOccurrences(of: "^---\n", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\n---$", with: "", options: .regularExpression)
        case .toml:
            return content
                .replacingOccurrences(of: "^\\+\\+\\+\n", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\n\\+\\+\\+$", with: "", options: .regularExpression)
        case .json:
            return content // JSON doesn't have delimiters separate from content
        }
    }

    // MARK: - Format-Specific Parsing

    /// Parse YAML frontmatter
    private func parseYAML(_ content: String, into frontmatter: Frontmatter) throws {
        do {
            guard let yaml = try Yams.load(yaml: content) as? [String: Any] else {
                throw FrontmatterError.yamlParsingFailed("Could not parse as dictionary")
            }

            extractCommonFields(from: yaml, into: frontmatter)
        } catch let error as FrontmatterError {
            throw error
        } catch {
            throw FrontmatterError.yamlParsingFailed(error.localizedDescription)
        }
    }

    /// Parse TOML frontmatter
    private func parseTOML(_ content: String, into frontmatter: Frontmatter) throws {
        do {
            let table = try TOMLTable(string: content)

            // Extract common fields directly from table
            if let title = table["title"] as? String {
                frontmatter.title = title
            }
            if let dateString = table["date"] as? String {
                frontmatter.date = parseDate(dateString)
            }
            if let draft = table["draft"] as? Bool {
                frontmatter.draft = draft
            }
            if let tags = table["tags"] as? [String] {
                frontmatter.tags = tags
            }
            if let categories = table["categories"] as? [String] {
                frontmatter.categories = categories
            }
            if let description = table["description"] as? String {
                frontmatter.description = description
            }

            // Store custom fields (all other keys)
            let knownKeys = Set(["title", "date", "draft", "tags", "categories", "description"])
            var customFields: [String: Any] = [:]
            for key in table.keys where !knownKeys.contains(key) {
                customFields[key] = table[key]
            }
            frontmatter.customFields = customFields
        } catch {
            throw FrontmatterError.tomlParsingFailed(error.localizedDescription)
        }
    }

    /// Parse JSON frontmatter
    private func parseJSON(_ content: String, into frontmatter: Frontmatter) throws {
        guard let data = content.data(using: .utf8) else {
            throw FrontmatterError.jsonParsingFailed("Could not convert to UTF-8 data")
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw FrontmatterError.jsonParsingFailed("Could not parse as dictionary")
            }

            extractCommonFields(from: json, into: frontmatter)
        } catch let error as FrontmatterError {
            throw error
        } catch {
            throw FrontmatterError.jsonParsingFailed(error.localizedDescription)
        }
    }

    /// Extract common Hugo fields from dictionary
    private func extractCommonFields(from dict: [String: Any], into frontmatter: Frontmatter) {
        // Title
        if let title = dict["title"] as? String {
            frontmatter.title = title
        }

        // Date (can be String or Date from YAML parser)
        if let date = dict["date"] as? Date {
            frontmatter.date = date
        } else if let dateString = dict["date"] as? String {
            frontmatter.date = parseDate(dateString)
        }

        // Draft
        if let draft = dict["draft"] as? Bool {
            frontmatter.draft = draft
        }

        // Tags
        if let tags = dict["tags"] as? [String] {
            frontmatter.tags = tags
        } else if let tags = dict["tags"] as? [Any] {
            frontmatter.tags = tags.compactMap { $0 as? String }
        }

        // Categories
        if let categories = dict["categories"] as? [String] {
            frontmatter.categories = categories
        } else if let categories = dict["categories"] as? [Any] {
            frontmatter.categories = categories.compactMap { $0 as? String }
        }

        // Description
        if let description = dict["description"] as? String {
            frontmatter.description = description
        }

        // Store custom fields (everything except known fields)
        let knownKeys = Set(["title", "date", "draft", "tags", "categories", "description"])
        let customFields = dict.filter { !knownKeys.contains($0.key) }
        frontmatter.customFields = customFields
    }

    /// Parse date string (supports multiple Hugo date formats)
    private func parseDate(_ dateString: String) -> Date? {
        let formatters = [
            "yyyy-MM-dd'T'HH:mm:ssZ",      // ISO 8601 with timezone
            "yyyy-MM-dd'T'HH:mm:ss",       // ISO 8601 without timezone
            "yyyy-MM-dd HH:mm:ss Z",       // Hugo default
            "yyyy-MM-dd",                  // Date only
        ]

        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: dateString) {
                return date
            }
        }

        // Try ISO8601DateFormatter as fallback
        if let date = ISO8601DateFormatter().date(from: dateString) {
            return date
        }

        return nil
    }

    // MARK: - Serialization

    /// Serialize frontmatter back to original format
    /// - Parameter frontmatter: The frontmatter to serialize
    /// - Returns: Serialized frontmatter string with delimiters
    /// - Note: This method swallows serialization errors and falls back to rawContent.
    ///         Use `serializeFrontmatterThrowing(_:)` if you want to handle errors explicitly.
    func serializeFrontmatter(_ frontmatter: Frontmatter) -> String {
        switch frontmatter.format {
        case .yaml:
            return serializeYAML(frontmatter)
        case .toml:
            return serializeTOML(frontmatter)
        case .json:
            return serializeJSON(frontmatter)
        }
    }

    /// Serialize frontmatter back to original format (throwing variant)
    /// - Parameter frontmatter: The frontmatter to serialize
    /// - Returns: Serialized frontmatter string with delimiters
    /// - Throws: `FrontmatterError` if serialization fails
    /// - Note: Use this method when you want to handle serialization errors explicitly
    func serializeFrontmatterThrowing(_ frontmatter: Frontmatter) throws -> String {
        switch frontmatter.format {
        case .yaml:
            return try serializeYAMLThrowing(frontmatter)
        case .toml:
            return serializeTOML(frontmatter) // TOML doesn't currently throw
        case .json:
            return try serializeJSONThrowing(frontmatter)
        }
    }

    /// Serialize to YAML format (non-throwing, falls back to rawContent)
    private func serializeYAML(_ frontmatter: Frontmatter) -> String {
        var dict: [String: Any] = frontmatter.customFields

        // Add common fields
        if let title = frontmatter.title {
            dict["title"] = title
        }
        if let date = frontmatter.date {
            dict["date"] = formatDate(date)
        }
        if let draft = frontmatter.draft {
            dict["draft"] = draft
        }
        if let tags = frontmatter.tags, !tags.isEmpty {
            dict["tags"] = tags
        }
        if let categories = frontmatter.categories, !categories.isEmpty {
            dict["categories"] = categories
        }
        if let description = frontmatter.description {
            dict["description"] = description
        }

        do {
            let yaml = try Yams.dump(object: dict)
            return "---\n\(yaml)---"
        } catch {
            // Log the error with a clear warning
            print("⚠️ YAML serialization error: \(error.localizedDescription)")
            print("   Falling back to raw frontmatter content")
            return frontmatter.rawContent
        }
    }

    /// Serialize to YAML format (throwing variant)
    private func serializeYAMLThrowing(_ frontmatter: Frontmatter) throws -> String {
        var dict: [String: Any] = frontmatter.customFields

        // Add common fields
        if let title = frontmatter.title {
            dict["title"] = title
        }
        if let date = frontmatter.date {
            dict["date"] = formatDate(date)
        }
        if let draft = frontmatter.draft {
            dict["draft"] = draft
        }
        if let tags = frontmatter.tags, !tags.isEmpty {
            dict["tags"] = tags
        }
        if let categories = frontmatter.categories, !categories.isEmpty {
            dict["categories"] = categories
        }
        if let description = frontmatter.description {
            dict["description"] = description
        }

        do {
            let yaml = try Yams.dump(object: dict)
            return "---\n\(yaml)---"
        } catch {
            throw FrontmatterError.yamlSerializationFailed(error.localizedDescription)
        }
    }

    /// Serialize to TOML format
    private func serializeTOML(_ frontmatter: Frontmatter) -> String {
        let tomlTable = TOMLTable()

        // Add common fields (order matters for readability)
        if let title = frontmatter.title {
            tomlTable["title"] = title
        }
        if let date = frontmatter.date {
            tomlTable["date"] = formatDate(date)
        }
        if let draft = frontmatter.draft {
            tomlTable["draft"] = draft
        }
        if let description = frontmatter.description {
            tomlTable["description"] = description
        }
        if let tags = frontmatter.tags, !tags.isEmpty {
            tomlTable["tags"] = tags
        }
        if let categories = frontmatter.categories, !categories.isEmpty {
            tomlTable["categories"] = categories
        }

        // Add custom fields (only basic types supported by TOML)
        for (key, value) in frontmatter.customFields {
            // Only add values that are TOMLValueConvertible
            if let stringValue = value as? String {
                tomlTable[key] = stringValue
            } else if let intValue = value as? Int {
                tomlTable[key] = intValue
            } else if let doubleValue = value as? Double {
                tomlTable[key] = doubleValue
            } else if let boolValue = value as? Bool {
                tomlTable[key] = boolValue
            } else if let arrayValue = value as? [String] {
                tomlTable[key] = arrayValue
            }
            // Skip other types for now
        }

        // Convert to string (TOMLTable has built-in toString)
        let tomlString = String(describing: tomlTable)
        return "+++\n\(tomlString)+++"
    }

    /// Serialize to JSON format (non-throwing, falls back to rawContent)
    private func serializeJSON(_ frontmatter: Frontmatter) -> String {
        var dict: [String: Any] = frontmatter.customFields

        // Add common fields
        if let title = frontmatter.title {
            dict["title"] = title
        }
        if let date = frontmatter.date {
            dict["date"] = formatDate(date)
        }
        if let draft = frontmatter.draft {
            dict["draft"] = draft
        }
        if let tags = frontmatter.tags, !tags.isEmpty {
            dict["tags"] = tags
        }
        if let categories = frontmatter.categories, !categories.isEmpty {
            dict["categories"] = categories
        }
        if let description = frontmatter.description {
            dict["description"] = description
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        } catch {
            // Log the error with a clear warning
            print("⚠️ JSON serialization error: \(error.localizedDescription)")
            print("   Falling back to raw frontmatter content")
        }

        return frontmatter.rawContent
    }

    /// Serialize to JSON format (throwing variant)
    private func serializeJSONThrowing(_ frontmatter: Frontmatter) throws -> String {
        var dict: [String: Any] = frontmatter.customFields

        // Add common fields
        if let title = frontmatter.title {
            dict["title"] = title
        }
        if let date = frontmatter.date {
            dict["date"] = formatDate(date)
        }
        if let draft = frontmatter.draft {
            dict["draft"] = draft
        }
        if let tags = frontmatter.tags, !tags.isEmpty {
            dict["tags"] = tags
        }
        if let categories = frontmatter.categories, !categories.isEmpty {
            dict["categories"] = categories
        }
        if let description = frontmatter.description {
            dict["description"] = description
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                throw FrontmatterError.jsonSerializationFailed("Could not convert data to UTF-8 string")
            }
            return jsonString
        } catch let error as FrontmatterError {
            throw error
        } catch {
            throw FrontmatterError.jsonSerializationFailed(error.localizedDescription)
        }
    }

    /// Format date for Hugo (uses simple date format: yyyy-MM-dd)
    private func formatDate(_ date: Date) -> String {
        return Self.hugoDateFormatter.string(from: date)
    }
}
