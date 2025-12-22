import Foundation

/// Format of the frontmatter
enum FrontmatterFormat {
    case yaml
    case toml
    case json
}

/// Represents Hugo frontmatter metadata
/// Phase 1: Basic version that stores raw content
/// Phase 3: Will be enhanced with full parsing and structured fields
@Observable
class Frontmatter {
    /// Raw frontmatter content including delimiters
    var rawContent: String

    /// Detected format
    var format: FrontmatterFormat

    // Common Hugo fields
    var title: String?
    var date: Date?
    var draft: Bool?
    var tags: [String]?
    var categories: [String]?
    var description: String?

    // Custom fields (any fields not in the common list)
    var customFields: [String: Any] = [:]

    init(rawContent: String, format: FrontmatterFormat = .yaml) {
        self.rawContent = rawContent
        self.format = format
    }

    /// Detect frontmatter format from delimiters
    static func detectFormat(from content: String) -> FrontmatterFormat? {
        if content.hasPrefix("---") {
            return .yaml
        } else if content.hasPrefix("+++") {
            return .toml
        } else if content.hasPrefix("{") {
            return .json
        }
        return nil
    }
}
