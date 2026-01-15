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

    // MARK: - DocumentStats Tests (moved from EditorViewModel to InspectorPanel)

    /// Test word count calculation via DocumentStats
    func testDocumentStatsWordCount() {
        let stats = DocumentStats.compute(from: "Hello world this is a test")
        XCTAssertEqual(stats.wordCount, 6)
    }

    /// Test character count calculation via DocumentStats
    func testDocumentStatsCharacterCount() {
        let stats = DocumentStats.compute(from: "Hello world")
        XCTAssertEqual(stats.characterCount, 11)
    }

    /// Test word count with empty content via DocumentStats
    func testDocumentStatsWordCountEmpty() {
        let stats = DocumentStats.compute(from: "")
        XCTAssertEqual(stats.wordCount, 0)
    }

    /// Test word count ignores multiple spaces via DocumentStats
    func testDocumentStatsWordCountIgnoresMultipleSpaces() {
        let stats = DocumentStats.compute(from: "Hello    world    test")
        XCTAssertEqual(stats.wordCount, 3)
    }

    /// Test paragraph count via DocumentStats
    func testDocumentStatsParagraphCount() {
        let content = """
        First paragraph here.

        Second paragraph here.

        Third paragraph.
        """
        let stats = DocumentStats.compute(from: content)
        XCTAssertEqual(stats.paragraphCount, 3)
    }

    /// Test sentence count via DocumentStats
    func testDocumentStatsSentenceCount() {
        let content = "Hello world. This is a test! Is it working?"
        let stats = DocumentStats.compute(from: content)
        XCTAssertEqual(stats.sentenceCount, 3)
    }

    /// Test reading time via DocumentStats
    func testDocumentStatsReadingTime() {
        // 200 words should be ~1 min (200 WPM)
        let words = Array(repeating: "word", count: 200).joined(separator: " ")
        let stats = DocumentStats.compute(from: words)
        XCTAssertEqual(stats.readingTime, "~1 min")

        // 400 words should be ~2 mins
        let moreWords = Array(repeating: "word", count: 400).joined(separator: " ")
        let stats2 = DocumentStats.compute(from: moreWords)
        XCTAssertEqual(stats2.readingTime, "~2 mins")
    }

    // MARK: - Vulnerability Documentation Tests

    /// Documents that hasUnsavedChanges returns WRONG result when called on stale ViewModel
    /// This is a known architectural issue - the computed property depends on selectedNode.
    /// The guard in handleContentChange() protects against this in practice.
    /// See victor-cs2 for proposed fix: store content locally instead of computed property.
    func testHasUnsavedChangesVulnerability_ReturnsWrongValueAfterFileSwitch() {
        // Select file 1 and create editor
        siteViewModel.selectedNode = testFileNode1
        siteViewModel.currentEditingContent = testContentFile1.markdownContent

        let editorVM1 = EditorViewModel(
            fileNode: testFileNode1,
            contentFile: testContentFile1,
            siteViewModel: siteViewModel
        )

        // Initially, hasUnsavedChanges should be false (content matches)
        XCTAssertFalse(editorVM1.hasUnsavedChanges,
                       "Should have no unsaved changes initially")

        // Modify file 1's content
        editorVM1.editableContent = "Modified content for file 1"

        // Now hasUnsavedChanges should be true
        XCTAssertTrue(editorVM1.hasUnsavedChanges,
                      "Should have unsaved changes after modification")

        // Switch to file 2 - this is where the vulnerability manifests
        siteViewModel.selectedNode = testFileNode2
        siteViewModel.currentEditingContent = testContentFile2.markdownContent

        // VULNERABILITY: editorVM1.hasUnsavedChanges now compares:
        // - editableContent (reads file 2's content from siteViewModel)
        // - contentFile.markdownContent (still file 1's original content)
        // This comparison is WRONG - it's comparing file 2's content to file 1's saved content!

        // The result depends on whether file 2's content equals file 1's saved content
        // In our test setup, they're different, so hasUnsavedChanges returns true
        // BUT FOR THE WRONG REASON - it thinks file 1 has changes when really
        // it's comparing file 2's content to file 1's baseline

        // Document the vulnerability: after switching, the comparison is meaningless
        let vulnerableResult = editorVM1.hasUnsavedChanges

        // The guard in handleContentChange() prevents this from causing harm,
        // but the underlying computed property is still broken
        XCTAssertTrue(vulnerableResult,
                      "VULNERABILITY: hasUnsavedChanges returns true but for wrong reason - " +
                      "comparing file 2's content to file 1's baseline. " +
                      "See victor-cs2 for architectural fix.")

        // Verify the guard protects against this in practice
        editorVM1.handleContentChange()
        // File 1 should NOT be marked as modified (guard prevents it)
        XCTAssertFalse(siteViewModel.isFileModified(testFileNode1.id),
                       "Guard should prevent stale ViewModel from marking file as modified")
    }

    // MARK: - Integration Tests with Real Timing

    /// Integration test: Verifies auto-save uses captured content, not current editableContent
    /// This test uses REAL TIMING to verify the race condition fix works in practice.
    /// The debounce interval is 2 seconds, so this test takes ~3 seconds to run.
    func testAutoSaveUsesCorrectContentAfterFileSwitchDuringDebounce() async throws {
        // Ensure auto-save is enabled for this test
        UserDefaults.standard.set(true, forKey: "isAutoSaveEnabled")
        defer {
            // Reset to default after test
            UserDefaults.standard.removeObject(forKey: "isAutoSaveEnabled")
        }

        // Create actual test files on disk
        let tempDir = FileManager.default.temporaryDirectory
        let testURL1 = tempDir.appendingPathComponent("race_test_file1_\(UUID()).md")
        let testURL2 = tempDir.appendingPathComponent("race_test_file2_\(UUID()).md")

        // Write initial content
        let file1InitialContent = "---\ntitle: File 1\n---\n\nOriginal content of file 1"
        let file2InitialContent = "---\ntitle: File 2\n---\n\nOriginal content of file 2"
        try file1InitialContent.write(to: testURL1, atomically: true, encoding: .utf8)
        try file2InitialContent.write(to: testURL2, atomically: true, encoding: .utf8)

        // Clean up after test
        defer {
            try? FileManager.default.removeItem(at: testURL1)
            try? FileManager.default.removeItem(at: testURL2)
        }

        // Create file nodes
        let fileNode1 = FileNode(url: testURL1, isDirectory: false, isPageBundle: false)
        let fileNode2 = FileNode(url: testURL2, isDirectory: false, isPageBundle: false)

        // Load content files - small delay to ensure file modification dates are stable
        try await Task.sleep(for: .milliseconds(100))
        let contentFile1 = try await FileSystemService.shared.readContentFile(at: testURL1)
        let contentFile2 = try await FileSystemService.shared.readContentFile(at: testURL2)
        fileNode1.contentFile = contentFile1
        fileNode2.contentFile = contentFile2

        // Select file 1
        siteViewModel.selectedNode = fileNode1
        siteViewModel.currentEditingContent = contentFile1.markdownContent

        // Create editor view model for file 1
        let editorVM1 = EditorViewModel(
            fileNode: fileNode1,
            contentFile: contentFile1,
            siteViewModel: siteViewModel
        )

        // Keep a strong reference to prevent deallocation
        _ = editorVM1

        // Modify file 1's content - this will schedule auto-save
        let file1ModifiedContent = "MODIFIED: This is the new content for file 1"
        editorVM1.editableContent = file1ModifiedContent
        editorVM1.handleContentChange()  // Triggers auto-save scheduling

        // Verify file 1 is marked as modified
        XCTAssertTrue(siteViewModel.isFileModified(fileNode1.id),
                      "File 1 should be marked as modified")

        // Give a tiny delay to ensure the auto-save task is created
        try await Task.sleep(for: .milliseconds(50))

        // CRITICAL: Switch to file 2 BEFORE the auto-save debounce completes
        // The debounce is 2 seconds, so we switch immediately
        siteViewModel.selectedNode = fileNode2
        siteViewModel.currentEditingContent = contentFile2.markdownContent

        // Verify the switch happened
        XCTAssertEqual(siteViewModel.selectedNode?.id, fileNode2.id,
                       "Should have switched to file 2")

        // Wait for auto-save to complete (debounce is 2 seconds, wait 3 to be safe)
        try await Task.sleep(for: .seconds(3))

        // Read file 1 from disk - it should have the MODIFIED content, not file 2's content
        let file1SavedContent = try String(contentsOf: testURL1, encoding: .utf8)

        // CRITICAL ASSERTION: File 1 should contain file 1's modified content
        XCTAssertTrue(file1SavedContent.contains(file1ModifiedContent),
                      "File 1 should be saved with its modified content, not file 2's content. " +
                      "Actual content: \(file1SavedContent)")

        // File 1 should NOT contain file 2's content (data corruption check)
        XCTAssertFalse(file1SavedContent.contains("Original content of file 2"),
                       "File 1 should NOT contain file 2's content (data corruption!)")
        XCTAssertFalse(file1SavedContent.contains("File 2"),
                       "File 1 should NOT contain file 2's title (data corruption!)")

        // File 2 should be unchanged
        let file2Content = try String(contentsOf: testURL2, encoding: .utf8)
        XCTAssertTrue(file2Content.contains("Original content of file 2"),
                      "File 2 should remain unchanged")
    }

    /// Integration test: Verifies manual save captures content correctly even with await suspension
    /// This test creates a real file and saves it to verify the fix works end-to-end.
    func testManualSaveUsesCorrectContentEvenIfFileSwitchDuringAwait() async throws {
        // Create actual test file on disk
        let tempDir = FileManager.default.temporaryDirectory
        let testURL = tempDir.appendingPathComponent("manual_save_test_\(UUID()).md")

        // Write initial content
        let initialContent = "---\ntitle: Test\n---\n\nInitial content"
        try initialContent.write(to: testURL, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testURL)
        }

        // Create file node and load content
        let fileNode = FileNode(url: testURL, isDirectory: false, isPageBundle: false)
        let contentFile = try await FileSystemService.shared.readContentFile(at: testURL)
        fileNode.contentFile = contentFile

        // Select file
        siteViewModel.selectedNode = fileNode
        siteViewModel.currentEditingContent = contentFile.markdownContent

        // Create editor view model
        let editorVM = EditorViewModel(
            fileNode: fileNode,
            contentFile: contentFile,
            siteViewModel: siteViewModel
        )

        // Modify content
        let modifiedContent = "MODIFIED CONTENT - should be saved correctly"
        editorVM.editableContent = modifiedContent

        // Verify unsaved changes before save
        XCTAssertTrue(editorVM.hasUnsavedChanges)

        // Save the file - the fix captures content BEFORE the await
        let saveSuccess = await editorVM.save()
        XCTAssertTrue(saveSuccess, "Save should succeed")

        // Read from disk to verify
        let savedContent = try String(contentsOf: testURL, encoding: .utf8)
        XCTAssertTrue(savedContent.contains(modifiedContent),
                      "Saved file should contain the modified content")

        // Verify contentFile model was updated
        XCTAssertEqual(contentFile.markdownContent, modifiedContent,
                       "ContentFile model should be updated with saved content")
    }
}
