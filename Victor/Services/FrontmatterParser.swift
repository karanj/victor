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

    /// Known fields that are handled explicitly (not stored in customFields)
    private static let knownFields: Set<String> = [
        // Essential
        "title", "date", "draft", "description", "tags", "categories",
        // Publishing
        "publishDate", "expiryDate", "lastmod", "weight",
        // URL
        "slug", "url", "aliases",
        // SEO
        "keywords", "summary", "linkTitle",
        // Layout
        "type", "layout",
        // Flags
        "headless", "isCJKLanguage", "markup", "translationKey",
        // Complex
        "menus", "menu", "build", "sitemap", "outputs", "resources", "cascade",
        // Params
        "params"
    ]

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
            Logger.shared.error("FrontmatterParser: parsing error", error: error)
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

            extractAllFields(from: yaml, into: frontmatter)
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

            // Convert TOML table to dictionary for unified parsing
            var dict: [String: Any] = [:]
            for key in table.keys {
                dict[key] = convertTOMLValue(table[key])
            }

            extractAllFields(from: dict, into: frontmatter)
        } catch {
            throw FrontmatterError.tomlParsingFailed(error.localizedDescription)
        }
    }

    /// Convert TOML value to Swift type
    private func convertTOMLValue(_ value: Any?) -> Any? {
        guard let value = value else { return nil }

        if let table = value as? TOMLTable {
            var dict: [String: Any] = [:]
            for key in table.keys {
                if let converted = convertTOMLValue(table[key]) {
                    dict[key] = converted
                }
            }
            return dict
        } else if let array = value as? [Any] {
            return array.compactMap { convertTOMLValue($0) }
        } else {
            return value
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

            extractAllFields(from: json, into: frontmatter)
        } catch let error as FrontmatterError {
            throw error
        } catch {
            throw FrontmatterError.jsonParsingFailed(error.localizedDescription)
        }
    }

    // MARK: - Field Extraction

    /// Extract all Hugo fields from dictionary
    private func extractAllFields(from dict: [String: Any], into frontmatter: Frontmatter) {
        // Essential fields
        extractEssentialFields(from: dict, into: frontmatter)

        // Publishing fields
        extractPublishingFields(from: dict, into: frontmatter)

        // URL fields
        extractURLFields(from: dict, into: frontmatter)

        // SEO fields
        extractSEOFields(from: dict, into: frontmatter)

        // Layout fields
        extractLayoutFields(from: dict, into: frontmatter)

        // Flag fields
        extractFlagFields(from: dict, into: frontmatter)

        // Complex fields
        extractMenus(from: dict, into: frontmatter)
        extractBuildOptions(from: dict, into: frontmatter)
        extractSitemap(from: dict, into: frontmatter)
        extractOutputs(from: dict, into: frontmatter)
        extractResources(from: dict, into: frontmatter)
        extractCascade(from: dict, into: frontmatter)
        extractParams(from: dict, into: frontmatter)

        // Store unknown fields as customFields
        let customFields = dict.filter { !Self.knownFields.contains($0.key) }
        frontmatter.customFields = customFields
    }

    /// Extract essential fields (title, date, draft, description, tags, categories)
    private func extractEssentialFields(from dict: [String: Any], into frontmatter: Frontmatter) {
        frontmatter.title = dict["title"] as? String

        // Date (can be String or Date from YAML parser)
        if let date = dict["date"] as? Date {
            frontmatter.date = date
        } else if let dateString = dict["date"] as? String {
            frontmatter.date = parseDate(dateString)
        }

        frontmatter.draft = dict["draft"] as? Bool

        frontmatter.description = dict["description"] as? String

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
    }

    /// Extract publishing fields (publishDate, expiryDate, lastmod, weight)
    private func extractPublishingFields(from dict: [String: Any], into frontmatter: Frontmatter) {
        // Publish Date
        if let date = dict["publishDate"] as? Date {
            frontmatter.publishDate = date
        } else if let dateString = dict["publishDate"] as? String {
            frontmatter.publishDate = parseDate(dateString)
        }

        // Expiry Date
        if let date = dict["expiryDate"] as? Date {
            frontmatter.expiryDate = date
        } else if let dateString = dict["expiryDate"] as? String {
            frontmatter.expiryDate = parseDate(dateString)
        }

        // Last Modified
        if let date = dict["lastmod"] as? Date {
            frontmatter.lastmod = date
        } else if let dateString = dict["lastmod"] as? String {
            frontmatter.lastmod = parseDate(dateString)
        }

        // Weight
        frontmatter.weight = dict["weight"] as? Int
    }

    /// Extract URL fields (slug, url, aliases)
    private func extractURLFields(from dict: [String: Any], into frontmatter: Frontmatter) {
        frontmatter.slug = dict["slug"] as? String
        frontmatter.url = dict["url"] as? String

        // Aliases
        if let aliases = dict["aliases"] as? [String] {
            frontmatter.aliases = aliases
        } else if let aliases = dict["aliases"] as? [Any] {
            frontmatter.aliases = aliases.compactMap { $0 as? String }
        }
    }

    /// Extract SEO fields (keywords, summary, linkTitle)
    private func extractSEOFields(from dict: [String: Any], into frontmatter: Frontmatter) {
        // Keywords
        if let keywords = dict["keywords"] as? [String] {
            frontmatter.keywords = keywords
        } else if let keywords = dict["keywords"] as? [Any] {
            frontmatter.keywords = keywords.compactMap { $0 as? String }
        }

        frontmatter.summary = dict["summary"] as? String
        frontmatter.linkTitle = dict["linkTitle"] as? String
    }

    /// Extract layout fields (type, layout)
    private func extractLayoutFields(from dict: [String: Any], into frontmatter: Frontmatter) {
        frontmatter.type = dict["type"] as? String
        frontmatter.layout = dict["layout"] as? String
    }

    /// Extract flag fields (headless, isCJKLanguage, markup, translationKey)
    private func extractFlagFields(from dict: [String: Any], into frontmatter: Frontmatter) {
        frontmatter.headless = dict["headless"] as? Bool
        frontmatter.isCJKLanguage = dict["isCJKLanguage"] as? Bool
        frontmatter.markup = dict["markup"] as? String
        frontmatter.translationKey = dict["translationKey"] as? String
    }

    /// Extract menu configuration
    private func extractMenus(from dict: [String: Any], into frontmatter: Frontmatter) {
        // Hugo supports both "menu" and "menus" keys
        let menuData = dict["menus"] ?? dict["menu"]

        guard let menuData = menuData else { return }

        var entries: [MenuEntry] = []

        // Simple string format: menu: "main"
        if let menuName = menuData as? String {
            entries.append(MenuEntry(menuName: menuName))
        }
        // Array format: menu: ["main", "footer"]
        else if let menuNames = menuData as? [String] {
            for name in menuNames {
                entries.append(MenuEntry(menuName: name))
            }
        }
        // Map format: menu: main: { weight: 10, ... }
        else if let menuMap = menuData as? [String: Any] {
            for (menuName, config) in menuMap {
                if let configDict = config as? [String: Any] {
                    let entry = MenuEntry(
                        menuName: menuName,
                        name: configDict["name"] as? String,
                        weight: configDict["weight"] as? Int,
                        parent: configDict["parent"] as? String,
                        identifier: configDict["identifier"] as? String,
                        pre: configDict["pre"] as? String,
                        post: configDict["post"] as? String,
                        title: configDict["title"] as? String,
                        params: (configDict["params"] as? [String: String]) ?? [:]
                    )
                    entries.append(entry)
                } else {
                    // Simple entry without config
                    entries.append(MenuEntry(menuName: menuName))
                }
            }
        }

        frontmatter.menus = entries
    }

    /// Extract build options
    private func extractBuildOptions(from dict: [String: Any], into frontmatter: Frontmatter) {
        guard let buildDict = dict["build"] as? [String: Any] else { return }

        var build = BuildOptions()

        if let listString = buildDict["list"] as? String,
           let list = BuildOptions.ListOption(rawValue: listString) {
            build.list = list
        }

        if let renderString = buildDict["render"] as? String,
           let render = BuildOptions.RenderOption(rawValue: renderString) {
            build.render = render
        }

        if let publishResources = buildDict["publishResources"] as? Bool {
            build.publishResources = publishResources
        }

        frontmatter.build = build
    }

    /// Extract sitemap configuration
    private func extractSitemap(from dict: [String: Any], into frontmatter: Frontmatter) {
        guard let sitemapDict = dict["sitemap"] as? [String: Any] else { return }

        var sitemap = SitemapConfig()

        if let freqString = sitemapDict["changefreq"] as? String,
           let freq = SitemapConfig.ChangeFreq(rawValue: freqString) {
            sitemap.changefreq = freq
        }

        if let priority = sitemapDict["priority"] as? Double {
            sitemap.priority = priority
        } else if let priority = sitemapDict["priority"] as? Int {
            sitemap.priority = Double(priority)
        }

        if let disable = sitemapDict["disable"] as? Bool {
            sitemap.disable = disable
        }

        frontmatter.sitemap = sitemap
    }

    /// Extract output formats
    private func extractOutputs(from dict: [String: Any], into frontmatter: Frontmatter) {
        if let outputs = dict["outputs"] as? [String] {
            frontmatter.outputs = outputs
        } else if let outputs = dict["outputs"] as? [Any] {
            frontmatter.outputs = outputs.compactMap { $0 as? String }
        }
    }

    /// Extract page resources
    private func extractResources(from dict: [String: Any], into frontmatter: Frontmatter) {
        guard let resourcesArray = dict["resources"] as? [[String: Any]] else { return }

        var resources: [ResourceConfig] = []

        for resourceDict in resourcesArray {
            guard let src = resourceDict["src"] as? String else { continue }

            let resource = ResourceConfig(
                src: src,
                name: resourceDict["name"] as? String,
                title: resourceDict["title"] as? String,
                params: (resourceDict["params"] as? [String: String]) ?? [:]
            )
            resources.append(resource)
        }

        frontmatter.resources = resources
    }

    /// Extract cascade configuration
    private func extractCascade(from dict: [String: Any], into frontmatter: Frontmatter) {
        guard let cascadeData = dict["cascade"] else { return }

        var entries: [CascadeEntry] = []

        // Single cascade entry (map)
        if let cascadeDict = cascadeData as? [String: Any] {
            let entry = parseCascadeEntry(cascadeDict)
            entries.append(entry)
        }
        // Multiple cascade entries (array)
        else if let cascadeArray = cascadeData as? [[String: Any]] {
            for cascadeDict in cascadeArray {
                let entry = parseCascadeEntry(cascadeDict)
                entries.append(entry)
            }
        }

        frontmatter.cascade = entries
    }

    /// Parse a single cascade entry
    private func parseCascadeEntry(_ dict: [String: Any]) -> CascadeEntry {
        var target: CascadeTarget?

        if let targetDict = dict["target"] as? [String: Any] {
            target = CascadeTarget(
                path: targetDict["path"] as? String,
                kind: targetDict["kind"] as? String,
                lang: targetDict["lang"] as? String,
                environment: targetDict["environment"] as? String
            )
        }

        // Values are everything except "target"
        let values = dict.filter { $0.key != "target" }

        return CascadeEntry(values: values, target: target)
    }

    /// Extract params (custom parameters in params section)
    private func extractParams(from dict: [String: Any], into frontmatter: Frontmatter) {
        if let params = dict["params"] as? [String: Any] {
            frontmatter.params = params
        }
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
            formatter.locale = Locale(identifier: "en_US_POSIX")
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

    /// Build dictionary from frontmatter for serialization
    private func buildSerializationDict(_ frontmatter: Frontmatter) -> [String: Any] {
        var dict: [String: Any] = frontmatter.customFields

        // Essential fields
        if let title = frontmatter.title {
            dict["title"] = title
        }
        if let date = frontmatter.date {
            dict["date"] = formatDate(date)
        }
        if let draft = frontmatter.draft {
            dict["draft"] = draft
        }
        if let description = frontmatter.description {
            dict["description"] = description
        }
        if let tags = frontmatter.tags, !tags.isEmpty {
            dict["tags"] = tags
        }
        if let categories = frontmatter.categories, !categories.isEmpty {
            dict["categories"] = categories
        }

        // Publishing fields
        if let publishDate = frontmatter.publishDate {
            dict["publishDate"] = formatDate(publishDate)
        }
        if let expiryDate = frontmatter.expiryDate {
            dict["expiryDate"] = formatDate(expiryDate)
        }
        if let lastmod = frontmatter.lastmod {
            dict["lastmod"] = formatDate(lastmod)
        }
        if let weight = frontmatter.weight {
            dict["weight"] = weight
        }

        // URL fields
        if let slug = frontmatter.slug {
            dict["slug"] = slug
        }
        if let url = frontmatter.url {
            dict["url"] = url
        }
        if let aliases = frontmatter.aliases, !aliases.isEmpty {
            dict["aliases"] = aliases
        }

        // SEO fields
        if let keywords = frontmatter.keywords, !keywords.isEmpty {
            dict["keywords"] = keywords
        }
        if let summary = frontmatter.summary {
            dict["summary"] = summary
        }
        if let linkTitle = frontmatter.linkTitle {
            dict["linkTitle"] = linkTitle
        }

        // Layout fields
        if let type = frontmatter.type {
            dict["type"] = type
        }
        if let layout = frontmatter.layout {
            dict["layout"] = layout
        }

        // Flags
        if let headless = frontmatter.headless {
            dict["headless"] = headless
        }
        if let isCJKLanguage = frontmatter.isCJKLanguage {
            dict["isCJKLanguage"] = isCJKLanguage
        }
        if let markup = frontmatter.markup {
            dict["markup"] = markup
        }
        if let translationKey = frontmatter.translationKey {
            dict["translationKey"] = translationKey
        }

        // Complex fields
        if !frontmatter.menus.isEmpty {
            dict["menus"] = serializeMenus(frontmatter.menus)
        }
        if let build = frontmatter.build, !build.isDefault {
            dict["build"] = serializeBuildOptions(build)
        }
        if let sitemap = frontmatter.sitemap, !sitemap.isEmpty {
            dict["sitemap"] = serializeSitemap(sitemap)
        }
        if let outputs = frontmatter.outputs, !outputs.isEmpty {
            dict["outputs"] = outputs
        }
        if !frontmatter.resources.isEmpty {
            dict["resources"] = serializeResources(frontmatter.resources)
        }
        if !frontmatter.cascade.isEmpty {
            dict["cascade"] = serializeCascade(frontmatter.cascade)
        }
        if !frontmatter.params.isEmpty {
            dict["params"] = frontmatter.params
        }

        return dict
    }

    /// Serialize menus to dictionary
    private func serializeMenus(_ menus: [MenuEntry]) -> [String: Any] {
        var result: [String: Any] = [:]

        for menu in menus {
            var menuDict: [String: Any] = [:]

            if let name = menu.name {
                menuDict["name"] = name
            }
            if let weight = menu.weight {
                menuDict["weight"] = weight
            }
            if let parent = menu.parent {
                menuDict["parent"] = parent
            }
            if let identifier = menu.identifier {
                menuDict["identifier"] = identifier
            }
            if let pre = menu.pre {
                menuDict["pre"] = pre
            }
            if let post = menu.post {
                menuDict["post"] = post
            }
            if let title = menu.title {
                menuDict["title"] = title
            }
            if !menu.params.isEmpty {
                menuDict["params"] = menu.params
            }

            // If no properties, store as empty dict
            result[menu.menuName] = menuDict.isEmpty ? [:] : menuDict
        }

        return result
    }

    /// Serialize build options to dictionary
    private func serializeBuildOptions(_ build: BuildOptions) -> [String: Any] {
        var dict: [String: Any] = [:]

        if build.list != .always {
            dict["list"] = build.list.rawValue
        }
        if build.render != .always {
            dict["render"] = build.render.rawValue
        }
        if !build.publishResources {
            dict["publishResources"] = build.publishResources
        }

        return dict
    }

    /// Serialize sitemap config to dictionary
    private func serializeSitemap(_ sitemap: SitemapConfig) -> [String: Any] {
        var dict: [String: Any] = [:]

        if let changefreq = sitemap.changefreq {
            dict["changefreq"] = changefreq.rawValue
        }
        if let priority = sitemap.priority {
            dict["priority"] = priority
        }
        if sitemap.disable {
            dict["disable"] = sitemap.disable
        }

        return dict
    }

    /// Serialize resources to array of dictionaries
    private func serializeResources(_ resources: [ResourceConfig]) -> [[String: Any]] {
        return resources.map { resource in
            var dict: [String: Any] = ["src": resource.src]

            if let name = resource.name {
                dict["name"] = name
            }
            if let title = resource.title {
                dict["title"] = title
            }
            if !resource.params.isEmpty {
                dict["params"] = resource.params
            }

            return dict
        }
    }

    /// Serialize cascade entries to array
    private func serializeCascade(_ cascade: [CascadeEntry]) -> [[String: Any]] {
        return cascade.map { entry in
            var dict = entry.values

            if let target = entry.target, !target.isEmpty {
                var targetDict: [String: Any] = [:]
                if let path = target.path {
                    targetDict["path"] = path
                }
                if let kind = target.kind {
                    targetDict["kind"] = kind
                }
                if let lang = target.lang {
                    targetDict["lang"] = lang
                }
                if let environment = target.environment {
                    targetDict["environment"] = environment
                }
                dict["target"] = targetDict
            }

            return dict
        }
    }

    /// Serialize to YAML format (non-throwing, falls back to rawContent)
    private func serializeYAML(_ frontmatter: Frontmatter) -> String {
        let dict = buildSerializationDict(frontmatter)

        do {
            let yaml = try Yams.dump(object: dict)
            return "---\n\(yaml)---"
        } catch {
            Logger.shared.error("FrontmatterParser: YAML serialization error", error: error)
            return frontmatter.rawContent
        }
    }

    /// Serialize to YAML format (throwing variant)
    private func serializeYAMLThrowing(_ frontmatter: Frontmatter) throws -> String {
        let dict = buildSerializationDict(frontmatter)

        do {
            let yaml = try Yams.dump(object: dict)
            return "---\n\(yaml)---"
        } catch {
            throw FrontmatterError.yamlSerializationFailed(error.localizedDescription)
        }
    }

    /// Serialize to TOML format
    private func serializeTOML(_ frontmatter: Frontmatter) -> String {
        let dict = buildSerializationDict(frontmatter)
        let tomlTable = TOMLTable()

        // Convert dictionary to TOML table
        for (key, value) in dict {
            addToTOMLTable(key: key, value: value, table: tomlTable)
        }

        let tomlString = String(describing: tomlTable)
        return "+++\n\(tomlString)+++"
    }

    /// Add a value to TOML table
    private func addToTOMLTable(key: String, value: Any, table: TOMLTable) {
        if let stringValue = value as? String {
            table[key] = stringValue
        } else if let intValue = value as? Int {
            table[key] = intValue
        } else if let doubleValue = value as? Double {
            table[key] = doubleValue
        } else if let boolValue = value as? Bool {
            table[key] = boolValue
        } else if let arrayValue = value as? [String] {
            table[key] = arrayValue
        } else if let dictValue = value as? [String: Any] {
            let subTable = TOMLTable()
            for (subKey, subValue) in dictValue {
                addToTOMLTable(key: subKey, value: subValue, table: subTable)
            }
            table[key] = subTable
        }
        // Skip other types
    }

    /// Serialize to JSON format (non-throwing, falls back to rawContent)
    private func serializeJSON(_ frontmatter: Frontmatter) -> String {
        let dict = buildSerializationDict(frontmatter)

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        } catch {
            Logger.shared.error("FrontmatterParser: JSON serialization error", error: error)
        }

        return frontmatter.rawContent
    }

    /// Serialize to JSON format (throwing variant)
    private func serializeJSONThrowing(_ frontmatter: Frontmatter) throws -> String {
        let dict = buildSerializationDict(frontmatter)

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
