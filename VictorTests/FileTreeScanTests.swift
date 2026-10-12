import XCTest
@testable import Victor

/// `FileSystemService.scanDirectory` - what the sidebar tree shows under `content/`.
final class FileTreeScanTests: XCTestCase {
    private var siteURL: URL!

    override func setUpWithError() throws {
        siteURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileTreeScanTests-\(UUID().uuidString)")
        try write("hugo.toml", "title = 'x'")
        // Branch bundle with page resources, incl. a resources-only subfolder
        try write("content/apps/dose-tracker/_index.md", "---\ntitle: x\n---\n")
        try write("content/apps/dose-tracker/privacy.md", "x")
        try write("content/apps/dose-tracker/icon.png", "png")
        try write("content/apps/dose-tracker/screenshots/01-home.jpg", "jpg")
        // Leaf bundle
        try write("content/posts/trip/index.md", "x")
        try write("content/posts/trip/photo.jpg", "jpg")
        // Not a bundle: loose non-markdown stays hidden, as before
        try write("content/posts/a.md", "x")
        try write("content/posts/stray.png", "png")
        try write("content/scratch/notes.txt", "txt")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: siteURL)
    }

    private func write(_ path: String, _ text: String) throws {
        let url = siteURL.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func node(_ path: String, in nodes: [FileNode]) -> FileNode? {
        var current = nodes
        var found: FileNode?
        for part in path.split(separator: "/") {
            found = current.first { $0.name == part }
            current = found?.children ?? []
        }
        return found
    }

    func testBranchBundleShowsItsResourcesAndResourceFolders() throws {
        let tree = try FileSystemService().scanDirectory(at: siteURL)
        XCTAssertNotNil(node("content/apps/dose-tracker/icon.png", in: tree))
        XCTAssertNotNil(node("content/apps/dose-tracker/screenshots", in: tree))
        XCTAssertNotNil(node("content/apps/dose-tracker/screenshots/01-home.jpg", in: tree))
        XCTAssertNotNil(node("content/apps/dose-tracker/privacy.md", in: tree))
    }

    func testLeafBundleShowsItsResources() throws {
        let tree = try FileSystemService().scanDirectory(at: siteURL)
        XCTAssertNotNil(node("content/posts/trip/photo.jpg", in: tree))
    }

    func testNonMarkdownOutsideBundlesStaysHidden() throws {
        let tree = try FileSystemService().scanDirectory(at: siteURL)
        XCTAssertNotNil(node("content/posts/a.md", in: tree))
        XCTAssertNil(node("content/posts/stray.png", in: tree))
        XCTAssertNil(node("content/scratch", in: tree), "folder with no markdown and no bundle stays hidden")
    }
}
