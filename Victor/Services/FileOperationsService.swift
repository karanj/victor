import Foundation
import AppKit

/// Service for file system operations on content files
///
/// Provides a high-level interface for file operations, delegating
/// to FileSystemService for actual file system work.
@MainActor
final class FileOperationsService {

    /// Shared instance
    static let shared = FileOperationsService()

    /// Underlying file system service
    private let fileSystemService: FileSystemService

    init(fileSystemService: FileSystemService = .shared) {
        self.fileSystemService = fileSystemService
    }

    // MARK: - Create Operations

    /// Create a new markdown file in the given directory
    /// - Parameters:
    ///   - directory: The directory URL to create the file in
    ///   - siteRoot: The site root URL for path traversal validation
    /// - Returns: The URL of the newly created file
    func createMarkdownFile(in directory: URL, siteRoot: URL) async throws -> URL {
        return try await fileSystemService.createMarkdownFile(in: directory, siteRoot: siteRoot)
    }

    /// Create a new folder in the given directory
    /// - Parameter directory: The parent directory URL
    /// - Returns: The URL of the newly created folder
    func createFolder(in directory: URL) async throws -> URL {
        return try await fileSystemService.createFolder(in: directory)
    }

    // MARK: - Modify Operations

    /// Rename a file
    /// - Parameters:
    ///   - url: The current file URL
    ///   - newName: The new filename (just the name, not the full path)
    ///   - siteRoot: The site root URL for path traversal validation
    /// - Returns: The new file URL after renaming
    func renameFile(at url: URL, to newName: String, siteRoot: URL) async throws -> URL {
        return try await fileSystemService.renameFile(at: url, to: newName, siteRoot: siteRoot)
    }

    /// Duplicate a file
    /// - Parameter url: The file URL to duplicate
    /// - Returns: The URL of the duplicate file
    func duplicateFile(at url: URL) async throws -> URL {
        return try await fileSystemService.duplicateFile(at: url)
    }

    /// Move a file or folder to a different directory within the site
    /// (drag-to-move, victor-sel B.4)
    /// - Parameters:
    ///   - url: the file/folder's current URL
    ///   - targetDirectory: the destination folder's URL
    ///   - siteRoot: the site root URL for path traversal validation
    /// - Returns: the new URL after the move
    func moveFile(at url: URL, to targetDirectory: URL, siteRoot: URL) async throws -> URL {
        return try await fileSystemService.moveFile(at: url, to: targetDirectory, siteRoot: siteRoot)
    }

    // MARK: - Delete Operations

    /// Move a file to the trash
    /// - Parameter url: The file URL to trash
    /// - Returns: the URL the item landed at inside the Trash, when the system
    ///   reports one (victor-und) - see `FileSystemService.moveToTrash`.
    @discardableResult
    func moveToTrash(at url: URL) async throws -> URL? {
        try await fileSystemService.moveToTrash(at: url)
    }

    // MARK: - Utility Operations

    /// Reveal one or more files/folders in Finder as a single selection
    /// - Parameter urls: the file URLs to reveal
    func revealInFinder(urls: [URL]) {
        fileSystemService.revealInFinder(urls: urls)
    }

    /// Reveal a single file in Finder
    /// - Parameter url: The file URL to reveal
    func revealInFinder(url: URL) {
        fileSystemService.revealInFinder(url: url)
    }

    /// Copy one or more file paths to the pasteboard, newline-joined
    /// - Parameter urls: the file URLs whose paths to copy
    func copyPathsToClipboard(urls: [URL]) {
        fileSystemService.copyPathsToClipboard(urls: urls)
    }

    /// Copy a single file's path to the clipboard
    /// - Parameter url: The file URL whose path to copy
    func copyPathToClipboard(url: URL) {
        fileSystemService.copyPathToClipboard(url: url)
    }
}
