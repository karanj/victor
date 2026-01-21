import XCTest
@testable import Victor

/// Tests for FileOperationsService - file system operations with callbacks
@MainActor
final class FileOperationsServiceTests: XCTestCase {

    var tempDirectory: URL!
    var service: FileOperationsService!

    override func setUp() async throws {
        // Create a temporary directory for test files
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileOperationsServiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        service = FileOperationsService()
    }

    override func tearDown() async throws {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - Create Markdown File Tests

    func testCreateMarkdownFileReturnsURL() async throws {
        let newURL = try await service.createMarkdownFile(in: tempDirectory)

        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertEqual(newURL.pathExtension, "md")
    }

    func testCreateMarkdownFileCreatesUniqueNames() async throws {
        let url1 = try await service.createMarkdownFile(in: tempDirectory)
        let url2 = try await service.createMarkdownFile(in: tempDirectory)

        XCTAssertNotEqual(url1, url2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url2.path))
    }

    // MARK: - Create Folder Tests

    func testCreateFolderReturnsURL() async throws {
        let newURL = try await service.createFolder(in: tempDirectory)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    // MARK: - Rename File Tests

    func testRenameFileChangesName() async throws {
        // Create a test file
        let originalURL = tempDirectory.appendingPathComponent("original.md")
        try "# Test".write(to: originalURL, atomically: true, encoding: .utf8)

        let newURL = try await service.renameFile(at: originalURL, to: "renamed.md")

        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertEqual(newURL.lastPathComponent, "renamed.md")
    }

    func testRenameFilePreservesContent() async throws {
        let content = "# Hello World\n\nThis is test content."
        let originalURL = tempDirectory.appendingPathComponent("test.md")
        try content.write(to: originalURL, atomically: true, encoding: .utf8)

        let newURL = try await service.renameFile(at: originalURL, to: "new-name.md")

        let readContent = try String(contentsOf: newURL, encoding: .utf8)
        XCTAssertEqual(readContent, content)
    }

    // MARK: - Duplicate File Tests

    func testDuplicateFileCreatesNewFile() async throws {
        let originalURL = tempDirectory.appendingPathComponent("original.md")
        try "# Original".write(to: originalURL, atomically: true, encoding: .utf8)

        let duplicateURL = try await service.duplicateFile(at: originalURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: duplicateURL.path))
        XCTAssertNotEqual(originalURL, duplicateURL)
    }

    func testDuplicateFileCopiesContent() async throws {
        let content = "# Original Content"
        let originalURL = tempDirectory.appendingPathComponent("file.md")
        try content.write(to: originalURL, atomically: true, encoding: .utf8)

        let duplicateURL = try await service.duplicateFile(at: originalURL)

        let duplicateContent = try String(contentsOf: duplicateURL, encoding: .utf8)
        XCTAssertEqual(duplicateContent, content)
    }

    // MARK: - Move to Trash Tests

    func testMoveToTrashRemovesFile() async throws {
        let fileURL = tempDirectory.appendingPathComponent("to-delete.md")
        try "# Delete me".write(to: fileURL, atomically: true, encoding: .utf8)

        try await service.moveToTrash(at: fileURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - Reveal in Finder Tests

    func testRevealInFinderDoesNotThrow() {
        // Just verify it doesn't throw - actual Finder behavior can't be tested
        let fileURL = tempDirectory.appendingPathComponent("test.md")
        service.revealInFinder(url: fileURL)
        // No assertion needed - just checking it doesn't crash
    }

    // MARK: - Copy Path Tests

    func testCopyPathSetsClipboard() {
        let fileURL = tempDirectory.appendingPathComponent("test.md")

        service.copyPathToClipboard(url: fileURL)

        // Check pasteboard
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        let pastedString = pasteboard.string(forType: .string)
        XCTAssertEqual(pastedString, fileURL.path)
        #endif
    }
}
