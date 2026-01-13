import XCTest
@testable import Victor

/// Tests for EditorViewModel focusing on race conditions during file switching
@MainActor
final class EditorViewModelTests: XCTestCase {

    // MARK: - Test Fixtures

    var siteViewModel: SiteViewModel!
    var testFileNode1: FileNode!
    var testFileNode2: FileNode!
    var testContentFile1: ContentFile!
    var testContentFile2: ContentFile!

    override func setUp() async throws {
        try await super.setUp()

        // Create test site view model
        siteViewModel = SiteViewModel()

        // Create test URLs
        let tempDir = FileManager.default.temporaryDirectory
        let testURL1 = tempDir.appendingPathComponent("test1.md")
        let testURL2 = tempDir.appendingPathComponent("test2.md")

        // Create test file nodes
        testFileNode1 = FileNode(url: testURL1, isDirectory: false, isPageBundle: false)
        testFileNode2 = FileNode(url: testURL2, isDirectory: false, isPageBundle: false)

        // Create test content files
        let frontmatter1 = Frontmatter(rawContent: "---\ntitle: Test File 1\n---", format: .yaml)
        frontmatter1.title = "Test File 1"
        testContentFile1 = ContentFile(
            url: testURL1,
            frontmatter: frontmatter1,
            markdownContent: "This is test file 1 content",
            lastModified: Date()
        )
        testFileNode1.contentFile = testContentFile1

        let frontmatter2 = Frontmatter(rawContent: "---\ntitle: Test File 2\n---", format: .yaml)
        frontmatter2.title = "Test File 2"
        testContentFile2 = ContentFile(
            url: testURL2,
            frontmatter: frontmatter2,
            markdownContent: "This is test file 2 content",
            lastModified: Date()
        )
        testFileNode2.contentFile = testContentFile2

        // Set up file nodes in site view model
        siteViewModel.fileNodes = [testFileNode1, testFileNode2]
    }

    override func tearDown() async throws {
        siteViewModel = nil
        testFileNode1 = nil
        testFileNode2 = nil
        testContentFile1 = nil
        testContentFile2 = nil
        try await super.tearDown()
    }

    // MARK: - Content Capture Tests

    /// Test that the per-file content storage preserves edits when switching files
    /// This is a prerequisite for preventing data corruption
    func testPerFileContentStoragePreservesEditsWhenSwitching() {
        // Select file 1 and set content
        siteViewModel.selectedNode = testFileNode1
        siteViewModel.currentEditingContent = "File 1 modified content"

        // Switch to file 2 and set different content
        siteViewModel.selectedNode = testFileNode2
        siteViewModel.currentEditingContent = "File 2 modified content"

        // Switch back to file 1
        siteViewModel.selectedNode = testFileNode1

        // File 1's content should be preserved
        XCTAssertEqual(siteViewModel.currentEditingContent, "File 1 modified content",
                       "Per-file storage should preserve file 1's edits")

        // Switch back to file 2
        siteViewModel.selectedNode = testFileNode2

        // File 2's content should be preserved
        XCTAssertEqual(siteViewModel.currentEditingContent, "File 2 modified content",
                       "Per-file storage should preserve file 2's edits")
    }

    /// Test that EditorViewModel detects when it's no longer the selected file
    /// This is critical for preventing stale ViewModels from modifying file state
    func testEditorViewModelDetectsWhenNoLongerSelected() {
        // Select file 1
        siteViewModel.selectedNode = testFileNode1
        siteViewModel.currentEditingContent = testContentFile1.markdownContent

        // Create editor view model for file 1
        let editorVM1 = EditorViewModel(
            fileNode: testFileNode1,
            contentFile: testContentFile1,
            siteViewModel: siteViewModel
        )

        // Modify content
        editorVM1.editableContent = "Modified content"
        editorVM1.handleContentChange()

        // File 1 should be marked as modified
        XCTAssertTrue(siteViewModel.isFileModified(testFileNode1.id))

        // Switch to file 2
        siteViewModel.selectedNode = testFileNode2

        // Old editor view model's handleContentChange should be a no-op now
        // because it checks if its fileNode is still selected
        editorVM1.handleContentChange()

        // File 1 should still be marked as modified (not cleared by stale ViewModel)
        XCTAssertTrue(siteViewModel.isFileModified(testFileNode1.id),
                      "Stale ViewModel should not clear modified state of its file")
    }

    // MARK: - False Unsaved Changes Tests

    /// Test that handleContentChange() guards against spurious onChange triggers after file switch
    /// This prevents false "unsaved changes" indicators when switching files
    func testHandleContentChangeGuardsAgainstFileSwitchSpuriousTriggers() {
        // Select file 1
        siteViewModel.selectedNode = testFileNode1
        siteViewModel.currentEditingContent = testContentFile1.markdownContent

        // Create editor view model for file 1
        let editorVM = EditorViewModel(
            fileNode: testFileNode1,
            contentFile: testContentFile1,
            siteViewModel: siteViewModel
        )

        // File 1 should not be marked as modified initially
        XCTAssertFalse(siteViewModel.isFileModified(testFileNode1.id),
                       "File 1 should not be modified initially")

        // Switch to file 2 (simulating user switching files)
        siteViewModel.selectedNode = testFileNode2
        siteViewModel.currentEditingContent = testContentFile2.markdownContent

        // The old EditorViewModel (for file 1) might still be alive and its
        // editableContent computed property now returns file 2's content.
        // If handleContentChange() is called without the guard, it would
        // incorrectly mark file 1 as modified.

        // Call handleContentChange() on the OLD editor view model
        editorVM.handleContentChange()

        // File 1 should STILL NOT be marked as modified because the guard
        // checks that fileNode.id == siteViewModel.selectedNode?.id
        XCTAssertFalse(siteViewModel.isFileModified(testFileNode1.id),
                       "File 1 should not be marked as modified after file switch")
    }

    /// Test that switching files quickly doesn't leave behind false modified indicators
    func testRapidFileSwitchingDoesNotLeaveModifiedIndicators() {
        // Select and switch between files rapidly without making changes
        siteViewModel.selectedNode = testFileNode1
        siteViewModel.currentEditingContent = testContentFile1.markdownContent

        let editorVM1 = EditorViewModel(
            fileNode: testFileNode1,
            contentFile: testContentFile1,
            siteViewModel: siteViewModel
        )

        // Switch to file 2
        siteViewModel.selectedNode = testFileNode2
        siteViewModel.currentEditingContent = testContentFile2.markdownContent

        let editorVM2 = EditorViewModel(
            fileNode: testFileNode2,
            contentFile: testContentFile2,
            siteViewModel: siteViewModel
        )

        // Switch back to file 1
        siteViewModel.selectedNode = testFileNode1
        siteViewModel.currentEditingContent = testContentFile1.markdownContent

        // Trigger content change handlers (simulating SwiftUI .onChange)
        editorVM1.handleContentChange()
        editorVM2.handleContentChange()

        // Neither file should be marked as modified
        XCTAssertFalse(siteViewModel.isFileModified(testFileNode1.id),
                       "File 1 should not be modified after rapid switching")
        XCTAssertFalse(siteViewModel.isFileModified(testFileNode2.id),
                       "File 2 should not be modified after rapid switching")
        XCTAssertFalse(siteViewModel.hasUnsavedChanges,
                       "No files should have unsaved changes after rapid switching")
    }

    // MARK: - Computed Property Safety Tests

    /// Test that editableContent computed property returns correct file's content
    func testEditableContentReflectsCurrentlySelectedFile() {
        // Select file 1
        siteViewModel.selectedNode = testFileNode1
        siteViewModel.currentEditingContent = testContentFile1.markdownContent

        let editorVM1 = EditorViewModel(
            fileNode: testFileNode1,
            contentFile: testContentFile1,
            siteViewModel: siteViewModel
        )

        // Verify editor VM returns file 1's content
        XCTAssertEqual(editorVM1.editableContent, testContentFile1.markdownContent)

        // Switch to file 2
        siteViewModel.selectedNode = testFileNode2
        siteViewModel.currentEditingContent = testContentFile2.markdownContent

        // The OLD editor VM's computed property now returns file 2's content (!)
        // This is the root cause of the bug - computed properties depend on global state
        XCTAssertEqual(editorVM1.editableContent, testContentFile2.markdownContent,
                       "Computed property returns wrong file's content after switch (expected behavior showing the bug)")

        // Create new editor VM for file 2
        let editorVM2 = EditorViewModel(
            fileNode: testFileNode2,
            contentFile: testContentFile2,
            siteViewModel: siteViewModel
        )

        // New editor VM should return file 2's content
        XCTAssertEqual(editorVM2.editableContent, testContentFile2.markdownContent)
    }

    /// Test that modifications are tracked per-file correctly
    func testModificationsAreTrackedPerFile() {
        // Select and modify file 1
        siteViewModel.selectedNode = testFileNode1
        siteViewModel.currentEditingContent = testContentFile1.markdownContent

        let editorVM1 = EditorViewModel(
            fileNode: testFileNode1,
            contentFile: testContentFile1,
            siteViewModel: siteViewModel
        )

        // Modify file 1
        editorVM1.editableContent = "Modified content 1"
        editorVM1.handleContentChange()

        // File 1 should be modified
        XCTAssertTrue(siteViewModel.isFileModified(testFileNode1.id))
        XCTAssertFalse(siteViewModel.isFileModified(testFileNode2.id))

        // Switch to file 2
        siteViewModel.selectedNode = testFileNode2
        siteViewModel.currentEditingContent = testContentFile2.markdownContent

        let editorVM2 = EditorViewModel(
            fileNode: testFileNode2,
            contentFile: testContentFile2,
            siteViewModel: siteViewModel
        )

        // Modify file 2
        editorVM2.editableContent = "Modified content 2"
        editorVM2.handleContentChange()

        // Both files should be modified
        XCTAssertTrue(siteViewModel.isFileModified(testFileNode1.id))
        XCTAssertTrue(siteViewModel.isFileModified(testFileNode2.id))
    }

    // MARK: - Unsaved Changes Detection Tests

    /// Test that hasUnsavedChanges correctly detects content changes
    func testHasUnsavedChangesDetectsContentChanges() {
        siteViewModel.selectedNode = testFileNode1
        siteViewModel.currentEditingContent = testContentFile1.markdownContent

        let editorVM = EditorViewModel(
            fileNode: testFileNode1,
            contentFile: testContentFile1,
            siteViewModel: siteViewModel
        )

        // Initially no unsaved changes
        XCTAssertFalse(editorVM.hasUnsavedChanges)

        // Modify content
        editorVM.editableContent = "New content"

        // Should have unsaved changes
        XCTAssertTrue(editorVM.hasUnsavedChanges)
    }

    /// Test that hasUnsavedChanges is false when content matches saved content
    func testHasUnsavedChangesIsFalseWhenContentMatchesSaved() {
        siteViewModel.selectedNode = testFileNode1
        siteViewModel.currentEditingContent = testContentFile1.markdownContent

        let editorVM = EditorViewModel(
            fileNode: testFileNode1,
            contentFile: testContentFile1,
            siteViewModel: siteViewModel
        )

        // Set content to match saved content exactly
        editorVM.editableContent = testContentFile1.markdownContent

        // Should not have unsaved changes
        XCTAssertFalse(editorVM.hasUnsavedChanges)
    }

    // MARK: - Word and Character Count Tests

    /// Test word count calculation
    func testWordCountCalculation() {
        siteViewModel.selectedNode = testFileNode1
        siteViewModel.currentEditingContent = "Hello world this is a test"

        let editorVM = EditorViewModel(
            fileNode: testFileNode1,
            contentFile: testContentFile1,
            siteViewModel: siteViewModel
        )

        XCTAssertEqual(editorVM.wordCount, 6)
    }

    /// Test character count calculation
    func testCharacterCountCalculation() {
        siteViewModel.selectedNode = testFileNode1
        siteViewModel.currentEditingContent = "Hello world"

        let editorVM = EditorViewModel(
            fileNode: testFileNode1,
            contentFile: testContentFile1,
            siteViewModel: siteViewModel
        )

        XCTAssertEqual(editorVM.characterCount, 11)
    }

    /// Test word count with empty content
    func testWordCountWithEmptyContent() {
        siteViewModel.selectedNode = testFileNode1
        siteViewModel.currentEditingContent = ""

        let editorVM = EditorViewModel(
            fileNode: testFileNode1,
            contentFile: testContentFile1,
            siteViewModel: siteViewModel
        )

        XCTAssertEqual(editorVM.wordCount, 0)
    }

    /// Test word count ignores multiple spaces
    func testWordCountIgnoresMultipleSpaces() {
        siteViewModel.selectedNode = testFileNode1
        siteViewModel.currentEditingContent = "Hello    world    test"

        let editorVM = EditorViewModel(
            fileNode: testFileNode1,
            contentFile: testContentFile1,
            siteViewModel: siteViewModel
        )

        XCTAssertEqual(editorVM.wordCount, 3)
    }
}
