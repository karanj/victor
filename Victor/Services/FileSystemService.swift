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

    /// Read content file from disk
    /// File I/O is performed on a background thread to avoid blocking the main thread
    func readContentFile(at url: URL) async throws -> ContentFile {
        // Perform file I/O on background thread
        try await Task.detached {
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
        }.value
    }

    /// Write content to file at URL
    /// File I/O is performed on a background thread to avoid blocking the main thread
    func writeFile(to url: URL, content: String) async throws {
        // Perform file I/O on background thread
        try await Task.detached {
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

            // Check for errors
            if let error = coordinatorError {
                throw error
            }
            if let error = writeError {
                throw error
            }
        }.value
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
