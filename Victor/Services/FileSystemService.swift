import Foundation
import AppKit

/// Service for file system operations and folder management
@MainActor
class FileSystemService {
    static let shared = FileSystemService()

    private init() {}

    // MARK: - Folder Selection

    /// Present folder selection dialog and return selected URL
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

    /// Scan directory and build file tree
    /// Phase 1: Flat list of markdown files
    /// Phase 4: Will be enhanced to build hierarchical tree
    func scanDirectory(at url: URL) throws -> [FileNode] {
        var nodes: [FileNode] = []

        // Get content directory
        let contentURL = url.appendingPathComponent("content")

        guard FileManager.default.fileExists(atPath: contentURL.path) else {
            // If no content directory, scan root for .md files
            return try scanForMarkdownFiles(in: url, relativeTo: url)
        }

        // Scan content directory recursively
        nodes = try scanForMarkdownFiles(in: contentURL, relativeTo: contentURL)

        return nodes
    }

    /// Recursively scan for markdown files
    private func scanForMarkdownFiles(in directory: URL, relativeTo baseURL: URL) throws -> [FileNode] {
        var nodes: [FileNode] = []

        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nodes
        }

        for case let fileURL as URL in enumerator {
            _ = try fileURL.resourceValues(forKeys: Set(resourceKeys))

            // Phase 1: Only include markdown files (flat list)
            // Phase 4: Will include directories for hierarchy
            if fileURL.pathExtension.lowercased() == "md" {
                let node = FileNode(url: fileURL, isDirectory: false)
                nodes.append(node)
            }
        }

        // Sort alphabetically
        nodes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return nodes
    }

    // MARK: - File I/O

    /// Read content file from disk
    func readContentFile(at url: URL) async throws -> ContentFile {
        let content = try String(contentsOf: url, encoding: .utf8)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let modificationDate = attributes[.modificationDate] as? Date ?? Date()

        // Phase 1: Just store raw content
        // Phase 3: Will parse frontmatter
        let file = ContentFile(
            url: url,
            frontmatter: nil,
            markdownContent: content,
            lastModified: modificationDate
        )

        return file
    }

    /// Write content file to disk
    func saveContentFile(_ file: ContentFile) async throws {
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            coordinator.coordinate(writingItemAt: file.url, options: [], error: &coordinatorError) { url in
                do {
                    try file.fullContent.write(to: url, atomically: true, encoding: .utf8)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            if let error = coordinatorError {
                continuation.resume(throwing: error)
            }
        }
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
}

// MARK: - File Errors

enum FileError: LocalizedError {
    case accessDenied
    case fileNotFound
    case corruptedFrontmatter
    case writeFailure
    case notAHugoSite

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
        }
    }
}
