import Foundation

// MARK: - Search Scope

/// Defines which directories to search in
enum SearchScope: String, CaseIterable, Identifiable {
    case allFiles = "All Files"
    case content = "Content"
    case layouts = "Layouts"
    case data = "Data"
    case staticFiles = "Static"

    var id: String { rawValue }

    /// The Hugo role(s) this scope corresponds to
    var hugoRoles: Set<HugoRole>? {
        switch self {
        case .allFiles:
            return nil  // No filtering
        case .content:
            return [.content]
        case .layouts:
            return [.layouts]
        case .data:
            return [.data]
        case .staticFiles:
            return [.staticFiles, .assets]
        }
    }
}

// MARK: - Search Options

/// Configuration for a search operation
struct SearchOptions {
    var query: String = ""
    var replaceWith: String = ""
    var isRegex: Bool = false
    var isCaseSensitive: Bool = false
    var scope: SearchScope = .allFiles
    var includeFileNames: Bool = true  // Also match file names, not just content
}

// MARK: - Search Match

/// A single match within a file
struct SearchMatch: Identifiable, Equatable {
    let id: UUID
    let lineNumber: Int
    let lineContent: String
    let matchRange: Range<String.Index>

    init(lineNumber: Int, lineContent: String, matchRange: Range<String.Index>) {
        self.id = UUID()
        self.lineNumber = lineNumber
        self.lineContent = lineContent
        self.matchRange = matchRange
    }

    /// The matched text
    var matchedText: String {
        String(lineContent[matchRange])
    }

    /// Text before the match (for context display)
    var textBeforeMatch: String {
        String(lineContent[lineContent.startIndex..<matchRange.lowerBound])
    }

    /// Text after the match (for context display)
    var textAfterMatch: String {
        String(lineContent[matchRange.upperBound..<lineContent.endIndex])
    }

    static func == (lhs: SearchMatch, rhs: SearchMatch) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - File Search Result

/// Search results for a single file
struct FileSearchResult: Identifiable, Equatable {
    let id: UUID
    let fileURL: URL
    let fileName: String
    let relativePath: String
    var matches: [SearchMatch]
    var isExpanded: Bool = true

    init(fileURL: URL, siteRootURL: URL, matches: [SearchMatch]) {
        self.id = UUID()
        self.fileURL = fileURL
        self.fileName = fileURL.lastPathComponent
        self.matches = matches

        // Calculate relative path from site root
        let filePath = fileURL.path
        let rootPath = siteRootURL.path
        if filePath.hasPrefix(rootPath) {
            var relative = String(filePath.dropFirst(rootPath.count))
            if relative.hasPrefix("/") {
                relative = String(relative.dropFirst())
            }
            self.relativePath = relative
        } else {
            self.relativePath = fileName
        }
    }

    /// Total number of matches in this file
    var matchCount: Int {
        matches.count
    }

    static func == (lhs: FileSearchResult, rhs: FileSearchResult) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Global Search Results

/// Aggregated results from a global search
struct GlobalSearchResults {
    var fileResults: [FileSearchResult] = []
    var searchOptions: SearchOptions

    init(options: SearchOptions = SearchOptions()) {
        self.searchOptions = options
    }

    /// Total number of files with matches
    var fileCount: Int {
        fileResults.count
    }

    /// Total number of matches across all files
    var totalMatchCount: Int {
        fileResults.reduce(0) { $0 + $1.matchCount }
    }

    /// Whether there are any results
    var isEmpty: Bool {
        fileResults.isEmpty
    }

    /// Summary text for display (e.g., "15 matches in 4 files")
    var summaryText: String {
        if isEmpty {
            return "No results"
        }
        let matchText = totalMatchCount == 1 ? "match" : "matches"
        let fileText = fileCount == 1 ? "file" : "files"
        return "\(totalMatchCount) \(matchText) in \(fileCount) \(fileText)"
    }
}
