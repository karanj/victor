import Foundation
import AppKit

/// Service for file system operations and folder management
class FileSystemService {
    static let shared = FileSystemService()

    private init() {}

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
        UserDefaults.standard.set(bookmarkData, forKey: "hugoSiteBookmark")
        return bookmarkData
    }

    /// Load previously saved bookmark
    func loadBookmark() -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "hugoSiteBookmark") else {
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
            print("Error resolving bookmark: \(error)")
            return nil
        }
    }

    /// Stop accessing security-scoped resource
    func stopAccessing(url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    // MARK: - Directory Scanning

    /// Scan directory and build hierarchical file tree
    func scanDirectory(at url: URL) throws -> [FileNode] {
        // Get content directory
        let contentURL = url.appendingPathComponent("content")

        guard FileManager.default.fileExists(atPath: contentURL.path) else {
            // If no content directory, scan root for .md files
            return try buildFileTree(at: url)
        }

        // Build hierarchical tree from content directory
        return try buildFileTree(at: contentURL)
    }

    /// Recursively build file tree with folders and markdown files
    private func buildFileTree(at directory: URL) throws -> [FileNode] {
        var nodes: [FileNode] = []
        let fileManager = FileManager.default

        // Get immediate children of this directory
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for itemURL in contents {
            let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = resourceValues.isDirectory ?? false

            if isDirectory {
                // Check if this is a Hugo page bundle (has index.md or _index.md)
                let indexMD = itemURL.appendingPathComponent("index.md")
                let underscoreIndexMD = itemURL.appendingPathComponent("_index.md")
                let isBundle = fileManager.fileExists(atPath: indexMD.path) ||
                              fileManager.fileExists(atPath: underscoreIndexMD.path)

                // Create directory node with cached page bundle status
                let dirNode = FileNode(url: itemURL, isDirectory: true, isPageBundle: isBundle)

                // Recursively scan subdirectory
                let children = try buildFileTree(at: itemURL)

                // Only include directory if it has markdown files or subdirectories with markdown files
                if !children.isEmpty {
                    dirNode.children = children
                    // Set parent reference for all children
                    for child in children {
                        child.parent = dirNode
                    }
                    dirNode.sortChildren()
                    nodes.append(dirNode)
                }
            } else if itemURL.pathExtension.lowercased() == "md" {
                // Create file node for markdown files
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

    // MARK: - File I/O

    /// Read content file from disk
    func readContentFile(at url: URL) async throws -> ContentFile {
        let content = try String(contentsOf: url, encoding: .utf8)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let modificationDate = attributes[.modificationDate] as? Date ?? Date()

        // Parse frontmatter and markdown
        let parser = FrontmatterParser.shared
        let (frontmatter, markdown) = parser.parseContent(content)

        let file = ContentFile(
            url: url,
            frontmatter: frontmatter,
            markdownContent: markdown,
            lastModified: modificationDate
        )

        return file
    }

    /// Write content to file at URL
    func writeFile(to url: URL, content: String) async throws {
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var didResume = false

            coordinator.coordinate(writingItemAt: url, options: [], error: &coordinatorError) { url in
                do {
                    try content.write(to: url, atomically: true, encoding: .utf8)
                    continuation.resume()
                    didResume = true
                } catch {
                    continuation.resume(throwing: error)
                    didResume = true
                }
            }

            // Only resume if the coordination block was never executed
            if !didResume, let error = coordinatorError {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Write content file to disk
    func saveContentFile(_ file: ContentFile) async throws {
        try await writeFile(to: file.url, content: file.fullContent)
    }

    /// Create a new markdown file inside the given folder URL
    func createMarkdownFile(in folderURL: URL) async throws -> URL {
        let fileManager = FileManager.default

        // Ensure directory exists
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw FileError.fileNotFound
        }

        // Generate a base name from the current date: YYYY-MM-DD
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: Date())
        let baseName = dateString
        var candidateName = "\(baseName).md"
        var index = 1
        var candidateURL = folderURL.appendingPathComponent(candidateName)

        while fileManager.fileExists(atPath: candidateURL.path) {
            candidateName = "\(baseName)-\(index).md"
            candidateURL = folderURL.appendingPathComponent(candidateName)
            index += 1
        }

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
    func renameFile(at url: URL, to newName: String) async throws -> URL {
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)

        // Check if destination already exists
        if FileManager.default.fileExists(atPath: newURL.path) {
            throw FileError.fileAlreadyExists
        }

        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false

            coordinator.coordinate(writingItemAt: url, options: .forMoving, writingItemAt: newURL, options: .forReplacing, error: &coordinatorError) { oldURL, targetURL in
                do {
                    try FileManager.default.moveItem(at: oldURL, to: targetURL)
                    continuation.resume(returning: targetURL)
                    didResume = true
                } catch {
                    continuation.resume(throwing: error)
                    didResume = true
                }
            }

            if !didResume, let error = coordinatorError {
                continuation.resume(throwing: error)
            }
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

        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false

            coordinator.coordinate(readingItemAt: url, options: [], writingItemAt: newURL, options: .forReplacing, error: &coordinatorError) { sourceURL, destURL in
                do {
                    try fileManager.copyItem(at: sourceURL, to: destURL)
                    continuation.resume(returning: destURL)
                    didResume = true
                } catch {
                    continuation.resume(throwing: error)
                    didResume = true
                }
            }

            if !didResume, let error = coordinatorError {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Move a file or folder to the trash
    func moveToTrash(at url: URL) async throws {
        var trashedURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
    }

    /// Reveal a file in Finder
    func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Copy file path to clipboard
    func copyPathToClipboard(url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
    }

    /// Create a new folder inside the given directory
    func createFolder(in directory: URL, name: String = "New Folder") async throws -> URL {
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
}

// MARK: - File Errors

enum FileError: LocalizedError {
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
