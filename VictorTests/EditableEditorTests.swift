import XCTest
@testable import Victor

/// Tests for EditableEditor protocol and EditorSaveHelper
@MainActor
final class EditableEditorTests: XCTestCase {

    // MARK: - Test Fixtures

    var tempDir: URL!
    var testFileURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        testFileURL = tempDir.appendingPathComponent("test.txt")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - EditorSaveHelper Tests

    /// Test that save operation sets isSaving to true during save
    func testSaveOperationSetsIsSavingDuringSave() async throws {
        // Create a test file
        try "initial content".write(to: testFileURL, atomically: true, encoding: .utf8)

        var capturedIsSavingValues: [Bool] = []
        var isSaving = false {
            didSet { capturedIsSavingValues.append(isSaving) }
        }
        var showSavedIndicator = false
        var errorMessage: String?

        let helper = EditorSaveHelper()
        await helper.performSave(
            to: testFileURL,
            content: { "new content" },
            isSaving: { isSaving },
            setIsSaving: { isSaving = $0 },
            showSavedIndicator: { showSavedIndicator },
            setShowSavedIndicator: { showSavedIndicator = $0 },
            errorMessage: { errorMessage },
            setErrorMessage: { errorMessage = $0 },
            markAsSaved: {},
            afterSave: {},
            savedIndicatorDuration: 0.01 // Short duration for testing
        )

        // Should have set isSaving to true then false
        XCTAssertEqual(capturedIsSavingValues, [true, false], "isSaving should be set to true during save, then false after")
    }

    /// Test that save operation clears error message on success
    func testSaveOperationClearsErrorOnSuccess() async throws {
        try "initial".write(to: testFileURL, atomically: true, encoding: .utf8)

        var isSaving = false
        var showSavedIndicator = false
        var errorMessage: String? = "Previous error"

        let helper = EditorSaveHelper()
        await helper.performSave(
            to: testFileURL,
            content: { "new content" },
            isSaving: { isSaving },
            setIsSaving: { isSaving = $0 },
            showSavedIndicator: { showSavedIndicator },
            setShowSavedIndicator: { showSavedIndicator = $0 },
            errorMessage: { errorMessage },
            setErrorMessage: { errorMessage = $0 },
            markAsSaved: {},
            afterSave: {},
            savedIndicatorDuration: 0.01
        )

        XCTAssertNil(errorMessage, "Error message should be cleared on successful save")
    }

    /// Test that save operation writes content to disk
    func testSaveOperationWritesContentToDisk() async throws {
        try "initial".write(to: testFileURL, atomically: true, encoding: .utf8)

        var isSaving = false
        var showSavedIndicator = false
        var errorMessage: String?

        let helper = EditorSaveHelper()
        await helper.performSave(
            to: testFileURL,
            content: { "updated content" },
            isSaving: { isSaving },
            setIsSaving: { isSaving = $0 },
            showSavedIndicator: { showSavedIndicator },
            setShowSavedIndicator: { showSavedIndicator = $0 },
            errorMessage: { errorMessage },
            setErrorMessage: { errorMessage = $0 },
            markAsSaved: {},
            afterSave: {},
            savedIndicatorDuration: 0.01
        )

        let savedContent = try String(contentsOf: testFileURL, encoding: .utf8)
        XCTAssertEqual(savedContent, "updated content", "Content should be written to disk")
    }

    /// Test that save operation calls markAsSaved on success
    func testSaveOperationCallsMarkAsSaved() async throws {
        try "initial".write(to: testFileURL, atomically: true, encoding: .utf8)

        var isSaving = false
        var showSavedIndicator = false
        var errorMessage: String?
        var markAsSavedCalled = false

        let helper = EditorSaveHelper()
        await helper.performSave(
            to: testFileURL,
            content: { "new content" },
            isSaving: { isSaving },
            setIsSaving: { isSaving = $0 },
            showSavedIndicator: { showSavedIndicator },
            setShowSavedIndicator: { showSavedIndicator = $0 },
            errorMessage: { errorMessage },
            setErrorMessage: { errorMessage = $0 },
            markAsSaved: { markAsSavedCalled = true },
            afterSave: {},
            savedIndicatorDuration: 0.01
        )

        XCTAssertTrue(markAsSavedCalled, "markAsSaved should be called on successful save")
    }

    /// Test that save operation shows saved indicator on success
    func testSaveOperationShowsSavedIndicator() async throws {
        try "initial".write(to: testFileURL, atomically: true, encoding: .utf8)

        var isSaving = false
        var showSavedIndicator = false
        var indicatorWasShown = false
        var errorMessage: String?

        let helper = EditorSaveHelper()
        await helper.performSave(
            to: testFileURL,
            content: { "new content" },
            isSaving: { isSaving },
            setIsSaving: { isSaving = $0 },
            showSavedIndicator: { showSavedIndicator },
            setShowSavedIndicator: {
                showSavedIndicator = $0
                if $0 { indicatorWasShown = true }
            },
            errorMessage: { errorMessage },
            setErrorMessage: { errorMessage = $0 },
            markAsSaved: {},
            afterSave: {},
            savedIndicatorDuration: 0.01
        )

        XCTAssertTrue(indicatorWasShown, "Saved indicator should be shown on success")
        XCTAssertFalse(showSavedIndicator, "Saved indicator should be hidden after duration")
    }

    /// Test that save operation sets error message on failure
    func testSaveOperationSetsErrorOnFailure() async throws {
        // Use invalid URL that will fail to write
        let invalidURL = URL(fileURLWithPath: "/nonexistent/directory/file.txt")

        var isSaving = false
        var showSavedIndicator = false
        var errorMessage: String?
        var markAsSavedCalled = false

        let helper = EditorSaveHelper()
        await helper.performSave(
            to: invalidURL,
            content: { "content" },
            isSaving: { isSaving },
            setIsSaving: { isSaving = $0 },
            showSavedIndicator: { showSavedIndicator },
            setShowSavedIndicator: { showSavedIndicator = $0 },
            errorMessage: { errorMessage },
            setErrorMessage: { errorMessage = $0 },
            markAsSaved: { markAsSavedCalled = true },
            afterSave: {},
            savedIndicatorDuration: 0.01
        )

        XCTAssertNotNil(errorMessage, "Error message should be set on failure")
        XCTAssertTrue(errorMessage?.contains("Save failed") == true, "Error message should indicate save failure")
        XCTAssertFalse(markAsSavedCalled, "markAsSaved should not be called on failure")
        XCTAssertFalse(showSavedIndicator, "Saved indicator should not be shown on failure")
    }

    /// Test that save operation handles content provider errors
    func testSaveOperationHandlesContentProviderError() async throws {
        try "initial".write(to: testFileURL, atomically: true, encoding: .utf8)

        var isSaving = false
        var showSavedIndicator = false
        var errorMessage: String?

        let helper = EditorSaveHelper()
        await helper.performSave(
            to: testFileURL,
            content: { throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Content error"]) },
            isSaving: { isSaving },
            setIsSaving: { isSaving = $0 },
            showSavedIndicator: { showSavedIndicator },
            setShowSavedIndicator: { showSavedIndicator = $0 },
            errorMessage: { errorMessage },
            setErrorMessage: { errorMessage = $0 },
            markAsSaved: {},
            afterSave: {},
            savedIndicatorDuration: 0.01
        )

        XCTAssertNotNil(errorMessage, "Error message should be set when content provider throws")
        XCTAssertTrue(errorMessage?.contains("Content error") == true, "Error message should include original error")
    }

    // MARK: - EditorReloadHelper Tests

    /// Test that reload operation reads content from disk
    func testReloadOperationReadsFromDisk() async throws {
        try "file content".write(to: testFileURL, atomically: true, encoding: .utf8)

        var loadedContent: String?
        var errorMessage: String?

        let helper = EditorReloadHelper()
        await helper.performReload(
            from: testFileURL,
            updateContent: { loadedContent = $0 },
            errorMessage: { errorMessage },
            setErrorMessage: { errorMessage = $0 },
            markAsSaved: {}
        )

        XCTAssertEqual(loadedContent, "file content", "Should load content from disk")
        XCTAssertNil(errorMessage, "No error should be set on success")
    }

    /// Test that reload operation calls markAsSaved
    func testReloadOperationCallsMarkAsSaved() async throws {
        try "content".write(to: testFileURL, atomically: true, encoding: .utf8)

        var errorMessage: String?
        var markAsSavedCalled = false

        let helper = EditorReloadHelper()
        await helper.performReload(
            from: testFileURL,
            updateContent: { _ in },
            errorMessage: { errorMessage },
            setErrorMessage: { errorMessage = $0 },
            markAsSaved: { markAsSavedCalled = true }
        )

        XCTAssertTrue(markAsSavedCalled, "markAsSaved should be called after reload")
    }

    /// Test that reload operation sets error on failure
    func testReloadOperationSetsErrorOnFailure() async throws {
        let nonexistentURL = tempDir.appendingPathComponent("nonexistent.txt")

        var loadedContent: String?
        var errorMessage: String?
        var markAsSavedCalled = false

        let helper = EditorReloadHelper()
        await helper.performReload(
            from: nonexistentURL,
            updateContent: { loadedContent = $0 },
            errorMessage: { errorMessage },
            setErrorMessage: { errorMessage = $0 },
            markAsSaved: { markAsSavedCalled = true }
        )

        XCTAssertNotNil(errorMessage, "Error should be set when file doesn't exist")
        XCTAssertTrue(errorMessage?.contains("Reload failed") == true, "Error message should indicate reload failure")
        XCTAssertNil(loadedContent, "Content should not be set on failure")
        XCTAssertFalse(markAsSavedCalled, "markAsSaved should not be called on failure")
    }
}
