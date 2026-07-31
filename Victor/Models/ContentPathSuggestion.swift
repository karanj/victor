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
    /// Case-insensitive substring match; an empty query matches everything.
    static func filter(_ suggestions: [ContentPathSuggestion], query: String) -> [ContentPathSuggestion] {
        guard !query.isEmpty else { return suggestions }
        let lowercasedQuery = query.lowercased()
        return suggestions.filter {
            $0.path.lowercased().contains(lowercasedQuery) ||
            $0.displayName.lowercased().contains(lowercasedQuery)
        }
    }
}
