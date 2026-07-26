import XCTest
@testable import Victor

/// Tests for TextEditorViewModel's dirty-state wiring. TextFile-backed edits (css/js/yaml
/// via TextEditorPanel) previously never reached `modifiedFileIDs`, so the edited-dot,
/// Close Site confirmation, terminate handler and Save All all missed them.
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

    // MARK: - Auto-Save Debounce Registry (victor-rnm TOCTOU hardening, post-launch review)

    /// `save()` writes via `@concurrent` `writeFile`, which doesn't observe
    /// `Task.isCancelled`, so a plain `.cancel()` can't stop an in-flight write - only the
    /// node-ID registry lets rename cancel-AND-AWAIT. Asserts the registry directly so a
    /// broken nodeID/instance wiring fails rather than passing for the wrong reason.
    func testRenameFileCancelsAndDeregistersTextEditorViewModelsRegisteredDebounce() async throws {
        let previousDelay = AppSettings.shared.autoSaveDelay
        let previousEnabled = AppSettings.shared.isAutoSaveEnabled
        AppSettings.shared.autoSaveDelay = 5.0 // long enough to still be pending when we check
        AppSettings.shared.isAutoSaveEnabled = true
        defer {
            AppSettings.shared.autoSaveDelay = previousDelay
            AppSettings.shared.isAutoSaveEnabled = previousEnabled
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextEditorViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileURL = tempDir.appendingPathComponent("style.css")
        try "body {}".write(to: fileURL, atomically: true, encoding: .utf8)

        // Production wiring always has SiteViewModel and TextEditorViewModel
        // sharing ONE AutoSaveService instance (both default to `.shared`) - a
        // fresh instance here is for cross-test isolation only, and it must be
        // the SAME instance passed to both, or renameFile's cancelDebounce
        // would be cancelling a registry a different actor instance never saw.
        let sharedAutoSaveService = AutoSaveService()
        let siteViewModel = SiteViewModel(fileSystemService: FileSystemService(), autoSaveService: sharedAutoSaveService)
        siteViewModel.site = await HugoSite.create(rootURL: tempDir)
        let node = FileNode(url: fileURL, isDirectory: false)
        let textFile = TextFile(url: fileURL, content: "body {}", lastModified: Date())
        node.textFile = textFile
        siteViewModel.fileNodes = [node]

        let viewModel = TextEditorViewModel(autoSaveService: sharedAutoSaveService)
        viewModel.siteViewModel = siteViewModel
        viewModel.loadFile(textFile, nodeID: node.id)

        viewModel.editableContent = "body { color: blue; }"
        viewModel.contentDidChange() // schedules the debounce, registers with `sharedAutoSaveService`

        // Give the debounce Task a moment to reach its first await (registerDebounce).
        try await Task.sleep(for: .milliseconds(50))

        let registeredCount = await sharedAutoSaveService.debounceRegistrationCount
        XCTAssertEqual(registeredCount, 1,
                       "TextEditorViewModel must register its debounce Task with AutoSaveService under the node's id")

        await siteViewModel.renameFile(node: node, to: "renamed.css")

        let countAfterRename = await sharedAutoSaveService.debounceRegistrationCount
        XCTAssertEqual(countAfterRename, 0,
                       "renameFile's cancelDebounce must find and fully cancel-and-await the SAME registered Task - " +
                       "if the nodeID/instance wiring were broken this would still show 1")

        // The cancelled Task never wrote: old path is gone (renamed away), the
        // new path still holds its pre-edit on-disk content, and the edit
        // itself is still safe - unlike markdown, TextFile edits live directly
        // on the shared model object (not a separate per-file cache, see
        // CLAUDE.md's Content State Dual Storage section), so it isn't lost.
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        let renamedURL = tempDir.appendingPathComponent("renamed.css")
        let renamedContent = try String(contentsOf: renamedURL, encoding: .utf8)
        XCTAssertEqual(renamedContent, "body {}",
                       "a cancelled (still-sleeping) debounce must not write at all - not to the old path, not to the new one either")
        XCTAssertEqual(textFile.content, "body { color: blue; }",
                       "the edit must survive on the shared TextFile object, ready for the next auto-save or manual save")
    }
}
