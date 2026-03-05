import Foundation

/// Resolves content file paths to Hugo URLs using permalink configuration.
///
/// Hugo's `[permalinks]` config maps sections to URL patterns with tokens like
/// `:year`, `:month`, `:title`, etc. This resolver expands those patterns
/// to produce the actual URL a page will be served at.
struct PermalinkResolver {
    /// Permalink patterns keyed by section name (e.g. ["posts": "/:year/:month/:title/"])
    let permalinks: [String: String]

    /// Resolve a content file path to the Hugo URL it will be served at.
    ///
    /// - Parameters:
    ///   - filePath: Relative path from site root (e.g. "content/posts/my-post.md")
    ///   - date: The page's date from frontmatter (needed for date-based permalink tokens)
    ///   - slug: Optional slug override from frontmatter
    /// - Returns: The URL path (e.g. "/2024/03/my-post/")
    func resolveURL(filePath: String, date: Date?, slug: String?) -> String {
        var path = filePath

        // Strip "content/" prefix
        if path.hasPrefix("content/") {
            path = String(path.dropFirst("content/".count))
        }

        // Remove file extension
        let filename: String
        if let lastDot = path.lastIndex(of: ".") {
            filename = String(path[path.startIndex..<lastDot]).components(separatedBy: "/").last ?? ""
            path = String(path[..<lastDot])
        } else {
            filename = path.components(separatedBy: "/").last ?? ""
        }

        // Handle index files - permalink patterns don't apply
        if filename == "_index" || filename == "index" {
            if let lastSlash = path.lastIndex(of: "/") {
                path = String(path[..<lastSlash])
            } else {
                return "/"
            }
            return path.isEmpty ? "/" : "/\(path)/"
        }

        // Extract section (top-level directory) and filename-based slug
        let components = path.components(separatedBy: "/")
        let section = components.first ?? ""
        let fileSlug = components.last ?? ""

        // Check if we have a permalink pattern for this section
        if let pattern = permalinks[section], date != nil {
            let expanded = expandPattern(
                pattern,
                date: date!,
                section: section,
                fileSlug: fileSlug,
                slug: slug
            )
            return expanded
        }

        // Default: use the path directly (original behavior)
        let effectiveSlug = slug ?? fileSlug
        // Rebuild path with slug override applied to the last component
        if components.count > 1 {
            let parentPath = components.dropLast().joined(separator: "/")
            return "/\(parentPath)/\(effectiveSlug)/"
        }
        return "/\(effectiveSlug)/"
    }

    // MARK: - Pattern Expansion

    /// Expand a Hugo permalink pattern with actual values.
    private func expandPattern(
        _ pattern: String,
        date: Date,
        section: String,
        fileSlug: String,
        slug: String?
    ) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(identifier: "UTC")!
        var cal = calendar
        cal.timeZone = utc

        let comps = cal.dateComponents([.year, .month, .day, .weekday, .weekdayOrdinal], from: date)
        let year = comps.year ?? 2000
        let month = comps.month ?? 1
        let day = comps.day ?? 1
        let dayOfYear = cal.ordinality(of: .day, in: .year, for: date) ?? 1

        // The effective slug: :title and :slug both use slug override if present,
        // :filename always uses the actual filename
        let effectiveSlug = slug ?? fileSlug

        var result = pattern

        // Date tokens
        result = result.replacingOccurrences(of: ":year", with: String(format: "%04d", year))
        result = result.replacingOccurrences(of: ":month", with: String(format: "%02d", month))
        result = result.replacingOccurrences(of: ":day", with: String(format: "%02d", day))
        result = result.replacingOccurrences(of: ":yearday", with: String(format: "%03d", dayOfYear))

        // Month name (use POSIX locale for consistency with Hugo)
        let monthFormatter = DateFormatter()
        monthFormatter.timeZone = utc
        monthFormatter.locale = Locale(identifier: "en_US_POSIX")
        monthFormatter.dateFormat = "MMMM"
        result = result.replacingOccurrences(of: ":monthname", with: monthFormatter.string(from: date).lowercased())

        // Weekday
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.timeZone = utc
        weekdayFormatter.locale = Locale(identifier: "en_US_POSIX")
        weekdayFormatter.dateFormat = "EEEE"
        result = result.replacingOccurrences(of: ":weekdayname", with: weekdayFormatter.string(from: date).lowercased())
        result = result.replacingOccurrences(of: ":weekday", with: String(comps.weekday ?? 0))

        // Content tokens
        result = result.replacingOccurrences(of: ":section", with: section)
        result = result.replacingOccurrences(of: ":sections", with: section)
        result = result.replacingOccurrences(of: ":filename", with: fileSlug)
        result = result.replacingOccurrences(of: ":slug", with: effectiveSlug)
        result = result.replacingOccurrences(of: ":title", with: effectiveSlug)

        // Ensure leading slash
        if !result.hasPrefix("/") {
            result = "/" + result
        }

        // Ensure trailing slash
        if !result.hasSuffix("/") {
            result += "/"
        }

        return result
    }

    // MARK: - Token Definitions

    /// A Hugo permalink token with its description and example output.
    struct TokenInfo: Identifiable {
        var id: String { token }
        let token: String
        let description: String
        let example: String
    }

    /// All valid Hugo permalink tokens.
    static let validTokens: [TokenInfo] = [
        TokenInfo(token: ":year", description: "4-digit year", example: "2024"),
        TokenInfo(token: ":month", description: "2-digit month", example: "03"),
        TokenInfo(token: ":day", description: "2-digit day", example: "15"),
        TokenInfo(token: ":yearday", description: "Day of year (001–366)", example: "074"),
        TokenInfo(token: ":monthname", description: "Month name", example: "march"),
        TokenInfo(token: ":weekday", description: "Weekday number (0=Sun)", example: "5"),
        TokenInfo(token: ":weekdayname", description: "Weekday name", example: "friday"),
        TokenInfo(token: ":section", description: "Content section", example: "posts"),
        TokenInfo(token: ":sections", description: "Content sections path", example: "posts"),
        TokenInfo(token: ":title", description: "Page title/slug", example: "my-post"),
        TokenInfo(token: ":slug", description: "Slug (from frontmatter or filename)", example: "my-post"),
        TokenInfo(token: ":filename", description: "Original filename", example: "my-post"),
    ]

    /// Set of valid token strings for fast lookup.
    private static let validTokenSet: Set<String> = Set(validTokens.map(\.token))

    // MARK: - Validation

    /// Validate a permalink pattern string.
    /// Returns nil if valid, or an error message if invalid.
    static func validate(pattern: String) -> String? {
        if pattern.isEmpty {
            return "Pattern cannot be empty"
        }

        if !pattern.hasPrefix("/") {
            return "Pattern must start with /"
        }

        if !pattern.hasSuffix("/") {
            return "Pattern must end with /"
        }

        // Extract all :token occurrences and check against valid set
        let unknownTokens = extractTokens(from: pattern).filter { !validTokenSet.contains($0) }
        if !unknownTokens.isEmpty {
            let list = unknownTokens.joined(separator: ", ")
            return "Unknown token\(unknownTokens.count > 1 ? "s" : ""): \(list)"
        }

        return nil
    }

    /// Validate a section name.
    /// Returns nil if valid, or an error message if invalid.
    static func validateSectionName(_ name: String) -> String? {
        if name.isEmpty {
            return "Section name cannot be empty"
        }

        if name.contains("/") {
            return "Section name cannot contain slashes"
        }

        if name.contains(" ") {
            return "Section name cannot contain spaces"
        }

        return nil
    }

    /// Extract all `:tokenname` occurrences from a pattern string.
    private static func extractTokens(from pattern: String) -> [String] {
        var tokens: [String] = []
        var i = pattern.startIndex
        while i < pattern.endIndex {
            if pattern[i] == ":" {
                // Scan forward for the token name (letters only)
                var end = pattern.index(after: i)
                while end < pattern.endIndex && pattern[end].isLetter {
                    end = pattern.index(after: end)
                }
                if end > pattern.index(after: i) {
                    tokens.append(String(pattern[i..<end]))
                }
                i = end
            } else {
                i = pattern.index(after: i)
            }
        }
        return tokens
    }

    // MARK: - Config Parsing

    /// Extract permalink patterns from a HugoConfig.
    /// Uses the first-class `permalinks` property (already parsed during config loading).
    static func parsePermalinks(from config: HugoConfig) -> [String: String] {
        return config.permalinks
    }
}
