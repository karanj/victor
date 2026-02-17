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

    // MARK: - Delete Operations

    /// Move a file to the trash
    /// - Parameter url: The file URL to trash
    func moveToTrash(at url: URL) async throws {
        try await fileSystemService.moveToTrash(at: url)
    }

    // MARK: - Utility Operations

    /// Reveal a file in Finder
    /// - Parameter url: The file URL to reveal
    func revealInFinder(url: URL) {
        fileSystemService.revealInFinder(url: url)
    }

    /// Copy file path to clipboard
    /// - Parameter url: The file URL whose path to copy
    func copyPathToClipboard(url: URL) {
        fileSystemService.copyPathToClipboard(url: url)
    }
}
