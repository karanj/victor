import Foundation

/// Result of a fuzzy match operation
struct FuzzyMatchResult: Identifiable, Comparable {
    let id = UUID()
    let node: FileNode
    let score: Int
    let matchedIndices: [Int] // Indices in the filename where matches occurred

    /// Path relative to content directory for display
    var displayPath: String {
        node.url.path
    }

    /// Just the filename
    var filename: String {
        node.name
    }

    static func < (lhs: FuzzyMatchResult, rhs: FuzzyMatchResult) -> Bool {
        // Higher score = better match, so sort descending
        lhs.score > rhs.score
    }
}

/// Fuzzy matching algorithm for quick file search
struct FuzzyMatcher {

    /// Perform fuzzy matching on a list of file nodes
    /// - Parameters:
    ///   - query: The search query
    ///   - nodes: All file nodes to search through
    ///   - limit: Maximum number of results to return
    /// - Returns: Sorted array of match results (best matches first)
    static func match(query: String, in nodes: [FileNode], limit: Int = 20) -> [FuzzyMatchResult] {
        guard !query.isEmpty else {
            return []
        }

        let lowercaseQuery = query.lowercased()
        var results: [FuzzyMatchResult] = []

        // Recursively collect all markdown files
        let allFiles = collectMarkdownFiles(from: nodes)

        for node in allFiles {
            if let result = matchFile(query: lowercaseQuery, node: node) {
                results.append(result)
            }
        }

        // Sort by score (highest first) and limit results
        return Array(results.sorted().prefix(limit))
    }

    /// Collect all markdown files from the node tree
    private static func collectMarkdownFiles(from nodes: [FileNode]) -> [FileNode] {
        var files: [FileNode] = []

        for node in nodes {
            if node.isDirectory {
                files.append(contentsOf: collectMarkdownFiles(from: node.children))
            } else if node.isMarkdownFile {
                files.append(node)
            }
        }

        return files
    }

    /// Try to match a single file against the query
    private static func matchFile(query: String, node: FileNode) -> FuzzyMatchResult? {
        let filename = node.name.lowercased()
        let path = node.url.path.lowercased()

        // Try matching against filename first (higher priority)
        if let (score, indices) = fuzzyScore(query: query, target: filename) {
            // Boost score for filename matches
            let boostedScore = score + 100
            return FuzzyMatchResult(node: node, score: boostedScore, matchedIndices: indices)
        }

        // Try matching against full path
        if let (score, indices) = fuzzyScore(query: query, target: path) {
            return FuzzyMatchResult(node: node, score: score, matchedIndices: indices)
        }

        return nil
    }

    /// Calculate fuzzy match score between query and target string
    /// Returns nil if no match, otherwise returns (score, matchedIndices)
    private static func fuzzyScore(query: String, target: String) -> (Int, [Int])? {
        let queryChars = Array(query)
        let targetChars = Array(target)

        var queryIndex = 0
        var matchedIndices: [Int] = []
        var score = 0
        var consecutiveMatches = 0
        var lastMatchIndex = -1

        for (targetIndex, targetChar) in targetChars.enumerated() {
            guard queryIndex < queryChars.count else { break }

            if targetChar == queryChars[queryIndex] {
                matchedIndices.append(targetIndex)

                // Base score for matching
                score += 10

                // Bonus for consecutive matches
                if targetIndex == lastMatchIndex + 1 {
                    consecutiveMatches += 1
                    score += consecutiveMatches * 5
                } else {
                    consecutiveMatches = 0
                }

                // Bonus for matching at start
                if targetIndex == 0 {
                    score += 25
                }

                // Bonus for matching after separator (word boundary)
                if targetIndex > 0 {
                    let prevChar = targetChars[targetIndex - 1]
                    if prevChar == "/" || prevChar == "-" || prevChar == "_" || prevChar == "." || prevChar == " " {
                        score += 20
                    }
                }

                lastMatchIndex = targetIndex
                queryIndex += 1
            }
        }

        // All query characters must be found
        guard queryIndex == queryChars.count else {
            return nil
        }

        // Penalty for longer paths (prefer shorter, more specific matches)
        score -= targetChars.count / 10

        return (score, matchedIndices)
    }
}

/// Index of all files in a Hugo site for quick searching
struct FileIndex {
    private var markdownFiles: [FileNode] = []

    /// Build index from file nodes
    mutating func build(from nodes: [FileNode]) {
        markdownFiles = collectMarkdownFiles(from: nodes)
    }

    /// Get all indexed files
    var allFiles: [FileNode] {
        markdownFiles
    }

    /// Number of indexed files
    var count: Int {
        markdownFiles.count
    }

    /// Collect all markdown files recursively
    private func collectMarkdownFiles(from nodes: [FileNode]) -> [FileNode] {
        var files: [FileNode] = []

        for node in nodes {
            if node.isDirectory {
                files.append(contentsOf: collectMarkdownFiles(from: node.children))
            } else if node.isMarkdownFile {
                files.append(node)
            }
        }

        return files
    }
}
