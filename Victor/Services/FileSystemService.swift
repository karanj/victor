import Foundation
import AppKit

/// Service for file system operations and folder management
/// Stateless — safe to hand across actor boundaries. `init()` is non-private
/// (victor-zw4) so tests can construct isolated instances instead of sharing
/// the process-wide `.shared` singleton; construction has no side effects.
final class FileSystemService: @unchecked Sendable {
    static let shared = FileSystemService()

    init() {}

    // MARK: - Path Security

    /// Validate that a URL stays within the given site root (prevents path traversal attacks)
    /// - Parameters:
    ///   - url: The URL to validate
    ///   - siteRoot: The root URL of the Hugo site
    /// - Throws: FileError.accessDenied if the path escapes the site root
    func validatePathWithinSite(_ url: URL, siteRoot: URL) throws {
        let canonicalPath = url.standardized.path
        let canonicalSiteRoot = siteRoot.standardized.path

        // Compare on a directory boundary: a bare hasPrefix check would accept
        // sibling directories like "/site-evil" for root "/site"
        guard isPath(canonicalPath, within: canonicalSiteRoot) else {
            Logger.shared.warning("[Security] Path traversal attempt blocked: \(url.path) outside \(siteRoot.path)")
            throw FileError.accessDenied
        }

        // Check for symlink attacks - resolve symlinks and verify again
        let fileManager = FileManager.default
        if let resolvedPath = try? fileManager.destinationOfSymbolicLink(atPath: canonicalPath) {
            // Symlink destinations may be relative to the link's directory
            let resolvedURL = URL(
                fileURLWithPath: resolvedPath,
                relativeTo: url.deletingLastPathComponent()
            ).standardized
            guard isPath(resolvedURL.path, within: canonicalSiteRoot) else {
                Logger.shared.warning("[Security] Symlink traversal attempt blocked: \(resolvedPath) outside \(siteRoot.path)")
                throw FileError.accessDenied
            }
        }
    }

    /// True if `path` equals `root` or is contained inside it (directory-boundary aware)
    private func isPath(_ path: String, within root: String) -> Bool {
        if path == root { return true }
        let rootWithSeparator = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(rootWithSeparator)
    }

    /// Check if a filename contains path traversal sequences
    /// - Parameter name: The filename to check
    /// - Returns: true if the name is safe, false if it contains traversal sequences
    private func isSafeFilename(_ name: String) -> Bool {
        // Reject names containing path separators or traversal patterns
        let dangerousPatterns = ["/", "\\", "..", "~"]
        for pattern in dangerousPatterns {
            if name.contains(pattern) {
                return false
            }
        }

        // Reject empty or whitespace-only names
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        return true
    }

    // MARK: - Folder Selection

    /// Present folder selection dialog and return selected URL
    /// Requires main thread for NSOpenPanel
    @MainActor
    func selectHugoSiteFolder() async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.title = "Select Hugo Site Folder"
            panel.message = "Choose a folder containing your Hugo site"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = false
            panel.allowsMultipleSelection = false

            panel.begin { response in
                if response == .OK, let url = panel.url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Security-Scoped Bookmarks

    /// Save security-scoped bookmark for persistent access
    func saveBookmark(for url: URL) throws -> Data {
        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmarkData, forKey: AppConstants.UserDefaultsKeys.hugoSiteBookmark)
        return bookmarkData
    }

    /// Load previously saved bookmark
    func loadBookmark() -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: AppConstants.UserDefaultsKeys.hugoSiteBookmark) else {
            return nil
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                // Bookmark is stale, try to refresh it
                _ = try? saveBookmark(for: url)
            }

            // Start accessing security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                return nil
            }

            return url
        } catch {
            Logger.shared.error("Error resolving bookmark", error: error)
            return nil
        }
    }

    /// Stop accessing security-scoped resource
    func stopAccessing(url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    // MARK: - Directory Scanning

    /// Scan Hugo site directory and build hierarchical file tree
    /// Now scans all site files, not just content/
    func scanDirectory(at url: URL) throws -> [FileNode] {
        // Detect the Hugo site structure
        let structure = HugoSiteStructure.detect(at: url)

        // Build tree for the entire site
        return try buildSiteTree(at: url, structure: structure)
    }

    /// Build file tree for the entire Hugo site
    private func buildSiteTree(at siteRoot: URL, structure: HugoSiteStructure) throws -> [FileNode] {
        var nodes: [FileNode] = []
        let fileManager = FileManager.default

        // Get immediate children of the root
        let contents = try fileManager.contentsOfDirectory(
            at: siteRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for itemURL in contents {
            let itemName = itemURL.lastPathComponent

            // Skip excluded directories
            if HugoSiteStructure.shouldExclude(directoryName: itemName) {
                continue
            }

            let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = resourceValues.isDirectory ?? false

            if isDirectory {
                // Determine Hugo role for this directory
                let hugoRole = HugoRole(directoryName: itemName)

                // Check if this is a Hugo page bundle
                let indexMD = itemURL.appendingPathComponent("index.md")
                let underscoreIndexMD = itemURL.appendingPathComponent("_index.md")
                let isBundle = fileManager.fileExists(atPath: indexMD.path) ||
                              fileManager.fileExists(atPath: underscoreIndexMD.path)

                // Create directory node with Hugo role
                let dirNode = FileNode(
                    url: itemURL,
                    isDirectory: true,
                    isPageBundle: isBundle,
                    hugoRole: hugoRole
                )

                // Recursively scan subdirectory
                let children = try buildFileTree(at: itemURL, isContentDirectory: hugoRole == .content)

                // Include directory even if empty (for Hugo structure visibility)
                dirNode.children = children
                for child in children {
                    child.parent = dirNode
                }
                dirNode.sortChildren()
                nodes.append(dirNode)
            } else {
                // Include root-level files (config files, go.mod, README, etc.)
                let fileNode = FileNode(url: itemURL, isDirectory: false, isPageBundle: false)
                nodes.append(fileNode)
            }
        }

        // Sort: directories first, then alphabetically
        nodes.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return nodes
    }

    /// Recursively build file tree including all file types
    /// - Parameters:
    ///   - directory: The directory to scan
    ///   - isContentDirectory: If true, only include markdown files (Hugo content behavior)
    private func buildFileTree(at directory: URL, isContentDirectory: Bool = false) throws -> [FileNode] {
        var nodes: [FileNode] = []
        let fileManager = FileManager.default

        // Get immediate children of this directory
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for itemURL in contents {
            let itemName = itemURL.lastPathComponent

            // Skip excluded items
            if HugoSiteStructure.shouldExclude(directoryName: itemName) {
                continue
            }

            let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = resourceValues.isDirectory ?? false

            if isDirectory {
                // Check if this is a Hugo page bundle (has index.md or _index.md)
                let indexMD = itemURL.appendingPathComponent("index.md")
                let underscoreIndexMD = itemURL.appendingPathComponent("_index.md")
                let isBundle = fileManager.fileExists(atPath: indexMD.path) ||
                              fileManager.fileExists(atPath: underscoreIndexMD.path)

                // Create directory node
                let dirNode = FileNode(url: itemURL, isDirectory: true, isPageBundle: isBundle)

                // Recursively scan subdirectory
                let children = try buildFileTree(at: itemURL, isContentDirectory: isContentDirectory)

                // For content directories, only include if has children
                // For other directories, always include for visibility
                if isContentDirectory {
                    if !children.isEmpty {
                        dirNode.children = children
                        for child in children {
                            child.parent = dirNode
                        }
                        dirNode.sortChildren()
                        nodes.append(dirNode)
                    }
                } else {
                    dirNode.children = children
                    for child in children {
                        child.parent = dirNode
                    }
                    dirNode.sortChildren()
                    nodes.append(dirNode)
                }
            } else {
                // For content directory, only include markdown files
                // For other directories, include all files
                if isContentDirectory {
                    if itemURL.pathExtension.lowercased() == "md" {
                        let fileNode = FileNode(url: itemURL, isDirectory: false, isPageBundle: false)
                        nodes.append(fileNode)
                    }
                } else {
                    let fileNode = FileNode(url: itemURL, isDirectory: false, isPageBundle: false)
                    nodes.append(fileNode)
                }
            }
        }

        // Sort: directories first, then alphabetically
        nodes.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return nodes
    }

    // MARK: - File I/O

    /// Sendable wire format for `readContentFile(at:)`'s background read: only
    /// `String` + `Date` cross the `Task.detached` boundary. The non-Sendable
    /// `ContentFile` class (shared with `FileNode.contentFile`) is constructed
    /// afterward, back in the caller's isolation domain (WP3.5 Cluster 1).
    private struct ContentFileReadResult: Sendable {
        let content: String
        let modificationDate: Date
    }

    /// Read content file from disk. `Task.detached` is deliberate: the reads below are
    /// blocking and this function has no isolation of its own, so without detaching they
    /// would run inline on the caller's thread (typically the main actor).
    func readContentFile(at url: URL) async throws -> ContentFile {
        // Perform file I/O on background thread
        let result: ContentFileReadResult = try await Task.detached {
            let content = try String(contentsOf: url, encoding: .utf8)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let modificationDate = attributes[.modificationDate] as? Date ?? Date()
            return ContentFileReadResult(content: content, modificationDate: modificationDate)
        }.value

        // Parse frontmatter and construct the ContentFile after crossing back
        let parser = FrontmatterParser.shared
        let (frontmatter, markdown) = parser.parseContent(result.content)

        return ContentFile(
            url: url,
            frontmatter: frontmatter,
            markdownContent: markdown,
            lastModified: result.modificationDate
        )
    }

    /// Write content to file, off the caller's actor. `@concurrent` (SE-0461) compiler-pins
    /// the blocking coordinator/write calls to the concurrent executor, regardless of the
    /// `NonisolatedNonsendingByDefault` setting.
    @concurrent
    func writeFile(to url: URL, content: String) async throws {
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var writeError: Error?

        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinatorError) { coordinatedURL in
            do {
                // Write directly (not atomically) so Hugo's file watcher can detect
                // which file changed for --navigateToChanged. Atomic writes use rename
                // which Hugo can't associate with the content file path.
                // Risk is minimal since Hugo content is typically git-tracked.
                try content.write(to: coordinatedURL, atomically: false, encoding: .utf8)
            } catch {
                writeError = error
            }
        }

        // Check for errors
        if let error = coordinatorError {
            throw error
        }
        if let error = writeError {
            throw error
        }
    }

    /// Write content file to disk. Takes `url`/`content` rather than a `ContentFile` so the
    /// non-Sendable model never crosses the `await` boundary - the caller extracts them
    /// after syncing any pending edited content in.
    func saveContentFile(url: URL, content: String) async throws {
        try await writeFile(to: url, content: content)
    }

    /// Create a new markdown file inside the given folder URL
    /// - Parameters:
    ///   - folderURL: The folder to create the file in
    ///   - siteRoot: The site root URL for path traversal validation
    func createMarkdownFile(in folderURL: URL, siteRoot: URL) async throws -> URL {
        let fileManager = FileManager.default

        // Ensure directory exists
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw FileError.fileNotFound
        }

        // Generate a base name from the current date: YYYY-MM-DD
        let dateString = Date().formatted(Date.VerbatimFormatStyle.hugoDateOnly())
        let baseName = dateString
        var candidateName = "\(baseName).md"
        var index = 1
        var candidateURL = folderURL.appendingPathComponent(candidateName)

        while fileManager.fileExists(atPath: candidateURL.path) {
            candidateName = "\(baseName)-\(index).md"
            candidateURL = folderURL.appendingPathComponent(candidateName)
            index += 1
        }

        // Validate the candidate path stays within site boundaries
        try validatePathWithinSite(candidateURL, siteRoot: siteRoot)

        // Simple default frontmatter and body
        let content = """
        ---
        title: "New Post"
        draft: true
        ---

        # New Post

        Write your content here.
        """

        try await writeFile(to: candidateURL, content: content)
        return candidateURL
    }

    /// Get file modification date
    func getModificationDate(for url: URL) -> Date? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.modificationDate] as? Date
        } catch {
            return nil
        }
    }

    // MARK: - File Operations (Context Menu)

    /// Rename a file or folder
    /// - Parameters:
    ///   - url: The current file URL
    ///   - newName: The new filename
    ///   - siteRoot: The site root URL for path traversal validation
    func renameFile(at url: URL, to newName: String, siteRoot: URL) async throws -> URL {
        // Security: Validate filename doesn't contain path traversal sequences
        guard isSafeFilename(newName) else {
            Logger.shared.warning("[Security] Unsafe filename rejected in rename: \(newName)")
            throw FileError.accessDenied
        }

        // Stat the SOURCE for isDirectory: the destination doesn't exist yet, so Foundation
        // would miss and produce a slash-less URL, and the source URL's own form can't be
        // trusted either. A slash-less result mismatches every URL built after the move.
        var sourceIsDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &sourceIsDirectory)
        let newURL = url.deletingLastPathComponent()
            .appendingPathComponent(newName, isDirectory: sourceIsDirectory.boolValue)

        // Validate the new path stays within site boundaries
        try validatePathWithinSite(newURL, siteRoot: siteRoot)

        // Check if destination already exists
        if FileManager.default.fileExists(atPath: newURL.path) {
            throw FileError.fileAlreadyExists
        }

        // victor-mod: shared `withFileCoordination` helper replaces the hand-rolled
        // continuation + didResume dance (also used by AutoSaveService.performSave and
        // duplicateFile below).
        return try await withFileCoordination { resume in
            let coordinator = NSFileCoordinator()
            var coordinatorError: NSError?

            coordinator.coordinate(writingItemAt: url, options: .forMoving, writingItemAt: newURL, options: .forReplacing, error: &coordinatorError) { oldURL, targetURL in
                do {
                    try FileManager.default.moveItem(at: oldURL, to: targetURL)
                    resume(.success(targetURL))
                } catch {
                    resume(.failure(error))
                }
            }

            return coordinatorError
        }
    }

    /// Move a file or folder within the site (drag-to-move). Same coordination pattern as
    /// `renameFile`: source `isDirectory` stat, path-within-site validation, collision
    /// check, all before touching disk. No `isSafeFilename` check - the name doesn't change.
    /// - Parameters:
    ///   - url: the file/folder's current URL
    ///   - targetDirectory: the destination folder's URL (must be inside the site)
    ///   - siteRoot: the site root URL for path traversal validation
    /// - Returns: the new URL after the move (same filename, new parent)
    func moveFile(at url: URL, to targetDirectory: URL, siteRoot: URL) async throws -> URL {
        var sourceIsDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &sourceIsDirectory)
        let newURL = targetDirectory.appendingPathComponent(
            url.lastPathComponent, isDirectory: sourceIsDirectory.boolValue)

        // Validate the new path stays within site boundaries
        try validatePathWithinSite(newURL, siteRoot: siteRoot)

        // Check if destination already exists
        if FileManager.default.fileExists(atPath: newURL.path) {
            throw FileError.fileAlreadyExists
        }

        return try await withFileCoordination { resume in
            let coordinator = NSFileCoordinator()
            var coordinatorError: NSError?

            coordinator.coordinate(writingItemAt: url, options: .forMoving, writingItemAt: newURL, options: .forReplacing, error: &coordinatorError) { oldURL, targetURL in
                do {
                    try FileManager.default.moveItem(at: oldURL, to: targetURL)
                    resume(.success(targetURL))
                } catch {
                    resume(.failure(error))
                }
            }

            return coordinatorError
        }
    }

    /// Duplicate a file
    func duplicateFile(at url: URL) async throws -> URL {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        // Find a unique name for the duplicate
        var copyNumber = 1
        var newName = "\(baseName) copy.\(ext)"
        var newURL = directory.appendingPathComponent(newName)

        while fileManager.fileExists(atPath: newURL.path) {
            copyNumber += 1
            newName = "\(baseName) copy \(copyNumber).\(ext)"
            newURL = directory.appendingPathComponent(newName)
        }

        // victor-mod: shared `withFileCoordination` helper (see renameFile above).
        return try await withFileCoordination { resume in
            let coordinator = NSFileCoordinator()
            var coordinatorError: NSError?

            coordinator.coordinate(readingItemAt: url, options: [], writingItemAt: newURL, options: .forReplacing, error: &coordinatorError) { sourceURL, destURL in
                do {
                    try fileManager.copyItem(at: sourceURL, to: destURL)
                    resume(.success(destURL))
                } catch {
                    resume(.failure(error))
                }
            }

            return coordinatorError
        }
    }

    /// Copy an external file into the site, choosing a collision-free destination name.
    /// The single copy path for every drag-and-drop import flow.
    ///
    /// Deliberately synchronous: `NSFileCoordinator.coordinate` already blocks until the
    /// accessor completes, so there's no asynchrony to expose - and staying sync lets drop
    /// handlers call it without a `Task { }`, which for a non-Sendable class would raise
    /// "sending self risks causing data races" at every call site.
    /// - Parameters:
    ///   - sourceURL: the external file being imported
    ///   - directory: destination directory; must be inside the site
    ///   - siteRoot: site root for path traversal validation
    /// - Returns: the URL the file was copied to (the filename may differ on collision)
    func importFile(from sourceURL: URL, into directory: URL, siteRoot: URL) throws -> URL {
        let fileManager = FileManager.default

        // Ensure destination directory exists (e.g. static/ may not exist yet)
        var isDir: ObjCBool = false
        if !fileManager.fileExists(atPath: directory.path, isDirectory: &isDir) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } else if !isDir.boolValue {
            throw FileError.fileNotFound
        }

        let destURL = uniqueImportDestinationURL(for: sourceURL, in: directory)
        try validatePathWithinSite(destURL, siteRoot: siteRoot)

        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var copyError: Error?

        coordinator.coordinate(
            readingItemAt: sourceURL, options: [],
            writingItemAt: destURL, options: .forReplacing,
            error: &coordinatorError
        ) { readURL, writeURL in
            do {
                try fileManager.copyItem(at: readURL, to: writeURL)
            } catch {
                copyError = error
            }
        }

        if let error = coordinatorError {
            throw error
        }
        if let error = copyError {
            throw error
        }

        return destURL
    }

    /// Pick a collision-free destination filename for an imported file: keep the
    /// original name if free, otherwise append " 2", " 3", etc. (Finder's convention
    /// for copies, distinct from `duplicateFile`'s "copy"/"copy N" suffix since this
    /// isn't a duplicate of an existing site file - it's a new import that happens to
    /// share a name).
    private func uniqueImportDestinationURL(for sourceURL: URL, in directory: URL) -> URL {
        let fileManager = FileManager.default
        let originalName = sourceURL.lastPathComponent
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension

        var candidateURL = directory.appendingPathComponent(originalName)
        var counter = 2

        while fileManager.fileExists(atPath: candidateURL.path) {
            let candidateName = ext.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(counter).\(ext)"
            candidateURL = directory.appendingPathComponent(candidateName)
            counter += 1
        }

        return candidateURL
    }

    /// Move a file or folder to the trash
    /// - Returns: the URL the item landed at inside the Trash, when the system reports
    ///   one - undo needs it to move the item back. `nil` on volumes that don't support
    ///   `resultingItemURL`, so callers must degrade rather than force-unwrap.
    @discardableResult
    func moveToTrash(at url: URL) async throws -> URL? {
        var trashedURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
        return trashedURL as URL?
    }

    /// Reveal one or more files/folders in Finder as a single selection
    /// (victor-sel B.4 - the multi-select "Reveal in Finder" context menu
    /// item routes through this). `NSWorkspace.activateFileViewerSelecting`
    /// already accepts an array; the single-URL version below is a thin
    /// wrapper so there's one implementation, not two.
    func revealInFinder(urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Reveal a single file in Finder
    func revealInFinder(url: URL) {
        revealInFinder(urls: [url])
    }

    /// Copy one or more file paths to the pasteboard, newline-joined
    /// (victor-sel B.4 - the multi-select "Copy Path" context menu item and
    /// Cmd+C route through this). The single-URL version below is a thin
    /// wrapper so there's one pasteboard-writing implementation, not two.
    func copyPathsToClipboard(urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    /// Copy a single file's path to the clipboard
    func copyPathToClipboard(url: URL) {
        copyPathsToClipboard(urls: [url])
    }

    /// Create a new folder inside the given directory
    func createFolder(in directory: URL, name: String = "New Folder") async throws -> URL {
        // Security: Validate folder name doesn't contain path traversal sequences
        guard isSafeFilename(name) else {
            Logger.shared.warning("[Security] Unsafe folder name rejected: \(name)")
            throw FileError.accessDenied
        }

        let fileManager = FileManager.default

        // Find a unique name for the folder
        var folderName = name
        var folderURL = directory.appendingPathComponent(folderName)
        var counter = 1

        while fileManager.fileExists(atPath: folderURL.path) {
            counter += 1
            folderName = "\(name) \(counter)"
            folderURL = directory.appendingPathComponent(folderName)
        }

        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: false)
        return folderURL
    }

    // MARK: - Status Metadata Loading

    /// Read only the frontmatter portion of a markdown file (first ~4KB) - much faster than
    /// reading the whole file. `@concurrent` pins the blocking `FileHandle` read off the
    /// concurrent executor.
    @concurrent
    func readFrontmatterOnly(at url: URL) async -> FileStatusMetadata? {
        do {
            // Read first 4KB - more than enough for any reasonable frontmatter
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            let data = handle.readData(ofLength: 4096)
            guard let content = String(data: data, encoding: .utf8) else {
                return nil
            }

            return FrontmatterParser.shared.parseStatusMetadata(from: content)
        } catch {
            Logger.shared.debug("Failed to read frontmatter from \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    /// Batch load status metadata for multiple files
    /// Optimized for loading many files when a folder is expanded
    func loadStatusMetadata(for urls: [URL]) async -> [URL: FileStatusMetadata] {
        await withTaskGroup(of: (URL, FileStatusMetadata?).self) { group in
            for url in urls {
                group.addTask {
                    let metadata = await self.readFrontmatterOnly(at: url)
                    return (url, metadata)
                }
            }

            var results: [URL: FileStatusMetadata] = [:]
            for await (url, metadata) in group {
                if let metadata = metadata {
                    results[url] = metadata
                }
            }
            return results
        }
    }
}

// MARK: - File Errors

enum FileError: LocalizedError, Equatable {
    case accessDenied
    case fileNotFound
    case corruptedFrontmatter
    case writeFailure
    case notAHugoSite
    case fileAlreadyExists

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Cannot access file. Please grant permission."
        case .fileNotFound:
            return "File not found."
        case .corruptedFrontmatter:
            return "Frontmatter is malformed or corrupted."
        case .writeFailure:
            return "Failed to save file."
        case .notAHugoSite:
            return "Selected folder does not appear to be a Hugo site."
        case .fileAlreadyExists:
            return "A file with that name already exists."
        }
    }
}
