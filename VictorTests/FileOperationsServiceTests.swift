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
        let newURL = try await service.createMarkdownFile(in: tempDirectory, siteRoot: tempDirectory)

        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertEqual(newURL.pathExtension, "md")
    }

    func testCreateMarkdownFileCreatesUniqueNames() async throws {
        let url1 = try await service.createMarkdownFile(in: tempDirectory, siteRoot: tempDirectory)
        let url2 = try await service.createMarkdownFile(in: tempDirectory, siteRoot: tempDirectory)

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

        let newURL = try await service.renameFile(at: originalURL, to: "renamed.md", siteRoot: tempDirectory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertEqual(newURL.lastPathComponent, "renamed.md")
    }

    func testRenameFilePreservesContent() async throws {
        let content = "# Hello World\n\nThis is test content."
        let originalURL = tempDirectory.appendingPathComponent("test.md")
        try content.write(to: originalURL, atomically: true, encoding: .utf8)

        let newURL = try await service.renameFile(at: originalURL, to: "new-name.md", siteRoot: tempDirectory)

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

    // MARK: - Path Traversal Protection Tests

    func testRenameFileRejectsPathTraversal() async throws {
        let originalURL = tempDirectory.appendingPathComponent("test.md")
        try "# Test".write(to: originalURL, atomically: true, encoding: .utf8)

        // "../evil.md" is already rejected by isSafeFilename, but verify it throws accessDenied
        do {
            _ = try await service.renameFile(at: originalURL, to: "../evil.md", siteRoot: tempDirectory)
            XCTFail("Expected accessDenied error for path traversal rename")
        } catch let error as FileError {
            XCTAssertEqual(error, .accessDenied)
        }
    }

    func testValidatePathRejectsSiblingDirectoryWithRootPrefix() throws {
        // "/tmp/.../site-evil" shares a string prefix with "/tmp/.../site" but is outside it.
        // A plain hasPrefix check wrongly accepts it.
        let siteRoot = tempDirectory.appendingPathComponent("site")
        let sibling = tempDirectory.appendingPathComponent("site-evil").appendingPathComponent("file.md")
        try FileManager.default.createDirectory(at: siteRoot, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try FileSystemService.shared.validatePathWithinSite(sibling, siteRoot: siteRoot),
            "A sibling directory sharing the site root's name prefix must be rejected"
        )

        // Sanity: paths genuinely inside the root still validate
        XCTAssertNoThrow(
            try FileSystemService.shared.validatePathWithinSite(
                siteRoot.appendingPathComponent("content/post.md"), siteRoot: siteRoot)
        )
    }

    func testRenameFileRejectsEscapingSiteRoot() async throws {
        // Create a subdirectory as the "site root" and a file inside it
        let siteRoot = tempDirectory.appendingPathComponent("mysite")
        let contentDir = siteRoot.appendingPathComponent("content")
        try FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)

        let originalURL = contentDir.appendingPathComponent("post.md")
        try "# Post".write(to: originalURL, atomically: true, encoding: .utf8)

        // Rename to a name that would land outside the site root
        // The file is at mysite/content/post.md, renaming within content/ is fine,
        // but we use a separate siteRoot to test the validation
        let outsideRoot = tempDirectory.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)

        // Direct test on FileSystemService with a restrictive siteRoot
        let fsService = FileSystemService.shared
        do {
            // File is at mysite/content/post.md, siteRoot is mysite/content
            // Renaming to "safe.md" should work with content as siteRoot
            let result = try await fsService.renameFile(at: originalURL, to: "safe.md", siteRoot: contentDir)
            XCTAssertEqual(result.lastPathComponent, "safe.md")
        }

        // Now test that creating a file in a directory outside siteRoot fails
        do {
            _ = try await fsService.createMarkdownFile(in: outsideRoot, siteRoot: siteRoot)
            XCTFail("Expected accessDenied error for create outside site root")
        } catch let error as FileError {
            XCTAssertEqual(error, .accessDenied)
        }
    }

    func testCreateMarkdownFileValidatesWithinSiteRoot() async throws {
        // Create two separate directories - one as site root, one outside
        let siteRoot = tempDirectory.appendingPathComponent("site")
        let outsideDir = tempDirectory.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: siteRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)

        let fsService = FileSystemService.shared

        // Creating inside site root should succeed
        let validURL = try await fsService.createMarkdownFile(in: siteRoot, siteRoot: siteRoot)
        XCTAssertTrue(validURL.path.hasPrefix(siteRoot.standardized.path))

        // Creating outside site root should throw accessDenied
        do {
            _ = try await fsService.createMarkdownFile(in: outsideDir, siteRoot: siteRoot)
            XCTFail("Expected accessDenied error for create outside site root")
        } catch let error as FileError {
            XCTAssertEqual(error, .accessDenied)
        }
    }

    // MARK: - saveContentFile / readContentFile (WP3.5 Cluster 1 signature change)

    /// `saveContentFile` changed from taking a `ContentFile` object to taking an
    /// extracted `url`/`content` pair (so the non-Sendable `ContentFile` class never
    /// has to cross the actor boundary). This confirms the new signature still writes
    /// exactly the given bytes to disk - not just that it compiles.
    func testSaveContentFileWritesExactBytesForGivenURLAndContent() async throws {
        let fileURL = tempDirectory.appendingPathComponent("saved.md")
        try "stale on-disk content".write(to: fileURL, atomically: true, encoding: .utf8)

        let fsService = FileSystemService.shared
        try await fsService.saveContentFile(url: fileURL, content: "---\ntitle: Hi\n---\nbody text")

        let onDisk = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(onDisk, "---\ntitle: Hi\n---\nbody text")
    }

    /// `readContentFile` now crosses its `Task.detached` boundary as a private
    /// Sendable (String, Date) snapshot and constructs the `ContentFile` class only
    /// after returning - confirms the round trip still produces correct frontmatter
    /// + markdown separation end to end, not just that the boundary type-checks.
    func testReadContentFileRoundTripsFrontmatterAndMarkdown() async throws {
        let fileURL = tempDirectory.appendingPathComponent("read.md")
        let raw = "---\ntitle: Round Trip\n---\nHello body"
        try raw.write(to: fileURL, atomically: true, encoding: .utf8)

        let fsService = FileSystemService.shared
        let contentFile = try await fsService.readContentFile(at: fileURL)

        XCTAssertEqual(contentFile.frontmatter?.title, "Round Trip")
        XCTAssertEqual(contentFile.markdownContent, "Hello body")
        XCTAssertEqual(contentFile.url, fileURL)
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
