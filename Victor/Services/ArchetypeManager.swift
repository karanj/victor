import Foundation

/// Service for managing Hugo archetypes (content templates)
/// Stateless aside from `private init()` — safe to hand across actor boundaries.
final class ArchetypeManager: @unchecked Sendable {
    static let shared = ArchetypeManager()

    private init() {}

    // MARK: - Loading

    /// Load all archetypes from a Hugo site's archetypes directory
    /// - Parameter siteURL: The root URL of the Hugo site
    /// - Returns: Array of Archetype objects
    /// `@MainActor`: reads `@MainActor`-isolated `Archetype` properties
    /// (`isDefault`, `name`) synchronously while sorting (WP3.5 Cluster 13).
    @MainActor
    func loadArchetypes(from siteURL: URL) async throws -> [Archetype] {
        let archetypesURL = siteURL.appendingPathComponent("archetypes")

        // Check if archetypes directory exists
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: archetypesURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return []
        }

        // Find all markdown files in archetypes/
        let contents = try FileManager.default.contentsOfDirectory(
            at: archetypesURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        let markdownFiles = contents.filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "md" || ext == "markdown"
        }

        // Parse each archetype
        var archetypes: [Archetype] = []
        for fileURL in markdownFiles {
            do {
                let archetype = try await parseArchetype(at: fileURL)
                archetypes.append(archetype)
            } catch {
                Logger.shared.error("Failed to parse archetype: \(fileURL.lastPathComponent)", error: error)
            }
        }

        // Sort: default first, then alphabetically
        archetypes.sort { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return archetypes
    }

    /// Parse a single archetype file
    /// - Parameter url: The archetype file URL
    /// - Returns: An Archetype instance
    /// `@MainActor`: constructs an `Archetype`, which is itself `@MainActor`-isolated
    /// (WP3.5 Cluster 13) — this method already only ever runs from `@MainActor` callers.
    @MainActor
    func parseArchetype(at url: URL) async throws -> Archetype {
        // Off-actor read (victor-tdt audit): see `DataFileParser.parseDataFile`'s
        // identical comment for why `readFileContentsOffActor` replaces `Task.detached`.
        let content = try await readFileContentsOffActor(at: url)

        let (frontmatter, body, format) = parseFrontmatterAndBody(content)

        return Archetype(
            url: url,
            frontmatterContent: frontmatter,
            bodyTemplate: body,
            frontmatterFormat: format
        )
    }

    /// Parse frontmatter and body from archetype content
    private func parseFrontmatterAndBody(_ content: String) -> (frontmatter: String, body: String, format: FrontmatterFormat) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Detect format and parse accordingly
        if trimmed.hasPrefix("---") {
            return parseYAMLFrontmatter(trimmed)
        } else if trimmed.hasPrefix("+++") {
            return parseTOMLFrontmatter(trimmed)
        } else if trimmed.hasPrefix("{") {
            return parseJSONFrontmatter(trimmed)
        }

        // No frontmatter detected - treat entire content as body
        return ("", content, .yaml)
    }

    private func parseYAMLFrontmatter(_ content: String) -> (String, String, FrontmatterFormat) {
        // Find the closing ---
        let lines = content.components(separatedBy: "\n")
        guard lines.count > 1, lines[0] == "---" else {
            return ("", content, .yaml)
        }

        var frontmatterEndIndex: Int?
        for (index, line) in lines.dropFirst().enumerated() {
            if line == "---" {
                frontmatterEndIndex = index + 1  // +1 because we dropped first
                break
            }
        }

        guard let endIndex = frontmatterEndIndex else {
            return ("", content, .yaml)
        }

        let frontmatterLines = Array(lines[1..<endIndex])
        let bodyLines = Array(lines[(endIndex + 1)...])

        let frontmatter = frontmatterLines.joined(separator: "\n")
        let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        return (frontmatter, body, .yaml)
    }

    private func parseTOMLFrontmatter(_ content: String) -> (String, String, FrontmatterFormat) {
        let lines = content.components(separatedBy: "\n")
        guard lines.count > 1, lines[0] == "+++" else {
            return ("", content, .toml)
        }

        var frontmatterEndIndex: Int?
        for (index, line) in lines.dropFirst().enumerated() {
            if line == "+++" {
                frontmatterEndIndex = index + 1
                break
            }
        }

        guard let endIndex = frontmatterEndIndex else {
            return ("", content, .toml)
        }

        let frontmatterLines = Array(lines[1..<endIndex])
        let bodyLines = Array(lines[(endIndex + 1)...])

        let frontmatter = frontmatterLines.joined(separator: "\n")
        let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        return (frontmatter, body, .toml)
    }

    private func parseJSONFrontmatter(_ content: String) -> (String, String, FrontmatterFormat) {
        // JSON frontmatter ends with a closing brace
        // This is a simplified parser - proper JSON parsing would be more complex
        var braceCount = 0
        var endIndex: String.Index?

        for (index, char) in content.enumerated() {
            if char == "{" {
                braceCount += 1
            } else if char == "}" {
                braceCount -= 1
                if braceCount == 0 {
                    endIndex = content.index(content.startIndex, offsetBy: index + 1)
                    break
                }
            }
        }

        guard let jsonEndIndex = endIndex else {
            return ("", content, .json)
        }

        let frontmatter = String(content[..<jsonEndIndex])
        let body = String(content[jsonEndIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)

        return (frontmatter, body, .json)
    }

    // MARK: - Content Creation

    /// Create a new content file from an archetype
    /// - Parameters:
    ///   - archetype: The archetype to use
    ///   - title: The title for the new content
    ///   - targetDirectory: The directory to create the file in
    ///   - filename: Optional custom filename (defaults to slugified title)
    /// - Returns: URL of the created file
    /// `@MainActor`: calls `archetype.processTemplate(title:)`, an instance
    /// method on the `@MainActor`-isolated `Archetype` (WP3.5 Cluster 13).
    @MainActor
    func createContent(
        from archetype: Archetype,
        title: String,
        in targetDirectory: URL,
        filename: String? = nil
    ) async throws -> URL {
        // Generate filename from title if not provided
        let slug = filename ?? slugify(title)
        let fileName = slug.hasSuffix(".md") ? slug : "\(slug).md"

        let fileURL = targetDirectory.appendingPathComponent(fileName)

        // Check if file already exists
        if FileManager.default.fileExists(atPath: fileURL.path) {
            throw ArchetypeError.fileAlreadyExists(fileURL)
        }

        // Process the archetype template
        let content = archetype.processTemplate(title: title)

        // Write the file
        try await Task.detached {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }.value

        return fileURL
    }

    /// Generate the default archetype content (used when no archetypes exist)
    func defaultArchetypeContent(title: String, date: Date = Date()) -> String {
        let dateString = date.formatted(Date.ISO8601FormatStyle.hugoArchetypeTimestamp)

        return """
        ---
        title: "\(title)"
        date: \(dateString)
        draft: true
        ---

        """
    }

    /// Convert a title to a URL-friendly slug
    private func slugify(_ title: String) -> String {
        let lowercased = title.lowercased()
        let alphanumeric = lowercased.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return alphanumeric.filter { !$0.isEmpty }.joined(separator: "-")
    }
}

// MARK: - Errors

enum ArchetypeError: LocalizedError {
    case fileAlreadyExists(URL)
    case invalidArchetype
    case directoryNotFound

    var errorDescription: String? {
        switch self {
        case .fileAlreadyExists(let url):
            return "A file already exists at: \(url.lastPathComponent)"
        case .invalidArchetype:
            return "Invalid archetype file"
        case .directoryNotFound:
            return "Target directory not found"
        }
    }
}
