import Foundation

/// Service for searching and replacing text across multiple files
actor SearchService {
    static let shared = SearchService()

    private init() {}

    // MARK: - Search

    /// Search for matches across multiple files
    /// - Parameters:
    ///   - options: Search configuration including query, regex, case sensitivity
    ///   - fileURLs: Pre-filtered file URLs to search in (see `searchableFileURLs(from:options:)`
    ///     below, called by the caller on `@MainActor` before crossing into this actor -
    ///     `FileNode` has a `weak var parent` and recursive children, so it can never be
    ///     Sendable and must never cross this boundary as a live tree; WP3.5 Cluster 6)
    ///   - siteRootURL: Root URL of the Hugo site (for relative paths)
    /// - Returns: Array of file results with matches
    func search(
        options: SearchOptions,
        in fileURLs: [URL],
        siteRootURL: URL
    ) async -> [FileSearchResult] {
        guard !options.query.isEmpty else { return [] }

        // Search files in parallel
        return await withTaskGroup(of: FileSearchResult?.self) { group in
            for fileURL in fileURLs {
                group.addTask {
                    await self.searchFile(at: fileURL, options: options, siteRootURL: siteRootURL)
                }
            }

            var results: [FileSearchResult] = []
            for await result in group {
                if let result = result, !result.matches.isEmpty {
                    results.append(result)
                }
            }

            // Sort by file path for consistent ordering
            return results.sorted { $0.relativePath < $1.relativePath }
        }
    }

    /// Search within a single file
    private func searchFile(
        at url: URL,
        options: SearchOptions,
        siteRootURL: URL
    ) async -> FileSearchResult? {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let matches = searchInContent(content, options: options)

            if matches.isEmpty {
                return nil
            }

            return FileSearchResult(
                fileURL: url,
                siteRootURL: siteRootURL,
                matches: matches
            )
        } catch {
            Logger.shared.error("[SearchService] Failed to read file: \(url.lastPathComponent)", error: error)
            return nil
        }
    }

    /// Search for matches within file content
    func searchInContent(_ content: String, options: SearchOptions) -> [SearchMatch] {
        guard !options.query.isEmpty else { return [] }

        var matches: [SearchMatch] = []
        let lines = content.components(separatedBy: .newlines)

        // Build regex pattern
        let pattern: String
        if options.isRegex {
            pattern = options.query
        } else {
            pattern = NSRegularExpression.escapedPattern(for: options.query)
        }

        var regexOptions: NSRegularExpression.Options = []
        if !options.isCaseSensitive {
            regexOptions.insert(.caseInsensitive)
        }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: regexOptions) else {
            Logger.shared.warning("[SearchService] Invalid regex pattern: \(options.query)")
            return []
        }

        for (index, line) in lines.enumerated() {
            let nsRange = NSRange(line.startIndex..., in: line)
            let lineMatches = regex.matches(in: line, range: nsRange)

            for match in lineMatches {
                if let swiftRange = Range(match.range, in: line) {
                    matches.append(SearchMatch(
                        lineNumber: index + 1,
                        lineContent: line,
                        matchRange: swiftRange
                    ))
                }

                // Limit matches per file for performance
                if matches.count >= AppConstants.GlobalSearch.maxResultsPerFile {
                    return matches
                }
            }
        }

        return matches
    }

    // MARK: - Replace

    /// Replace all matches in files
    /// - Parameters:
    ///   - results: Search results to replace in
    ///   - options: Search options including replacement text
    /// - Returns: Number of replacements made
    func replaceAll(
        in results: [FileSearchResult],
        options: SearchOptions
    ) async throws -> Int {
        guard !options.replaceWith.isEmpty || !options.query.isEmpty else { return 0 }

        var totalReplacements = 0

        for fileResult in results {
            let replacements = try await replaceInFile(
                at: fileResult.fileURL,
                options: options
            )
            totalReplacements += replacements
        }

        return totalReplacements
    }

    /// Replace matches in a single file
    private func replaceInFile(
        at url: URL,
        options: SearchOptions
    ) async throws -> Int {
        let content = try String(contentsOf: url, encoding: .utf8)

        // Build regex pattern
        let pattern: String
        if options.isRegex {
            pattern = options.query
        } else {
            pattern = NSRegularExpression.escapedPattern(for: options.query)
        }

        var regexOptions: NSRegularExpression.Options = []
        if !options.isCaseSensitive {
            regexOptions.insert(.caseInsensitive)
        }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: regexOptions) else {
            throw SearchError.invalidRegex(options.query)
        }

        let nsRange = NSRange(content.startIndex..., in: content)
        let matchCount = regex.numberOfMatches(in: content, range: nsRange)

        if matchCount == 0 {
            return 0
        }

        // Perform replacement
        let replaced = regex.stringByReplacingMatches(
            in: content,
            range: nsRange,
            withTemplate: options.isRegex ? options.replaceWith : NSRegularExpression.escapedTemplate(for: options.replaceWith)
        )

        // Write back to file using FileSystemService pattern
        try await writeFile(to: url, content: replaced)

        Logger.shared.info("[SearchService] Replaced \(matchCount) matches in \(url.lastPathComponent)")
        return matchCount
    }

    /// Write content to file with coordination.
    /// `nonisolated` replaces `Task.detached` here (victor-tdt audit): `SearchService`
    /// is an `actor`, so this private method was actor-isolated purely by inheriting
    /// that isolation, not because it touches actor state - `nonisolated` already gets
    /// the blocking coordinated write off the actor's executor under this project's
    /// current default, without spawning a detached task.
    private nonisolated func writeFile(to url: URL, content: String) async throws {
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var writeError: Error?

        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinatorError) { coordinatedURL in
            do {
                try content.write(to: coordinatedURL, atomically: true, encoding: .utf8)
            } catch {
                writeError = error
            }
        }

        if let error = coordinatorError {
            throw error
        }
        if let error = writeError {
            throw error
        }
    }

    // MARK: - File Collection

    /// Recursively collect all searchable file URLs from nodes.
    ///
    /// `nonisolated static`, not an actor-isolated instance method: `FileNode` has a
    /// `weak var parent` and recursive children (CLAUDE.md: must stay a class, can't be
    /// Sendable), so this walk has to happen entirely on the caller's side (`@MainActor`,
    /// since `SiteViewModel.fileNodes` is only safe to read there) - the actor itself
    /// never touches a `FileNode` reference (WP3.5 Cluster 6). Call this before
    /// `search(options:in:siteRootURL:)`, passing its result as `fileURLs`.
    nonisolated static func searchableFileURLs(from nodes: [FileNode], options: SearchOptions) -> [URL] {
        var files: [URL] = []

        for node in nodes {
            collectFiles(from: node, into: &files, options: options)
        }

        return files
    }

    private nonisolated static func collectFiles(from node: FileNode, into files: inout [URL], options: SearchOptions) {
        if node.isDirectory {
            // Check scope filtering
            if let roles = options.scope.hugoRoles {
                // For scoped search, only descend into matching directories
                if let nodeRole = node.hugoRole, roles.contains(nodeRole) {
                    // This directory matches scope, search all children
                    for child in node.children {
                        collectFiles(from: child, into: &files, options: options)
                    }
                } else if node.hugoRole == nil {
                    // No role assigned, check children (might be subdirectory of matching dir)
                    for child in node.children {
                        collectFiles(from: child, into: &files, options: options)
                    }
                }
                // Skip directories that don't match scope
            } else {
                // All files scope - descend into all directories
                for child in node.children {
                    collectFiles(from: child, into: &files, options: options)
                }
            }
        } else if node.isEditable {
            // Check if file is in a matching scope
            if let roles = options.scope.hugoRoles {
                if isNodeInScope(node, roles: roles) {
                    files.append(node.url)
                }
            } else {
                // All files scope
                files.append(node.url)
            }
        }
    }

    /// Check if a file node is within a directory matching the given roles
    private nonisolated static func isNodeInScope(_ node: FileNode, roles: Set<HugoRole>) -> Bool {
        var current: FileNode? = node.parent
        while let parent = current {
            if let role = parent.hugoRole, roles.contains(role) {
                return true
            }
            current = parent.parent
        }
        return false
    }
}

// MARK: - Errors

enum SearchError: LocalizedError {
    case invalidRegex(String)
    case fileReadError(URL)
    case fileWriteError(URL)

    var errorDescription: String? {
        switch self {
        case .invalidRegex(let pattern):
            return "Invalid regular expression: \(pattern)"
        case .fileReadError(let url):
            return "Failed to read file: \(url.lastPathComponent)"
        case .fileWriteError(let url):
            return "Failed to write file: \(url.lastPathComponent)"
        }
    }
}
