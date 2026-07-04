import XCTest
@testable import Victor

/// Tests for the drag-and-drop image import flow (W3.3 / victor-dnd):
/// - `ImageDropPathResolver`: pure path-mapping logic (page bundle vs static/)
/// - `FileSystemService.importFile`: the actual copy, shared by the sidebar folder
///   drop and the editor's image drop so neither invents its own copy code path
final class ImageDropImportTests: XCTestCase {

    // MARK: - ImageDropPathResolver

    func testDestinationUsesStaticRootWhenNotInPageBundle() {
        let siteRoot = URL(fileURLWithPath: "/tmp/mysite")

        let destination = ImageDropPathResolver.destination(
            currentFileParentURL: siteRoot.appendingPathComponent("content/posts"),
            parentIsPageBundle: false,
            siteRoot: siteRoot
        )

        XCTAssertEqual(destination.directory, siteRoot.appendingPathComponent("static"))
        XCTAssertEqual(destination.style, .siteRootRelative)
        XCTAssertEqual(destination.style.path(for: "photo.png"), "/photo.png")
    }

    func testDestinationUsesStaticRootWhenParentURLUnknown() {
        let siteRoot = URL(fileURLWithPath: "/tmp/mysite")

        let destination = ImageDropPathResolver.destination(
            currentFileParentURL: nil,
            parentIsPageBundle: false,
            siteRoot: siteRoot
        )

        XCTAssertEqual(destination.directory, siteRoot.appendingPathComponent("static"))
    }

    func testDestinationUsesPageBundleFolderWhenInBundle() {
        let siteRoot = URL(fileURLWithPath: "/tmp/mysite")
        let bundleURL = siteRoot.appendingPathComponent("content/posts/my-post")

        let destination = ImageDropPathResolver.destination(
            currentFileParentURL: bundleURL,
            parentIsPageBundle: true,
            siteRoot: siteRoot
        )

        XCTAssertEqual(destination.directory, bundleURL)
        XCTAssertEqual(destination.style, .pageBundleRelative)
        XCTAssertEqual(destination.style.path(for: "photo.png"), "photo.png")
    }

    func testMarkdownImageReferenceForSiteRootRelative() {
        let destURL = URL(fileURLWithPath: "/tmp/mysite/static/sunset.png")
        let reference = ImageDropPathResolver.markdownImageReference(for: destURL, style: .siteRootRelative)
        XCTAssertEqual(reference, "![sunset](/sunset.png)")
    }

    func testMarkdownImageReferenceForPageBundleRelative() {
        let destURL = URL(fileURLWithPath: "/tmp/mysite/content/posts/my-post/sunset.png")
        let reference = ImageDropPathResolver.markdownImageReference(for: destURL, style: .pageBundleRelative)
        XCTAssertEqual(reference, "![sunset](sunset.png)")
    }

    // MARK: - FileSystemService.importFile

    var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageDropImportTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func testImportFileCopiesContent() throws {
        let siteRoot = tempDirectory.appendingPathComponent("site")
        let destDir = siteRoot.appendingPathComponent("static")
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let sourceURL = tempDirectory.appendingPathComponent("external-photo.png")
        let content = "fake-image-bytes"
        try content.write(to: sourceURL, atomically: true, encoding: .utf8)

        let destURL = try FileSystemService.shared.importFile(from: sourceURL, into: destDir, siteRoot: siteRoot)

        XCTAssertEqual(destURL.lastPathComponent, "external-photo.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destURL.path))
        XCTAssertEqual(try String(contentsOf: destURL, encoding: .utf8), content)
        // Source file is untouched (copy, not move)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    func testImportFileCreatesDestinationDirectoryIfMissing() throws {
        let siteRoot = tempDirectory.appendingPathComponent("site")
        try FileManager.default.createDirectory(at: siteRoot, withIntermediateDirectories: true)
        let destDir = siteRoot.appendingPathComponent("static") // deliberately not created

        let sourceURL = tempDirectory.appendingPathComponent("photo.png")
        try "data".write(to: sourceURL, atomically: true, encoding: .utf8)

        let destURL = try FileSystemService.shared.importFile(from: sourceURL, into: destDir, siteRoot: siteRoot)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destURL.path))
    }

    func testImportFileAvoidsNameCollisions() throws {
        let siteRoot = tempDirectory.appendingPathComponent("site")
        let destDir = siteRoot.appendingPathComponent("static")
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        // A file with the same name already exists at the destination
        let existing = destDir.appendingPathComponent("photo.png")
        try "existing".write(to: existing, atomically: true, encoding: .utf8)

        let sourceURL = tempDirectory.appendingPathComponent("photo.png")
        try "new-content".write(to: sourceURL, atomically: true, encoding: .utf8)

        let destURL = try FileSystemService.shared.importFile(from: sourceURL, into: destDir, siteRoot: siteRoot)

        XCTAssertEqual(destURL.lastPathComponent, "photo 2.png")
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "existing")
        XCTAssertEqual(try String(contentsOf: destURL, encoding: .utf8), "new-content")

        // A second import of a file with the same original name should skip both
        // "photo.png" and "photo 2.png" and land on "photo 3.png"
        let anotherSourceDir = tempDirectory.appendingPathComponent("more")
        try FileManager.default.createDirectory(at: anotherSourceDir, withIntermediateDirectories: true)
        let anotherSource = anotherSourceDir.appendingPathComponent("photo.png")
        try "third".write(to: anotherSource, atomically: true, encoding: .utf8)

        let destURL2 = try FileSystemService.shared.importFile(from: anotherSource, into: destDir, siteRoot: siteRoot)
        XCTAssertEqual(destURL2.lastPathComponent, "photo 3.png")
    }

    func testImportFileRejectsDestinationOutsideSiteRoot() throws {
        let siteRoot = tempDirectory.appendingPathComponent("site")
        try FileManager.default.createDirectory(at: siteRoot, withIntermediateDirectories: true)
        let outsideDir = tempDirectory.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)

        let sourceURL = tempDirectory.appendingPathComponent("photo.png")
        try "data".write(to: sourceURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try FileSystemService.shared.importFile(from: sourceURL, into: outsideDir, siteRoot: siteRoot)
        ) { error in
            XCTAssertEqual(error as? FileError, .accessDenied)
        }
    }
}
