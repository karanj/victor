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
        // :filename/:contentbasename always use the actual filename
        let effectiveSlug = slug ?? fileSlug

        // Names (use POSIX locale for consistency with Hugo)
        let monthName = date.formatted(Date.VerbatimFormatStyle.hugoMonthName(timeZone: utc))
        let weekdayName = date.formatted(Date.VerbatimFormatStyle.hugoWeekdayName(timeZone: utc))

        let replacements: [(token: String, value: String)] = [
            (":year", String(format: "%04d", year)),
            (":month", String(format: "%02d", month)),
            (":day", String(format: "%02d", day)),
            (":yearday", String(format: "%03d", dayOfYear)),
            (":monthname", monthName.lowercased()),
            (":weekdayname", weekdayName.lowercased()),
            (":weekday", String(comps.weekday ?? 0)),
            (":section", section),
            (":sections", section),
            (":contentbasename", fileSlug),
            (":filename", fileSlug),
            (":slugorcontentbasename", effectiveSlug),
            (":slugorfilename", effectiveSlug),
            (":slug", effectiveSlug),
            (":title", effectiveSlug),
        ]

        var result = pattern
        // Longest token first, so a token that prefixes another (:year in
        // :yearday, :section in :sections, :slug in :slugor…) can't corrupt it
        for (token, value) in replacements.sorted(by: { $0.token.count > $1.token.count }) {
            result = result.replacingOccurrences(of: token, with: value)
        }

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
        /// Deprecated tokens stay recognized (files using them must not break)
        /// but are excluded from the insert menu.
        var deprecated: Bool = false
    }

    /// All valid Hugo permalink tokens.
    /// :filename/:slugorfilename were deprecated in Hugo v0.144 in favor of
    /// :contentbasename/:slugorcontentbasename (CONFIG-SCHEMA-SPEC finding #9).
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
        TokenInfo(token: ":contentbasename", description: "Content file base name", example: "my-post"),
        TokenInfo(token: ":slugorcontentbasename", description: "Slug, falling back to file base name", example: "my-post"),
        TokenInfo(token: ":filename", description: "Original filename (deprecated — use :contentbasename)", example: "my-post", deprecated: true),
        TokenInfo(token: ":slugorfilename", description: "Slug or filename (deprecated — use :slugorcontentbasename)", example: "my-post", deprecated: true),
    ]

    /// Tokens offered in the insert menu — deprecated ones are recognized in
    /// existing patterns but never offered for new ones.
    static let insertableTokens: [TokenInfo] = validTokens.filter { !$0.deprecated }

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
