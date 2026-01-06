import Foundation

// MARK: - Content Path Suggestion

/// Represents a content file path suggestion for autocomplete
struct ContentPathSuggestion: Identifiable, Hashable {
    let id = UUID()
    let path: String        // e.g., "posts/my-post.md"
    let displayName: String // e.g., "my-post.md"

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }

    static func == (lhs: ContentPathSuggestion, rhs: ContentPathSuggestion) -> Bool {
        lhs.path == rhs.path
    }
}

// MARK: - Filtering

extension ContentPathSuggestion {
    /// Filter suggestions based on a search query
    /// - Parameters:
    ///   - suggestions: Array of suggestions to filter
    ///   - query: Search query string
    /// - Returns: Filtered suggestions matching the query
    static func filter(_ suggestions: [ContentPathSuggestion], query: String) -> [ContentPathSuggestion] {
        guard !query.isEmpty else { return suggestions }
        let lowercasedQuery = query.lowercased()
        return suggestions.filter {
            $0.path.lowercased().contains(lowercasedQuery) ||
            $0.displayName.lowercased().contains(lowercasedQuery)
        }
    }
}
