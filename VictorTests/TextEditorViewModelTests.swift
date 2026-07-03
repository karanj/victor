import XCTest
@testable import Victor

/// Tests for TextEditorViewModel, focused on the dirty-state wiring added by
/// the phase-1 review P0 fix: TextFile-backed edits (css/js/yaml/toml/json
/// routed through TextEditorPanel) previously never reached
/// SiteViewModel.modifiedFileIDs, so the edited-dot, Close Site confirmation,
/// applicationShouldTerminate, and Save All all silently missed dirty
/// plain-text files. TextEditorViewModel now reports dirty/clean state via a
/// weak `siteViewModel` reference plus the FileNode.id it was loaded with
/// (mirroring the pattern EditorViewModel uses for markdown files).
@MainActor
final class TextEditorViewModelTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // See SiteViewModelTests.setUp() - SiteViewModel.init() restores a real
        // bookmarked site in the background, which can race with `await`s in
        // these tests and overwrite fileNodes out from under them. Clearing the
        // bookmark makes that restoration a guaranteed no-op.
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.hugoSiteBookmark)
    }

    // MARK: - Dirty State Reporting Tests

    func testContentDidChangeMarksSiteViewModelFileModified() {
        let siteViewModel = SiteViewModel()
        let node = FileNode(url: URL(fileURLWithPath: "/test/style.css"), isDirectory: false)
        let textFile = TextFile(url: node.url, content: "body {}", lastModified: Date())
        node.textFile = textFile
        siteViewModel.fileNodes = [node]

        let viewModel = TextEditorViewModel()
        viewModel.siteViewModel = siteViewModel
        viewModel.loadFile(textFile, nodeID: node.id)

        XCTAssertFalse(siteViewModel.isFileModified(node.id))

        viewModel.editableContent = "body { color: red; }"
        viewModel.contentDidChange()

        XCTAssertTrue(
            siteViewModel.isFileModified(node.id),
            "Editing a plain-text file must mark it modified on SiteViewModel"
        )
    }

    func testContentDidChangeClearsSiteViewModelFileModifiedWhenBackToOriginal() {
        let siteViewModel = SiteViewModel()
        let node = FileNode(url: URL(fileURLWithPath: "/test/style.css"), isDirectory: false)
        let textFile = TextFile(url: node.url, content: "body {}", lastModified: Date())
        node.textFile = textFile
        siteViewModel.fileNodes = [node]

        let viewModel = TextEditorViewModel()
        viewModel.siteViewModel = siteViewModel
        viewModel.loadFile(textFile, nodeID: node.id)

        viewModel.editableContent = "body { color: red; }"
        viewModel.contentDidChange()
        XCTAssertTrue(siteViewModel.isFileModified(node.id))

        // User hand-edits back to the original content (no save/revert call)
        viewModel.editableContent = "body {}"
        viewModel.contentDidChange()

        XCTAssertFalse(
            siteViewModel.isFileModified(node.id),
            "Returning to the saved content should clear the modified flag"
        )
    }

    func testSaveClearsSiteViewModelFileModifiedAndWritesToDisk() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextEditorViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileURL = tempDir.appendingPathComponent("style.css")
        try "body {}".write(to: fileURL, atomically: true, encoding: .utf8)

        let siteViewModel = SiteViewModel()
        let node = FileNode(url: fileURL, isDirectory: false)
        let textFile = TextFile(url: fileURL, content: "body {}", lastModified: Date())
        node.textFile = textFile
        siteViewModel.fileNodes = [node]

        let viewModel = TextEditorViewModel()
        viewModel.siteViewModel = siteViewModel
        viewModel.loadFile(textFile, nodeID: node.id)

        viewModel.editableContent = "body { color: blue; }"
        viewModel.contentDidChange()
        XCTAssertTrue(siteViewModel.isFileModified(node.id))

        await viewModel.save()

        XCTAssertFalse(
            siteViewModel.isFileModified(node.id),
            "Saving a plain-text file must clear the SiteViewModel modified flag"
        )
        let onDisk = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(onDisk, "body { color: blue; }")
    }

    func testReloadFromDiskClearsSiteViewModelFileModified() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextEditorViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileURL = tempDir.appendingPathComponent("style.css")
        try "body {}".write(to: fileURL, atomically: true, encoding: .utf8)

        let siteViewModel = SiteViewModel()
        let node = FileNode(url: fileURL, isDirectory: false)
        let textFile = TextFile(url: fileURL, content: "body {}", lastModified: Date())
        node.textFile = textFile
        siteViewModel.fileNodes = [node]

        let viewModel = TextEditorViewModel()
        viewModel.siteViewModel = siteViewModel
        viewModel.loadFile(textFile, nodeID: node.id)

        viewModel.editableContent = "body { color: blue; }"
        viewModel.contentDidChange()
        XCTAssertTrue(siteViewModel.isFileModified(node.id))

        await viewModel.reloadFromDisk()

        XCTAssertFalse(
            siteViewModel.isFileModified(node.id),
            "Reverting a plain-text file must clear the SiteViewModel modified flag"
        )
        XCTAssertEqual(viewModel.editableContent, "body {}")
    }
}
