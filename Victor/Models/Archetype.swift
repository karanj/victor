import Foundation

/// Represents a Hugo archetype (content template)
/// Archetypes are stored in the archetypes/ directory and define templates
/// for new content files with frontmatter and body placeholders.
/// `@MainActor`: only ever constructed/mutated from `@MainActor` call sites
/// (form-bound editing via `@Bindable` in the Archetype editor) — see WP3.5 Cluster 13.
@Observable
@MainActor
class Archetype: @MainActor EditableFile {
    let id: UUID
    let url: URL

    /// The raw frontmatter content (YAML/TOML/JSON)
    var frontmatterContent: String

    /// The body template content (may contain Go template variables)
    var bodyTemplate: String

    /// The detected frontmatter format
    var frontmatterFormat: FrontmatterFormat

    // MARK: - Editing State

    /// Local raw content storage - prevents cursor jumping by not reconstructing on every access
    /// This is the source of truth for the editor
    private var localRawContent: String

    /// Original raw content (for change tracking)
    @ObservationIgnored private var originalRawContent: String

    /// Whether this archetype has unsaved changes
    var hasUnsavedChanges: Bool {
        localRawContent != originalRawContent
    }

    /// Raw combined content for unified editing
    /// This wraps localRawContent to parse and sync the parts when content changes
    var rawContent: String {
        get {
            localRawContent
        }
        set {
            localRawContent = newValue
            // Parse the raw content to update frontmatter and body parts
            let parsed = Self.parseRawContent(newValue)
            frontmatterContent = parsed.frontmatter
            bodyTemplate = parsed.body
            if let format = parsed.format {
                frontmatterFormat = format
            }
        }
    }

    /// Parse raw content into frontmatter and body components
    private static func parseRawContent(_ content: String) -> (frontmatter: String, body: String, format: FrontmatterFormat?) {
        let lines = content.components(separatedBy: "\n")
        guard !lines.isEmpty else {
            return ("", content, nil)
        }

        // Detect frontmatter format from first line
        let firstLine = lines[0].trimmingCharacters(in: .whitespaces)
        var format: FrontmatterFormat?
        var delimiter: String

        if firstLine == "---" {
            format = .yaml
            delimiter = "---"
        } else if firstLine == "+++" {
            format = .toml
            delimiter = "+++"
        } else if firstLine == "{" {
            // JSON frontmatter
            format = .json
            delimiter = "{"
        } else {
            // No frontmatter detected
            return ("", content, nil)
        }

        // Handle JSON separately
        if format == .json {
            // Find matching closing brace
            var braceCount = 0
            var endIndex = 0
            for (index, line) in lines.enumerated() {
                for char in line {
                    if char == "{" { braceCount += 1 }
                    if char == "}" { braceCount -= 1 }
                }
                if braceCount == 0 {
                    endIndex = index
                    break
                }
            }
            let frontmatter = lines[0...endIndex].joined(separator: "\n")
            let body = lines.dropFirst(endIndex + 1).joined(separator: "\n").trimmingCharacters(in: .newlines)
            return (frontmatter, body, format)
        }

        // Find closing delimiter for YAML/TOML
        var frontmatterLines: [String] = []
        var bodyLines: [String] = []
        var foundClosing = false

        for (index, line) in lines.enumerated() {
            if index == 0 { continue } // Skip opening delimiter

            if line.trimmingCharacters(in: .whitespaces) == delimiter && !foundClosing {
                foundClosing = true
                continue
            }

            if foundClosing {
                bodyLines.append(line)
            } else {
                frontmatterLines.append(line)
            }
        }

        let frontmatter = frontmatterLines.joined(separator: "\n")
        let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .newlines)

        return (frontmatter, body, format)
    }

    /// Mark the current state as saved (reset original values)
    func markAsSaved() {
        originalRawContent = localRawContent
    }

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

        // Initialize raw content from parts
        let delimiter = frontmatterFormat.delimiter
        let initialRawContent = "\(delimiter)\n\(frontmatterContent)\n\(delimiter)\n\n\(bodyTemplate)"
        self.localRawContent = initialRawContent
        self.originalRawContent = initialRawContent
    }

    // MARK: - Template Processing

    /// Expand the archetype's template placeholders into content for a new file.
    func processTemplate(title: String, date: Date = Date(), additionalParams: [String: String] = [:]) -> String {
        let dateString = date.formatted(Date.ISO8601FormatStyle.hugoArchetypeTimestamp)

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
        return "\(delimiter)\n\(processedFrontmatter)\n\(delimiter)\n\n\(processedBody)"
    }

    // MARK: - Hashable & Equatable
    // Provided by EditableFile protocol
}
