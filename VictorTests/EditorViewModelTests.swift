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

    // MARK: - Setter-Owned Change Handling (keystroke-lag fix, part 2)

    /// Typing must be fully handled by the editableContent setter itself -
    /// dirty-flag and auto-save scheduling included. Previously the view layer
    /// drove this via `.onChange(of: viewModel.editableContent)`, which forced
    /// EditorPanelView's whole body to re-evaluate (and the focused value to
    /// republish) on every keystroke just to deliver this call.
    func testSettingEditableContentMarksFileModifiedWithoutExplicitHandleContentChange() {
        siteViewModel.selectedNode = testFileNode1

        let editorVM = EditorViewModel(
            fileNode: testFileNode1,
            contentFile: testContentFile1,
            siteViewModel: siteViewModel
        )

        XCTAssertFalse(siteViewModel.isFileModified(testFileNode1.id))

        // A keystroke is just a binding write - no view-layer onChange follow-up.
        editorVM.editableContent = "Modified by typing"

        XCTAssertTrue(
            siteViewModel.isFileModified(testFileNode1.id),
            "The editableContent setter must own change handling; no view onChange call should be needed"
        )
    }

    /// updateContent (external reload / save writeback) must also re-evaluate
    /// dirty state itself, preserving the clear-on-reload behavior the removed
    /// view onChange used to provide.
    func testUpdateContentClearsModifiedStateWhenContentMatchesSaved() {
        siteViewModel.selectedNode = testFileNode1

        let editorVM = EditorViewModel(
            fileNode: testFileNode1,
            contentFile: testContentFile1,
            siteViewModel: siteViewModel
        )

        editorVM.editableContent = "Dirty edit"
        siteViewModel.markFileModified(testFileNode1.id) // belt-and-braces: dirty either way
        XCTAssertTrue(siteViewModel.isFileModified(testFileNode1.id))

        // External reload: disk content becomes the truth and matches the editor.
        testContentFile1.markdownContent = "Reloaded from disk"
        editorVM.updateContent(from: "Reloaded from disk")

        XCTAssertFalse(
            siteViewModel.isFileModified(testFileNode1.id),
            "After an external reload that matches the editor content, the file must read as clean"
        )
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

    /// Test that editableContent returns correct file's content (FIXED in victor-cs2)
    /// After refactor: EditorViewModel uses local storage, so editableContent
    /// returns the correct file's content regardless of which file is selected
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

        // FIXED: editorVM1 now uses local storage, so it returns file 1's content
        // (not file 2's content like before the fix)
        XCTAssertEqual(editorVM1.editableContent, testContentFile1.markdownContent,
                       "After victor-cs2 fix: EditorViewModel returns its own file's content, not the selected file's content")

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

    // MARK: - Vulnerability Fix Documentation Tests

    /// Documents that hasUnsavedChanges now returns CORRECT result after file switch (FIXED in victor-cs2)
    /// The fix: EditorViewModel uses local content storage instead of computed property
    /// that depends on selectedNode. This eliminates the race condition class entirely.
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

        // Switch to file 2
        siteViewModel.selectedNode = testFileNode2
        siteViewModel.currentEditingContent = testContentFile2.markdownContent

        // FIXED (victor-cs2): editorVM1.hasUnsavedChanges now correctly compares:
        // - localContent (file 1's modified content, stored locally)
        // - contentFile.markdownContent (file 1's original saved content)
        // This comparison is NOW CORRECT - it compares file 1's content to file 1's baseline

        let result = editorVM1.hasUnsavedChanges

        // FIXED: hasUnsavedChanges returns true FOR THE CORRECT REASON
        // File 1 genuinely has unsaved changes ("Modified content for file 1" vs original)
        XCTAssertTrue(result,
                      "FIXED: hasUnsavedChanges correctly reports file 1 has unsaved changes, " +
                      "using local content storage instead of computed property")

        // The editableContent write at the top of this test happened while file 1
        // was still selected, so it legitimately marked file 1 modified (the setter
        // owns change handling now - keystroke-lag fix, part 2). Clear that flag to
        // isolate what this assertion actually pins: the stale-ViewModel guard.
        siteViewModel.clearFileModified(testFileNode1.id)

        // The guard in handleContentChange() is still present for defense-in-depth
        editorVM1.handleContentChange()
        // File 1 should NOT be marked as modified by a stale ViewModel (guard still works)
        XCTAssertFalse(siteViewModel.isFileModified(testFileNode1.id),
                       "Guard should prevent stale ViewModel from marking file as modified")
    }

    // MARK: - Local Content Storage Tests (for victor-cs2 refactor)

    /// Test that SiteViewModel provides getEditedContent(for:) method
    /// This method allows EditorViewModel to retrieve content for a specific file by ID
    func testSiteViewModelGetEditedContentForSpecificFile() {
        // Select file 1 and set content
        siteViewModel.selectedNode = testFileNode1
        siteViewModel.currentEditingContent = "Content for file 1"

        // Switch to file 2 and set different content
        siteViewModel.selectedNode = testFileNode2
        siteViewModel.currentEditingContent = "Content for file 2"

        // getEditedContent should return the correct content for each file ID
        // regardless of which file is currently selected
        XCTAssertEqual(siteViewModel.getEditedContent(for: testFileNode1.id), "Content for file 1",
                       "Should return file 1's content even when file 2 is selected")
        XCTAssertEqual(siteViewModel.getEditedContent(for: testFileNode2.id), "Content for file 2",
                       "Should return file 2's content")
    }

    /// Test that SiteViewModel provides setEditedContent(_:for:) method
    /// This method allows EditorViewModel to update content for a specific file by ID
    func testSiteViewModelSetEditedContentForSpecificFile() {
        // Select file 1
        siteViewModel.selectedNode = testFileNode1
        siteViewModel.currentEditingContent = testContentFile1.markdownContent

        // Switch to file 2
        siteViewModel.selectedNode = testFileNode2
        siteViewModel.currentEditingContent = testContentFile2.markdownContent

        // Use setEditedContent to update file 1's content while file 2 is selected
        siteViewModel.setEditedContent("Updated content for file 1", for: testFileNode1.id)

        // Switch back to file 1 and verify the content was updated
        siteViewModel.selectedNode = testFileNode1
        XCTAssertEqual(siteViewModel.currentEditingContent, "Updated content for file 1",
                       "setEditedContent should update per-file storage correctly")

        // File 2 should be unchanged
        siteViewModel.selectedNode = testFileNode2
        XCTAssertEqual(siteViewModel.currentEditingContent, testContentFile2.markdownContent,
                       "File 2's content should be unchanged")
    }

    /// Test that EditorViewModel with local storage maintains correct content after file switch
    /// After victor-cs2 refactor, editableContent should NOT depend on selectedNode
    func testEditorViewModelLocalStorageMaintainsContentAfterFileSwitch() {
        // Select file 1 and create editor
        siteViewModel.selectedNode = testFileNode1
        siteViewModel.currentEditingContent = testContentFile1.markdownContent

        let editorVM1 = EditorViewModel(
            fileNode: testFileNode1,
            contentFile: testContentFile1,
            siteViewModel: siteViewModel
        )

        // Modify file 1's content
        let file1ModifiedContent = "Modified content for file 1"
        editorVM1.editableContent = file1ModifiedContent

        // Verify initial content
        XCTAssertEqual(editorVM1.editableContent, file1ModifiedContent,
                       "Editor should have modified content")

        // Switch to file 2 (this is where the old bug manifested)
        siteViewModel.selectedNode = testFileNode2
        siteViewModel.currentEditingContent = testContentFile2.markdownContent

        // AFTER REFACTOR: editorVM1.editableContent should STILL return file 1's content
        // because it uses local storage, not the computed property based on selectedNode
        XCTAssertEqual(editorVM1.editableContent, file1ModifiedContent,
                       "After refactor: EditorViewModel should return its own file's content, " +
                       "not the currently selected file's content")
    }

    /// Test that hasUnsavedChanges works correctly after file switch (post-refactor)
    /// This is the FIXED version of testHasUnsavedChangesVulnerability_ReturnsWrongValueAfterFileSwitch
    func testHasUnsavedChangesWorksCorrectlyAfterFileSwitch() {
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

        // Switch to file 2
        siteViewModel.selectedNode = testFileNode2
        siteViewModel.currentEditingContent = testContentFile2.markdownContent

        // AFTER REFACTOR: hasUnsavedChanges should STILL be true because it compares
        // the EditorViewModel's local content against its own contentFile.markdownContent
        // It should NOT be affected by which file is currently selected
        XCTAssertTrue(editorVM1.hasUnsavedChanges,
                      "After refactor: hasUnsavedChanges should correctly detect unsaved changes " +
                      "regardless of which file is currently selected")

        // Create editor for file 2
        let editorVM2 = EditorViewModel(
            fileNode: testFileNode2,
            contentFile: testContentFile2,
            siteViewModel: siteViewModel
        )

        // File 2's editor should not have unsaved changes (content matches saved)
        XCTAssertFalse(editorVM2.hasUnsavedChanges,
                       "File 2's editor should have no unsaved changes")
    }

    // MARK: - Integration Tests with Real Timing

    /// Integration test: Verifies auto-save uses captured content, not current editableContent
    /// This test uses REAL TIMING to verify the race condition fix works in practice.
    ///
    /// Strengthened (keystroke-lag perf ticket): the original version relied on the
    /// default 2s debounce and a fixed 3s wait - "the flaky-but-related one" per the
    /// redesign review, since a hardcoded absolute sleep against a hardcoded default
    /// delay is exactly the kind of timing coupling that gets flaky under load. Now
    /// sets `autoSaveDelay` explicitly to a short, deterministic value (like
    /// AutoSaveServiceTests already does) and injects its own `AutoSaveService()`
    /// instance for cross-test isolation (victor-zw4) rather than the process-wide
    /// `.shared` actor. Same critical assertions as before, now proving the guarantee
    /// holds under EditorViewModel's redesigned debounce (a MainActor Task in
    /// EditorViewModel itself, building the full document once at fire time) - not
    /// just the old design (actor-side debounce, content captured at schedule time).
    func testAutoSaveUsesCorrectContentAfterFileSwitchDuringDebounce() async throws {
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaultsKeys.isAutoSaveEnabled)
        UserDefaults.standard.set(0.4, forKey: AppConstants.UserDefaultsKeys.autoSaveDelay)
        defer {
            UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.isAutoSaveEnabled)
            UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.autoSaveDelay)
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

        // Create editor view model for file 1, with its own isolated AutoSaveService
        // instance (victor-zw4) rather than the process-wide singleton.
        let editorVM1 = EditorViewModel(
            fileNode: fileNode1,
            contentFile: contentFile1,
            siteViewModel: siteViewModel,
            autoSaveService: AutoSaveService()
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

        // Give a tiny delay to ensure the debounce Task is created
        try await Task.sleep(for: .milliseconds(50))

        // CRITICAL: Switch to file 2 BEFORE the auto-save debounce completes
        // (debounce is 0.4s here, well before we switch away)
        siteViewModel.selectedNode = fileNode2
        siteViewModel.currentEditingContent = contentFile2.markdownContent

        // Verify the switch happened
        XCTAssertEqual(siteViewModel.selectedNode?.id, fileNode2.id,
                       "Should have switched to file 2")

        // Wait for auto-save to complete (debounce is 0.4s, wait 1s to be safe)
        try await Task.sleep(for: .seconds(1))

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

    /// FIX (keystroke-lag perf ticket): frontmatter serialization now happens once, at
    /// fire time, from LIVE state - not captured as a fixed string back when the
    /// debounce was scheduled. This edits the frontmatter DIRECTLY on the model
    /// (deliberately NOT calling handleContentChange() again) while the debounce from
    /// an earlier markdown edit is still in flight, simulating any edit path that
    /// doesn't happen to re-trigger scheduling. Under the OLD design
    /// (`buildFullContent` captured synchronously inside `scheduleAutoSave`, before the
    /// actor's debounce even started), this edit is silently lost - the string handed
    /// to the actor was already finalized. RED under the pre-fix code; green once the
    /// full document is built once, at fire time, from `contentFile.frontmatter` live.
    func testFrontmatterEditedDuringDebounceWindowReachesDisk() async throws {
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaultsKeys.isAutoSaveEnabled)
        UserDefaults.standard.set(0.5, forKey: AppConstants.UserDefaultsKeys.autoSaveDelay)
        defer {
            UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.isAutoSaveEnabled)
            UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.autoSaveDelay)
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("frontmatter_race.md")
        try "---\ntitle: Original Title\n---\n\nOriginal body".write(to: fileURL, atomically: true, encoding: .utf8)

        let fileNode = FileNode(url: fileURL, isDirectory: false, isPageBundle: false)
        let contentFile = try await FileSystemService.shared.readContentFile(at: fileURL)
        fileNode.contentFile = contentFile
        XCTAssertEqual(contentFile.frontmatter?.title, "Original Title") // sanity check on the fixture

        siteViewModel.selectedNode = fileNode
        siteViewModel.currentEditingContent = contentFile.markdownContent

        let editorVM = EditorViewModel(
            fileNode: fileNode,
            contentFile: contentFile,
            siteViewModel: siteViewModel,
            autoSaveService: AutoSaveService()
        )
        _ = editorVM // keep a strong reference to prevent deallocation

        // Start the debounce with a markdown edit.
        editorVM.editableContent = "Body edited"
        editorVM.handleContentChange()

        // While the debounce is still pending, edit frontmatter directly on the model -
        // NOT calling handleContentChange() again, to isolate "does fire-time build
        // read live state" from "does re-triggering recapture" (already covered by the
        // rapid-keystrokes test below).
        try await Task.sleep(for: .milliseconds(150))
        contentFile.frontmatter?.title = "Changed During Debounce"

        // Wait past the debounce interval for the save to land.
        try await Task.sleep(for: .seconds(1.0))

        let onDisk = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(
            onDisk.contains("Changed During Debounce"),
            "Frontmatter edited during the debounce window must reach disk - the full " +
            "document must be built from LIVE frontmatter at fire time, not a snapshot " +
            "captured when the debounce was scheduled. Actual on disk:\n\(onDisk)"
        )
        XCTAssertFalse(onDisk.contains("Original Title"), "Stale frontmatter must not linger on disk")
    }

    /// Rapid keystrokes must coalesce into exactly one disk write, containing only the
    /// FINAL edit's content. Each `handleContentChange()` call cancels and respawns
    /// EditorViewModel's own debounce Task; this proves that coalescing still holds
    /// after moving the debounce out of the actor and skipping per-keystroke
    /// serialization. (Caveat documented where the assertions are: black-box disk
    /// reads can't literally count write syscalls without instrumenting
    /// AutoSaveService itself, which the DI design deliberately avoids doing via a
    /// protocol/spy - "no behavioral fakes". What's provable, and what this test
    /// proves, is the equivalent externally-observable contract: no premature write
    /// lands before the debounce elapses, and exactly the final content lands once it
    /// does, with nothing further arriving afterward.)
    func testRapidKeystrokesResultInExactlyOneDiskWriteAfterDelay() async throws {
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaultsKeys.isAutoSaveEnabled)
        UserDefaults.standard.set(0.4, forKey: AppConstants.UserDefaultsKeys.autoSaveDelay)
        defer {
            UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.isAutoSaveEnabled)
            UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.autoSaveDelay)
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("rapid_keystrokes.md")
        let initialContent = "---\ntitle: Test\n---\n\nOriginal"
        try initialContent.write(to: fileURL, atomically: true, encoding: .utf8)

        let fileNode = FileNode(url: fileURL, isDirectory: false, isPageBundle: false)
        let contentFile = try await FileSystemService.shared.readContentFile(at: fileURL)
        fileNode.contentFile = contentFile

        siteViewModel.selectedNode = fileNode
        siteViewModel.currentEditingContent = contentFile.markdownContent

        let editorVM = EditorViewModel(
            fileNode: fileNode,
            contentFile: contentFile,
            siteViewModel: siteViewModel,
            autoSaveService: AutoSaveService()
        )
        _ = editorVM

        // Simulate rapid typing: each keystroke restarts the debounce, well under the
        // configured 0.4s delay apart.
        for i in 1...10 {
            editorVM.editableContent = "Original edited \(i) times"
            editorVM.handleContentChange()
            try await Task.sleep(for: .milliseconds(20))
        }

        // Immediately after the last keystroke, nothing should be on disk yet - proves
        // each keystroke actually cancelled the previous debounce rather than an
        // earlier one firing independently mid-sequence.
        let immediatelyAfter = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(immediatelyAfter, initialContent, "No premature write should have landed yet")

        // Wait past the debounce interval for the single coalesced save to land.
        try await Task.sleep(for: .seconds(1.0))

        let onDisk = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(
            onDisk.hasSuffix("Original edited 10 times"),
            "The single coalesced write must contain the FINAL keystroke's content. Actual:\n\(onDisk)"
        )
        XCTAssertFalse(onDisk.hasSuffix("Original edited 9 times"), "Must not have written an intermediate keystroke's content")

        // No further writes should land after this - exactly one save fired.
        try await Task.sleep(for: .milliseconds(600))
        let stillOnDisk = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(stillOnDisk, onDisk, "No additional write should occur after the single coalesced save")
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
