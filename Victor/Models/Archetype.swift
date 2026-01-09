import Foundation

/// Represents a Hugo archetype (content template)
/// Archetypes are stored in the archetypes/ directory and define templates
/// for new content files with frontmatter and body placeholders.
@Observable
class Archetype: Identifiable, Hashable {
    let id: UUID
    let url: URL

    /// The raw frontmatter content (YAML/TOML/JSON)
    var frontmatterContent: String

    /// The body template content (may contain Go template variables)
    var bodyTemplate: String

    /// The detected frontmatter format
    var frontmatterFormat: FrontmatterFormat

    /// File name without extension
    var name: String {
        url.deletingPathExtension().lastPathComponent
    }

    /// Full file name
    var fileName: String {
        url.lastPathComponent
    }

    /// Display name (capitalized, spaces added)
    var displayName: String {
        name.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    /// Whether this is the default archetype
    var isDefault: Bool {
        name.lowercased() == "default"
    }

    /// Content type this archetype is for (e.g., "posts", "pages")
    /// Derived from the file name
    var contentType: String {
        name
    }

    init(url: URL, frontmatterContent: String, bodyTemplate: String, frontmatterFormat: FrontmatterFormat) {
        self.id = UUID()
        self.url = url
        self.frontmatterContent = frontmatterContent
        self.bodyTemplate = bodyTemplate
        self.frontmatterFormat = frontmatterFormat
    }

    // MARK: - Template Processing

    /// Process the archetype to generate content for a new file
    /// - Parameters:
    ///   - title: The title for the new content
    ///   - date: The date for the new content
    ///   - additionalParams: Additional template parameters
    /// - Returns: The processed content string
    func processTemplate(title: String, date: Date = Date(), additionalParams: [String: String] = [:]) -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let dateString = dateFormatter.string(from: date)

        // Process frontmatter
        var processedFrontmatter = frontmatterContent
            .replacingOccurrences(of: "{{ .Title }}", with: title)
            .replacingOccurrences(of: "{{.Title}}", with: title)
            .replacingOccurrences(of: "{{ .Date }}", with: dateString)
            .replacingOccurrences(of: "{{.Date}}", with: dateString)

        // Process body
        var processedBody = bodyTemplate
            .replacingOccurrences(of: "{{ .Title }}", with: title)
            .replacingOccurrences(of: "{{.Title}}", with: title)
            .replacingOccurrences(of: "{{ .Date }}", with: dateString)
            .replacingOccurrences(of: "{{.Date}}", with: dateString)

        // Apply additional parameters
        for (key, value) in additionalParams {
            processedFrontmatter = processedFrontmatter
                .replacingOccurrences(of: "{{ .\(key) }}", with: value)
                .replacingOccurrences(of: "{{.\(key)}}", with: value)
            processedBody = processedBody
                .replacingOccurrences(of: "{{ .\(key) }}", with: value)
                .replacingOccurrences(of: "{{.\(key)}}", with: value)
        }

        // Build the full content
        let delimiter = frontmatterFormat.delimiter
        return "\(delimiter)\n\(processedFrontmatter)\(delimiter)\n\n\(processedBody)"
    }

    // MARK: - Hashable & Equatable

    static func == (lhs: Archetype, rhs: Archetype) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
