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

    func createMarkdownFile(in directory: URL, siteRoot: URL) async throws -> URL {
        return try await fileSystemService.createMarkdownFile(in: directory, siteRoot: siteRoot)
    }

    func createFolder(in directory: URL) async throws -> URL {
        return try await fileSystemService.createFolder(in: directory)
    }

    // MARK: - Modify Operations

    /// `newName` is a bare filename, not a path.
    func renameFile(at url: URL, to newName: String, siteRoot: URL) async throws -> URL {
        return try await fileSystemService.renameFile(at: url, to: newName, siteRoot: siteRoot)
    }

    func duplicateFile(at url: URL) async throws -> URL {
        return try await fileSystemService.duplicateFile(at: url)
    }

    /// Drag-to-move (victor-sel B.4).
    func moveFile(at url: URL, to targetDirectory: URL, siteRoot: URL) async throws -> URL {
        return try await fileSystemService.moveFile(at: url, to: targetDirectory, siteRoot: siteRoot)
    }

    // MARK: - Delete Operations

    /// Returns the URL the item landed at inside the Trash, when the system
    ///   reports one (victor-und) - see `FileSystemService.moveToTrash`.
    @discardableResult
    func moveToTrash(at url: URL) async throws -> URL? {
        try await fileSystemService.moveToTrash(at: url)
    }

    // MARK: - Utility Operations

    /// Reveals as a single Finder selection.
    func revealInFinder(urls: [URL]) {
        fileSystemService.revealInFinder(urls: urls)
    }

    func revealInFinder(url: URL) {
        fileSystemService.revealInFinder(url: url)
    }

    /// Newline-joined on the pasteboard.
    func copyPathsToClipboard(urls: [URL]) {
        fileSystemService.copyPathsToClipboard(urls: urls)
    }

    func copyPathToClipboard(url: URL) {
        fileSystemService.copyPathToClipboard(url: url)
    }
}
