import XCTest
import Observation
@testable import Victor

/// Tests for SiteViewModel
@MainActor
final class SiteViewModelTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // SiteViewModel.init() unconditionally kicks off a background Task that
        // restores whatever real Hugo site is bookmarked in UserDefaults on this
        // machine (SiteViewModel.loadSavedSite()). In synchronous tests that Task
        // never gets a chance to run, but any test with an `await` after
        // constructing SiteViewModel() yields control back to the scheduler and
        // lets it interleave, silently overwriting fileNodes/selectedNode with a
        // real site out from under the test. Clearing the bookmark key makes
        // loadSavedSite() a guaranteed no-op regardless of what's persisted
        // locally, so async tests are deterministic.
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.hugoSiteBookmark)
    }

    // MARK: - Selection Assertion Helpers (victor-sel)
    //
    // Two different helpers for two different jobs (SELECTION-MODEL-MEMO.md
    // section 8): `assertSelection` checks the selection equals a SPECIFIC
    // expected node (or the fully-cleared state), for retrofitting existing
    // tests that already assert a particular `selectedNode?.id`.
    // `assertSelectionInvariant` checks INTERNAL CONSISTENCY only - that
    // `selectedNode`/`selectedFileID`/`selectedFileIDs` never drift from each
    // other, regardless of what's selected - for the new lead-derivation and
    // batch-trash tests, where the point is to catch a future change that
    // mutates `selectedNode` without going through the canonical
    // `applySelectionChange`/`selectNode` write path.

    /// Asserts all three selection properties reflect `node` (or the
    /// fully-cleared state if `node` is nil) - written once so the ~12
    /// existing navigation/selection tests don't each hand-write three
    /// assertions.
    private func assertSelection(
        _ viewModel: SiteViewModel,
        is node: FileNode?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(viewModel.selectedNode?.id, node?.id, file: file, line: line)
        XCTAssertEqual(viewModel.selectedFileID, node?.id, file: file, line: line)
        if let node {
            XCTAssertEqual(viewModel.selectedFileIDs, [node.id], file: file, line: line)
        } else {
            XCTAssertTrue(viewModel.selectedFileIDs.isEmpty, file: file, line: line)
        }
    }

    /// Asserts the canonical-write-path invariant holds, regardless of what's
    /// selected: `selectedFileIDs.isEmpty` iff both `selectedNode`/
    /// `selectedFileID` are nil; otherwise `selectedNode?.id == selectedFileID`
    /// and `selectedFileIDs` contains it.
    private func assertSelectionInvariant(
        _ viewModel: SiteViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if viewModel.selectedFileIDs.isEmpty {
            XCTAssertNil(viewModel.selectedNode, file: file, line: line)
            XCTAssertNil(viewModel.selectedFileID, file: file, line: line)
        } else {
            XCTAssertNotNil(viewModel.selectedFileID, file: file, line: line)
            XCTAssertEqual(viewModel.selectedNode?.id, viewModel.selectedFileID, file: file, line: line)
            XCTAssertTrue(viewModel.selectedFileIDs.contains(viewModel.selectedFileID!), file: file, line: line)
        }
    }

    // MARK: - EditorLayoutMode Tests

    func testEditorLayoutModeDisplayNames() {
        XCTAssertEqual(EditorLayoutMode.editor.displayName, "Editor")
        XCTAssertEqual(EditorLayoutMode.preview.displayName, "Preview")
        XCTAssertEqual(EditorLayoutMode.split.displayName, "Split")
    }

    func testEditorLayoutModeIconNames() {
        XCTAssertEqual(EditorLayoutMode.editor.iconName, "doc.text")
        XCTAssertEqual(EditorLayoutMode.preview.iconName, "eye")
        XCTAssertEqual(EditorLayoutMode.split.iconName, "rectangle.split.2x1")
    }

    func testEditorLayoutModeAllCases() {
        let allCases = EditorLayoutMode.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.editor))
        XCTAssertTrue(allCases.contains(.preview))
        XCTAssertTrue(allCases.contains(.split))
    }

    // MARK: - Initialization Tests

    func testInitialStateWithNoUserDefaults() {
        // Note: preference defaults (auto-save, layout mode, highlight line, font size,
        // inspector visibility) moved to AppSettings and are covered by AppSettingsTests.
        let viewModel = SiteViewModel()

        // Check defaults
        XCTAssertNil(viewModel.site, "No site should be loaded initially")
        XCTAssertTrue(viewModel.fileNodes.isEmpty, "File nodes should be empty initially")
        XCTAssertNil(viewModel.selectedNode, "No node should be selected initially")
        XCTAssertFalse(viewModel.isLoading, "Should not be loading initially")
        XCTAssertNil(viewModel.errorMessage, "No error initially")
        XCTAssertEqual(viewModel.searchQuery, "", "Search query should be empty")
        XCTAssertFalse(viewModel.isFocusModeActive, "Focus mode should be inactive initially")
    }

    // MARK: - File Status Management Tests

    func testMarkFileModified() {
        let viewModel = SiteViewModel()
        let nodeID = UUID()

        XCTAssertFalse(viewModel.isFileModified(nodeID))

        viewModel.markFileModified(nodeID)

        XCTAssertTrue(viewModel.isFileModified(nodeID))
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }

    func testClearFileModified() {
        let viewModel = SiteViewModel()
        let nodeID = UUID()

        viewModel.markFileModified(nodeID)
        XCTAssertTrue(viewModel.isFileModified(nodeID))

        viewModel.clearFileModified(nodeID)

        XCTAssertFalse(viewModel.isFileModified(nodeID))
    }

    // MARK: - Observation Storm Guard Tests
    //
    // Diagnosed keystroke-lag mechanism: EditorViewModel.handleContentChange runs on
    // every keystroke and calls markFileModified/clearFileModified. An unconditional
    // Set.insert/remove mutates `modifiedFileIDs` (and fires Observation) even when
    // the member is already present/absent. Since Phase 1, two expensive listeners
    // read `hasUnsavedChanges` (which reads `modifiedFileIDs`): ContentView's body
    // (edited-dot) and VictorApp's .commands .disabled() validation - so an
    // unguarded mutation re-renders the window body AND rebuilds NSMenu items on
    // every keystroke, not just on the rare state transitions. These tests assert
    // the guarded, no-mutation-on-repeat behavior directly via Observation itself
    // (not just the end state), since the end state looks identical either way.

    /// Sanity check for the tracking mechanism itself: a genuine state transition
    /// (not-modified -> modified) MUST still fire Observation. Without this, the
    /// no-fire assertions below could pass vacuously if tracking were set up wrong.
    func testMarkFileModifiedFiresObservationOnActualTransition() {
        let viewModel = SiteViewModel()
        let nodeID = UUID()

        nonisolated(unsafe) var observedChange = false
        withObservationTracking {
            _ = viewModel.modifiedFileIDs
        } onChange: {
            observedChange = true
        }

        viewModel.markFileModified(nodeID) // not-present -> present: must fire

        XCTAssertTrue(observedChange, "Sanity check: an actual transition must still fire Observation")
    }

    /// The keystroke-lag fix: once a file is already marked modified, repeated
    /// markFileModified calls for the same id (i.e. every subsequent keystroke)
    /// must not mutate modifiedFileIDs again, and therefore must not fire Observation.
    func testMarkFileModifiedIsNoOpWhenAlreadyModified() {
        let viewModel = SiteViewModel()
        let nodeID = UUID()

        viewModel.markFileModified(nodeID) // first transition: not-present -> present
        XCTAssertTrue(viewModel.isFileModified(nodeID))

        nonisolated(unsafe) var observedChange = false
        withObservationTracking {
            _ = viewModel.modifiedFileIDs
        } onChange: {
            observedChange = true
        }

        viewModel.markFileModified(nodeID) // already present - must be a no-op

        XCTAssertFalse(
            observedChange,
            "Repeated markFileModified for an already-modified file must not fire Observation " +
            "(this is what re-renders ContentView's body and rebuilds NSMenu items on every keystroke)"
        )
    }

    /// Mirror of the above for clearFileModified: clearing a file that was never
    /// (or is no longer) modified must not mutate modifiedFileIDs or fire Observation.
    func testClearFileModifiedIsNoOpWhenNotModified() {
        let viewModel = SiteViewModel()
        let nodeID = UUID()

        XCTAssertFalse(viewModel.isFileModified(nodeID))

        nonisolated(unsafe) var observedChange = false
        withObservationTracking {
            _ = viewModel.modifiedFileIDs
        } onChange: {
            observedChange = true
        }

        viewModel.clearFileModified(nodeID) // already absent - must be a no-op

        XCTAssertFalse(observedChange, "clearFileModified on an already-clear file must not fire Observation")
    }

    /// markFileSaved's internal modifiedFileIDs.remove must also go through the
    /// guarded clearFileModified path: saving a file that was never marked modified
    /// (e.g. a redundant Save with no pending edits) must not fire modifiedFileIDs'
    /// Observation, even though recentlySavedFileIDs does legitimately change.
    func testMarkFileSavedDoesNotFireModifiedFileIDsObservationWhenNotPreviouslyModified() {
        let viewModel = SiteViewModel()
        let nodeID = UUID()

        XCTAssertFalse(viewModel.isFileModified(nodeID))

        nonisolated(unsafe) var observedChange = false
        withObservationTracking {
            _ = viewModel.modifiedFileIDs
        } onChange: {
            observedChange = true
        }

        viewModel.markFileSaved(nodeID)

        XCTAssertFalse(
            observedChange,
            "markFileSaved must route its internal modifiedFileIDs.remove through the guarded " +
            "clearFileModified path, not mutate unconditionally"
        )
        XCTAssertTrue(viewModel.isFileRecentlySaved(nodeID), "recentlySavedFileIDs should still be updated")
    }

    // MARK: - Edited-Content Version Tests (keystroke-lag fix, part 2)
    //
    // The live preview and inspector must learn about typing WITHOUT piggybacking
    // on unrelated view invalidations (the old behavior: they watched
    // `currentEditingContent`, whose backing FileCacheManager is not @Observable,
    // so their onChange only re-evaluated when the per-keystroke focused-value
    // storm happened to re-render everything). `editedContentVersion` is the
    // deliberate, narrow signal: bumped on every content edit, observed ONLY by
    // views that genuinely need per-keystroke wake-ups (each with its own
    // debounce). Menu validation must NOT depend on it - see the test below.

    /// Every setEditedContent call must bump the version so content observers
    /// (preview, inspector stats) get a change signal.
    func testSetEditedContentBumpsEditedContentVersion() {
        let viewModel = SiteViewModel()
        let nodeID = UUID()

        let before = viewModel.editedContentVersion
        viewModel.setEditedContent("hello", for: nodeID)

        XCTAssertEqual(viewModel.editedContentVersion, before + 1)
    }

    /// The currentEditingContent setter (used by Focus Mode's binding) must route
    /// through the same versioned path, not silently write to the cache.
    func testCurrentEditingContentSetterBumpsEditedContentVersion() {
        let viewModel = SiteViewModel()
        let node = FileNode(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("version-test.md"),
            isDirectory: false,
            isPageBundle: false
        )
        viewModel.selectedNode = node

        let before = viewModel.editedContentVersion
        viewModel.currentEditingContent = "typed in focus mode"

        XCTAssertEqual(viewModel.editedContentVersion, before + 1)
        XCTAssertEqual(viewModel.getEditedContent(for: node.id), "typed in focus mode")
    }

    /// Observation sanity check: a view tracking editedContentVersion (the
    /// preview) must be invalidated by a keystroke.
    func testEditedContentVersionFiresObservationOnEdit() {
        let viewModel = SiteViewModel()

        nonisolated(unsafe) var observedChange = false
        withObservationTracking {
            _ = viewModel.editedContentVersion
        } onChange: {
            observedChange = true
        }

        viewModel.setEditedContent("x", for: UUID())

        XCTAssertTrue(observedChange, "Preview/inspector rely on editedContentVersion firing per edit")
    }

    /// The menu-validation contract: menu items' .disabled() closures consult
    /// isFileModified (backed by transition-guarded modifiedFileIDs). Once a file
    /// is already dirty, a subsequent keystroke - content write plus the redundant
    /// markFileModified that handleContentChange issues - must not fire Observation
    /// for an isFileModified reader. This is the invariant that keeps NSMenu
    /// rebuilds off the per-keystroke path; if it regresses, typing lag returns.
    func testKeystrokeOnAlreadyDirtyFileDoesNotFireMenuValidationObservation() {
        let viewModel = SiteViewModel()
        let nodeID = UUID()

        // First keystroke: file transitions to dirty (fires, legitimately).
        viewModel.setEditedContent("first keystroke", for: nodeID)
        viewModel.markFileModified(nodeID)

        nonisolated(unsafe) var observedChange = false
        withObservationTracking {
            _ = viewModel.isFileModified(nodeID)
        } onChange: {
            observedChange = true
        }

        // Every subsequent keystroke does exactly this pair.
        viewModel.setEditedContent("second keystroke", for: nodeID)
        viewModel.markFileModified(nodeID)

        XCTAssertFalse(
            observedChange,
            "A keystroke on an already-dirty file must not invalidate isFileModified readers " +
            "(menu .disabled() validation) - that path rebuilds NSMenu items"
        )
    }

    // MARK: - Live Preview Auto-Enable (server-status stream)

    /// The status stream replays the CURRENT status to every new subscriber
    /// (HugoServerService replay-on-subscribe). Auto-enabling live preview must
    /// key off genuine stopped->running TRANSITIONS, not off any .running value
    /// observed - otherwise every re-subscribe (window re-appear re-running
    /// setupHugoServerObservers) forces the user back to live preview after
    /// they deliberately switched to markdown preview.
    func testAutoEnableLivePreviewOnlyOnActualStartTransition() {
        // Replayed current state (no previous value) is not a transition.
        XCTAssertFalse(SiteViewModel.shouldAutoEnableLivePreview(previous: nil, new: .running(port: 1313)))
        XCTAssertFalse(SiteViewModel.shouldAutoEnableLivePreview(previous: nil, new: .stopped))

        // Genuine startup transitions.
        XCTAssertTrue(SiteViewModel.shouldAutoEnableLivePreview(previous: .stopped, new: .running(port: 1313)))
        XCTAssertTrue(SiteViewModel.shouldAutoEnableLivePreview(previous: .starting, new: .running(port: 1313)))

        // Steady states and shutdowns never auto-enable.
        XCTAssertFalse(SiteViewModel.shouldAutoEnableLivePreview(previous: .running(port: 1313), new: .running(port: 1313)))
        XCTAssertFalse(SiteViewModel.shouldAutoEnableLivePreview(previous: .running(port: 1313), new: .stopped))
        XCTAssertFalse(SiteViewModel.shouldAutoEnableLivePreview(previous: .stopped, new: .starting))
    }

    func testMarkFileSaved() {
        let viewModel = SiteViewModel()
        let nodeID = UUID()

        // First mark as modified
        viewModel.markFileModified(nodeID)
        XCTAssertTrue(viewModel.isFileModified(nodeID))

        // Mark as saved
        viewModel.markFileSaved(nodeID)

        // Should no longer be modified
        XCTAssertFalse(viewModel.isFileModified(nodeID))
        // Should be recently saved
        XCTAssertTrue(viewModel.isFileRecentlySaved(nodeID))
    }

    func testMultipleModifiedFiles() {
        let viewModel = SiteViewModel()
        let nodeID1 = UUID()
        let nodeID2 = UUID()
        let nodeID3 = UUID()

        viewModel.markFileModified(nodeID1)
        viewModel.markFileModified(nodeID2)

        XCTAssertTrue(viewModel.isFileModified(nodeID1))
        XCTAssertTrue(viewModel.isFileModified(nodeID2))
        XCTAssertFalse(viewModel.isFileModified(nodeID3))
        XCTAssertTrue(viewModel.hasUnsavedChanges)

        viewModel.clearFileModified(nodeID1)

        XCTAssertFalse(viewModel.isFileModified(nodeID1))
        XCTAssertTrue(viewModel.isFileModified(nodeID2))
        XCTAssertTrue(viewModel.hasUnsavedChanges)

        viewModel.clearFileModified(nodeID2)

        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }

    // MARK: - Recent Files Tests

    func testAddRecentFile() {
        let viewModel = SiteViewModel()
        let node1 = FileNode(url: URL(fileURLWithPath: "/test/file1.md"), isDirectory: false)
        let node2 = FileNode(url: URL(fileURLWithPath: "/test/file2.md"), isDirectory: false)

        viewModel.addRecentFile(node1)

        XCTAssertEqual(viewModel.recentFiles.count, 1)
        XCTAssertEqual(viewModel.recentFiles.first?.id, node1.id)

        viewModel.addRecentFile(node2)

        XCTAssertEqual(viewModel.recentFiles.count, 2)
        XCTAssertEqual(viewModel.recentFiles.first?.id, node2.id)
    }

    func testAddRecentFileMoveToFront() {
        let viewModel = SiteViewModel()
        let node1 = FileNode(url: URL(fileURLWithPath: "/test/file1.md"), isDirectory: false)
        let node2 = FileNode(url: URL(fileURLWithPath: "/test/file2.md"), isDirectory: false)

        viewModel.addRecentFile(node1)
        viewModel.addRecentFile(node2)

        // node2 is first, node1 is second
        XCTAssertEqual(viewModel.recentFiles[0].id, node2.id)
        XCTAssertEqual(viewModel.recentFiles[1].id, node1.id)

        // Re-add node1 - should move to front
        viewModel.addRecentFile(node1)

        XCTAssertEqual(viewModel.recentFiles.count, 2)
        XCTAssertEqual(viewModel.recentFiles[0].id, node1.id)
        XCTAssertEqual(viewModel.recentFiles[1].id, node2.id)
    }

    func testRecentFilesMaxLimit() {
        let viewModel = SiteViewModel()

        // Add 15 files (limit is 10)
        for i in 0..<15 {
            let node = FileNode(url: URL(fileURLWithPath: "/test/file\(i).md"), isDirectory: false)
            viewModel.addRecentFile(node)
        }

        XCTAssertEqual(viewModel.recentFiles.count, 10, "Recent files should be limited to 10")
    }

    // MARK: - Recent Sites Tests
    // (Phase-1 review P1: recentSitePaths was a computed UserDefaults read,
    // invisible to @Observable - the Open Recent submenu never refreshed
    // after Clear Menu. Now a stored property that mutators update directly.)

    func testClearRecentSitesEmptiesObservableProperty() {
        let viewModel = SiteViewModel()
        viewModel.recentSitePaths = ["/one", "/two"]
        XCTAssertFalse(viewModel.recentSitePaths.isEmpty)

        viewModel.clearRecentSites()

        XCTAssertTrue(
            viewModel.recentSitePaths.isEmpty,
            "recentSitePaths must be an observable stored property that Clear Menu actually updates"
        )
    }

    // MARK: - Search Filtering Tests

    func testFilteredNodesEmptySearch() {
        let viewModel = SiteViewModel()
        let node1 = FileNode(url: URL(fileURLWithPath: "/test/file1.md"), isDirectory: false)
        let node2 = FileNode(url: URL(fileURLWithPath: "/test/file2.md"), isDirectory: false)
        viewModel.fileNodes = [node1, node2]

        viewModel.searchQuery = ""

        XCTAssertEqual(viewModel.filteredNodes.count, 2)
    }

    func testFilteredNodesWithQuery() {
        let viewModel = SiteViewModel()
        let node1 = FileNode(url: URL(fileURLWithPath: "/test/hello.md"), isDirectory: false)
        let node2 = FileNode(url: URL(fileURLWithPath: "/test/world.md"), isDirectory: false)
        let node3 = FileNode(url: URL(fileURLWithPath: "/test/hello-world.md"), isDirectory: false)
        viewModel.fileNodes = [node1, node2, node3]

        viewModel.searchQuery = "hello"

        let filtered = viewModel.filteredNodes
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.contains { $0.name == "hello.md" })
        XCTAssertTrue(filtered.contains { $0.name == "hello-world.md" })
        XCTAssertFalse(filtered.contains { $0.name == "world.md" })
    }

    func testFilteredNodesCaseInsensitive() {
        let viewModel = SiteViewModel()
        let node1 = FileNode(url: URL(fileURLWithPath: "/test/Hello.md"), isDirectory: false)
        let node2 = FileNode(url: URL(fileURLWithPath: "/test/HELLO.md"), isDirectory: false)
        let node3 = FileNode(url: URL(fileURLWithPath: "/test/hello.md"), isDirectory: false)
        viewModel.fileNodes = [node1, node2, node3]

        viewModel.searchQuery = "HeLLo"

        let filtered = viewModel.filteredNodes
        XCTAssertEqual(filtered.count, 3)
    }

    func testFilteredNodesWithDirectory() {
        let viewModel = SiteViewModel()

        // Create directory with children
        let directory = FileNode(url: URL(fileURLWithPath: "/test/posts"), isDirectory: true)
        let child1 = FileNode(url: URL(fileURLWithPath: "/test/posts/hello.md"), isDirectory: false)
        let child2 = FileNode(url: URL(fileURLWithPath: "/test/posts/world.md"), isDirectory: false)
        directory.children = [child1, child2]
        child1.parent = directory
        child2.parent = directory

        viewModel.fileNodes = [directory]

        viewModel.searchQuery = "hello"

        let filtered = viewModel.filteredNodes
        XCTAssertEqual(filtered.count, 1) // Directory with filtered children
        XCTAssertTrue(filtered[0].isDirectory)
        XCTAssertEqual(filtered[0].children.count, 1)
        XCTAssertEqual(filtered[0].children[0].name, "hello.md")

        // Check that the directory is auto-expanded
        XCTAssertTrue(viewModel.shouldAutoExpand(directory))
    }

    // MARK: - Node Lookup Tests

    func testFindNodeByID() {
        let viewModel = SiteViewModel()
        let node1 = FileNode(url: URL(fileURLWithPath: "/test/file1.md"), isDirectory: false)
        let node2 = FileNode(url: URL(fileURLWithPath: "/test/file2.md"), isDirectory: false)
        viewModel.fileNodes = [node1, node2]

        // Manually build the lookup table (normally done during loadSite)
        // Since we can't call private methods, we'll use the public interface
        // The lookup table is built when fileNodes is set via loadSite
        // For this test, we'll use a workaround

        // The lookup table is empty (it's built during loadSite), but findNode must
        // fall back to tree traversal so nodes added after site load are still found.
        // Otherwise Save All / isFileModified silently skip newly created files.
        let found = viewModel.findNode(id: node1.id)
        XCTAssertIdentical(found, node1, "findNode must fall back to tree traversal when the lookup table misses")
    }

    // MARK: - Save All Modified Files Tests

    /// victor-zw4: constructs `SiteViewModel` with its own `FileSystemService()` instance
    /// rather than relying on the `fileSystemService: FileSystemService = .shared` default,
    /// proving the injection seam actually works end-to-end (site load, edited-content
    /// cache, and the write-to-disk path all go through the injected instance) rather
    /// than only compiling.
    func testSaveAllModifiedFilesWritesEditedContentNotStaleContent() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("post.md")
        try "original content".write(to: fileURL, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        let node = FileNode(url: fileURL, isDirectory: false)
        node.contentFile = ContentFile(url: fileURL, frontmatter: nil, markdownContent: "original content")
        viewModel.fileNodes = [node]

        // Simulate unsaved editor state: edits live in the per-file cache, not on contentFile
        viewModel.setEditedContent("edited content", for: node.id)
        viewModel.markFileModified(node.id)

        await viewModel.saveAllModifiedFiles()

        let onDisk = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(onDisk, "edited content",
                       "Save All (used by Save-and-Quit) must write the user's edits, not the stale loaded content")
        XCTAssertFalse(viewModel.isFileModified(node.id))
    }

    /// Phase-1 review P0: TextFile-backed edits (css/js/yaml routed to
    /// TextEditorPanel) never reached modifiedFileIDs, so this branch of
    /// saveAllModifiedFiles was unreachable in practice and Cmd+Q / Save All
    /// silently discarded dirty plain-text files. Now that
    /// TextEditorViewModel reports dirty state (see TextEditorViewModelTests),
    /// this confirms the save side actually persists once marked.
    func testSaveAllModifiedFilesWritesDirtyTextFileToDisk() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("style.css")
        try "body { color: red; }".write(to: fileURL, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel()
        let node = FileNode(url: fileURL, isDirectory: false)
        let textFile = TextFile(url: fileURL, content: "body { color: red; }", lastModified: Date())
        // Unlike markdown, TextFile edits live directly on the shared TextFile
        // object (TextEditorViewModel.contentDidChange writes file.content),
        // not in a separate per-file edit cache.
        textFile.content = "body { color: blue; }"
        node.textFile = textFile
        viewModel.fileNodes = [node]

        viewModel.markFileModified(node.id)

        await viewModel.saveAllModifiedFiles()

        let onDisk = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(onDisk, "body { color: blue; }",
                       "Save All must reach and persist the textFile branch, not silently skip dirty plain-text files")
        XCTAssertFalse(viewModel.isFileModified(node.id))
    }

    // MARK: - Rename Tests (victor-rnm)

    func testRenameFileUpdatesNodeURLAndContentFileURL() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("post.md")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let node = FileNode(url: fileURL, isDirectory: false)
        node.contentFile = ContentFile(url: fileURL, frontmatter: nil, markdownContent: "hello")
        viewModel.fileNodes = [node]

        await viewModel.renameFile(node: node, to: "renamed.md")

        let expectedURL = tempDir.appendingPathComponent("renamed.md")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(node.url, expectedURL)
        XCTAssertEqual(node.contentFile?.url, expectedURL,
                       "contentFile.url must be updated too - saveAllModifiedFiles and EditorViewModel's auto-save debounce read it directly, not node.url")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testRenameDirectoryUpdatesDescendantURLs() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folderURL = tempDir.appendingPathComponent("post-bundle")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let indexURL = folderURL.appendingPathComponent("index.md")
        try "hello".write(to: indexURL, atomically: true, encoding: .utf8)
        let imagesURL = folderURL.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        let coverURL = imagesURL.appendingPathComponent("cover.png")
        try Data().write(to: coverURL)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)

        let folderNode = FileNode(url: folderURL, isDirectory: true, isPageBundle: true)
        let indexNode = FileNode(url: indexURL, isDirectory: false)
        let imagesNode = FileNode(url: imagesURL, isDirectory: true)
        let coverNode = FileNode(url: coverURL, isDirectory: false)
        folderNode.addChild(indexNode)
        folderNode.addChild(imagesNode)
        imagesNode.addChild(coverNode)
        viewModel.fileNodes = [folderNode]

        await viewModel.renameFile(node: folderNode, to: "renamed-bundle")

        let expectedFolderURL = tempDir.appendingPathComponent("renamed-bundle")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(folderNode.url, expectedFolderURL)
        XCTAssertEqual(indexNode.url, expectedFolderURL.appendingPathComponent("index.md"),
                       "descendant FileNode URLs must be rebuilt by prefix replacement after a directory rename")
        XCTAssertEqual(imagesNode.url, expectedFolderURL.appendingPathComponent("images"))
        XCTAssertEqual(coverNode.url, expectedFolderURL.appendingPathComponent("images/cover.png"),
                       "grandchild URLs must update too, not just direct children")
    }

    func testRenamePreservesEditedContentKeyedByUUID() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("post.md")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let node = FileNode(url: fileURL, isDirectory: false)
        node.contentFile = ContentFile(url: fileURL, frontmatter: nil, markdownContent: "original")
        viewModel.fileNodes = [node]

        viewModel.setEditedContent("unsaved edits", for: node.id)

        await viewModel.renameFile(node: node, to: "renamed.md")

        XCTAssertEqual(viewModel.getEditedContent(for: node.id), "unsaved edits",
                       "editedContentByFile is keyed by UUID, not path - cached edits must survive a rename")
    }

    func testRenameSurvivesInRecentFiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("post.md")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let node = FileNode(url: fileURL, isDirectory: false)
        node.contentFile = ContentFile(url: fileURL, frontmatter: nil, markdownContent: "hello")
        viewModel.fileNodes = [node]
        viewModel.addRecentFile(node)

        await viewModel.renameFile(node: node, to: "renamed.md")

        XCTAssertEqual(viewModel.recentFiles.first?.url, tempDir.appendingPathComponent("renamed.md"),
                       "recentFiles stores the same FileNode instances, not path strings - a rename must be visible there too")
    }

    func testRenamePreservesSelectedNodeIdentityWithoutForcePoke() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("post.md")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let node = FileNode(url: fileURL, isDirectory: false)
        node.contentFile = ContentFile(url: fileURL, frontmatter: nil, markdownContent: "hello")
        viewModel.fileNodes = [node]
        viewModel.selectedNode = node
        // Direct fixture poke (bypassing selectNode) doesn't route through the
        // canonical write path, so selectedFileIDs needs its own setup line to
        // match - see the assertion below (victor-sel).
        viewModel.selectedFileIDs = [node.id]

        await viewModel.renameFile(node: node, to: "renamed.md")

        // Same object instance throughout - `url` was mutated in place, not
        // swapped for a new node, so Observation propagates without needing
        // the old selectedNode = nil; selectedNode = node poke.
        XCTAssertTrue(viewModel.selectedNode === node)
        XCTAssertEqual(viewModel.selectedNode?.url, tempDir.appendingPathComponent("renamed.md"))
        XCTAssertTrue(viewModel.selectedFileIDs.contains(node.id), "rename doesn't touch selection identity - selectedFileIDs must still contain the (unchanged) id")
    }

    func testRenameReSortsTopLevelSiblingsWhenNameOrderChanges() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let aURL = tempDir.appendingPathComponent("apple.md")
        let zURL = tempDir.appendingPathComponent("zebra.md")
        try "a".write(to: aURL, atomically: true, encoding: .utf8)
        try "z".write(to: zURL, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let aNode = FileNode(url: aURL, isDirectory: false)
        let zNode = FileNode(url: zURL, isDirectory: false)
        viewModel.fileNodes = [aNode, zNode]

        await viewModel.renameFile(node: aNode, to: "zzzz.md")

        XCTAssertEqual(viewModel.fileNodes.map(\.name), ["zebra.md", "zzzz.md"],
                       "top-level fileNodes must be re-sorted after a rename changes sort order")
    }

    func testRenameReSortsFolderChildrenWhenNameOrderChanges() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folderURL = tempDir.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let aURL = folderURL.appendingPathComponent("apple.md")
        let zURL = folderURL.appendingPathComponent("zebra.md")
        try "a".write(to: aURL, atomically: true, encoding: .utf8)
        try "z".write(to: zURL, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let folderNode = FileNode(url: folderURL, isDirectory: true)
        let aNode = FileNode(url: aURL, isDirectory: false)
        let zNode = FileNode(url: zURL, isDirectory: false)
        folderNode.addChild(aNode)
        folderNode.addChild(zNode)
        viewModel.fileNodes = [folderNode]

        await viewModel.renameFile(node: aNode, to: "zzzz.md")

        XCTAssertEqual(folderNode.children.map(\.name), ["zebra.md", "zzzz.md"],
                       "a folder's children must be re-sorted after a rename changes sort order")
    }

    /// Highest-risk bug flagged in victor-rnm: a debounced auto-save scheduled
    /// BEFORE the rename must not land at the OLD path once its debounce fires
    /// AFTER the rename completes.
    ///
    /// Post-launch program review found the FIRST version of this test
    /// (exercising `AutoSaveService.scheduleAutoSave` directly) was validating
    /// a call path `renameFile` doesn't actually use in production - nothing
    /// registers into that URL-keyed dictionary outside tests (see
    /// `scheduleAutoSave`'s doc comment). Rewritten to drive a REAL
    /// EditorViewModel debounce (the thing that's actually registered/
    /// cancelled now) through the SAME AutoSaveService instance `viewModel`
    /// uses - production always shares one instance (`.shared`) between
    /// SiteViewModel and EditorViewModel; a mismatched instance here would let
    /// this test pass for the wrong reason (see
    /// EditorViewModelTests.testRenameFileCancelsAndDeregistersEditorViewModelsRegisteredDebounce,
    /// which asserts the registry directly rather than inferring correctness
    /// from disk content/timing).
    func testRenameCancelsPendingAutoSaveForOldPath() async throws {
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaultsKeys.isAutoSaveEnabled)
        UserDefaults.standard.set(0.3, forKey: AppConstants.UserDefaultsKeys.autoSaveDelay)
        defer {
            UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.isAutoSaveEnabled)
            UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.autoSaveDelay)
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("post.md")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)

        let autoSaveService = AutoSaveService()
        let viewModel = SiteViewModel(fileSystemService: FileSystemService(), autoSaveService: autoSaveService)
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let node = FileNode(url: fileURL, isDirectory: false)
        let contentFile = ContentFile(url: fileURL, frontmatter: nil, markdownContent: "original")
        node.contentFile = contentFile
        viewModel.fileNodes = [node]
        viewModel.selectedNode = node

        let editorVM = EditorViewModel(
            fileNode: node,
            contentFile: contentFile,
            siteViewModel: viewModel,
            autoSaveService: autoSaveService
        )
        _ = editorVM // keep a strong reference to prevent deallocation

        editorVM.editableContent = "edited content"
        editorVM.handleContentChange() // schedules the debounce, registers with `autoSaveService`

        try await Task.sleep(for: .milliseconds(50)) // let it reach registerDebounce, still well inside the 0.3s debounce

        await viewModel.renameFile(node: node, to: "renamed.md")

        // cancelDebounce awaits the Task's actual completion, so by the time
        // renameFile returns there's nothing left pending or in flight.
        let registeredAfterRename = await autoSaveService.debounceRegistrationCount
        XCTAssertEqual(registeredAfterRename, 0, "renameFile must cancel-and-await the registered debounce, not leave it pending")

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fileURL.path),
            "renameFile must cancel the pending debounced auto-save for the OLD path before renaming, or the debounce recreates the file there once it fires"
        )
        // The cancelled Task never wrote (it was still sleeping when renameFile
        // cancelled it - see AutoSaveService.cancelDebounce's doc comment: a
        // cancelled, still-sleeping debounce never fires at all, it doesn't get
        // redirected to the new path), so the renamed file on disk still holds
        // its ORIGINAL pre-edit content...
        let renamedURL = tempDir.appendingPathComponent("renamed.md")
        let renamedContent = try String(contentsOf: renamedURL, encoding: .utf8)
        XCTAssertEqual(renamedContent, "original",
                       "a cancelled (still-sleeping) debounce must not write at all - not to the old path, not to the new one either")
        // ...while the user's edit is safe, still pending in the per-file cache
        // keyed by node.id (see testRenamePreservesEditedContentKeyedByUUID) -
        // nothing was lost, it just wasn't flushed to disk by this cancelled debounce.
        XCTAssertEqual(viewModel.getEditedContent(for: node.id), "edited content",
                       "the edit must survive the cancelled debounce, ready for the next auto-save or manual save")
    }

    // MARK: - Move Node Tests (victor-sel B.4, drag-to-move within the tree)

    func testMoveNodeUpdatesURLAndReparents() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folderAURL = tempDir.appendingPathComponent("folderA")
        let folderBURL = tempDir.appendingPathComponent("folderB")
        try FileManager.default.createDirectory(at: folderAURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folderBURL, withIntermediateDirectories: true)
        let fileURL = folderAURL.appendingPathComponent("post.md")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let folderANode = FileNode(url: folderAURL, isDirectory: true)
        let folderBNode = FileNode(url: folderBURL, isDirectory: true)
        let fileNode = FileNode(url: fileURL, isDirectory: false)
        folderANode.addChild(fileNode)
        viewModel.fileNodes = [folderANode, folderBNode]

        await viewModel.moveNode(from: fileNode, to: folderBNode)

        let expectedURL = folderBURL.appendingPathComponent("post.md")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(fileNode.url, expectedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(folderANode.children.contains { $0.id == fileNode.id }, "must be removed from the old parent")
        XCTAssertTrue(folderBNode.children.contains { $0.id == fileNode.id }, "must be reparented into the new parent")
        XCTAssertTrue(fileNode.parent === folderBNode)
    }

    func testMoveNodeUpdatesDescendantURLsWhenMovingFolder() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folderURL = tempDir.appendingPathComponent("post-bundle")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let indexURL = folderURL.appendingPathComponent("index.md")
        try "hello".write(to: indexURL, atomically: true, encoding: .utf8)
        let imagesURL = folderURL.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        let coverURL = imagesURL.appendingPathComponent("cover.png")
        try Data().write(to: coverURL)

        let targetURL = tempDir.appendingPathComponent("archive")
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)

        let folderNode = FileNode(url: folderURL, isDirectory: true, isPageBundle: true)
        let indexNode = FileNode(url: indexURL, isDirectory: false)
        let imagesNode = FileNode(url: imagesURL, isDirectory: true)
        let coverNode = FileNode(url: coverURL, isDirectory: false)
        folderNode.addChild(indexNode)
        folderNode.addChild(imagesNode)
        imagesNode.addChild(coverNode)
        let targetNode = FileNode(url: targetURL, isDirectory: true)
        viewModel.fileNodes = [folderNode, targetNode]

        await viewModel.moveNode(from: folderNode, to: targetNode)

        let expectedFolderURL = targetURL.appendingPathComponent("post-bundle")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(folderNode.url, expectedFolderURL)
        XCTAssertEqual(indexNode.url, expectedFolderURL.appendingPathComponent("index.md"),
                       "descendant FileNode URLs must be rebuilt by prefix replacement after a directory move")
        XCTAssertEqual(imagesNode.url, expectedFolderURL.appendingPathComponent("images"))
        XCTAssertEqual(coverNode.url, expectedFolderURL.appendingPathComponent("images/cover.png"),
                       "grandchild URLs must update too, not just direct children")
        XCTAssertTrue(targetNode.children.contains { $0.id == folderNode.id })
        XCTAssertFalse(viewModel.fileNodes.contains { $0.id == folderNode.id }, "moved top-level node must be removed from fileNodes")
    }

    func testMoveNodeRefusesMovingFolderIntoOwnDescendant() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let parentURL = tempDir.appendingPathComponent("parent")
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        let childURL = parentURL.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: childURL, withIntermediateDirectories: true)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let parentNode = FileNode(url: parentURL, isDirectory: true)
        let childNode = FileNode(url: childURL, isDirectory: true)
        parentNode.addChild(childNode)
        viewModel.fileNodes = [parentNode]

        await viewModel.moveNode(from: parentNode, to: childNode)

        XCTAssertNotNil(viewModel.errorMessage, "moving a folder into its own descendant must be refused")
        XCTAssertEqual(parentNode.url, parentURL, "the refused move must leave the node untouched")
        XCTAssertTrue(FileManager.default.fileExists(atPath: parentURL.path))
        XCTAssertTrue(viewModel.fileNodes.contains { $0.id == parentNode.id }, "must not be reparented")
    }

    func testMoveNodeNoOpsWhenTargetIsCurrentParent() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folderURL = tempDir.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let fileURL = folderURL.appendingPathComponent("post.md")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let folderNode = FileNode(url: folderURL, isDirectory: true)
        let fileNode = FileNode(url: fileURL, isDirectory: false)
        folderNode.addChild(fileNode)
        viewModel.fileNodes = [folderNode]

        await viewModel.moveNode(from: fileNode, to: folderNode)

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(fileNode.url, fileURL, "no-op: url must be unchanged")
        XCTAssertTrue(folderNode.children.contains { $0.id == fileNode.id })
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "no-op must not touch disk")
    }

    /// Same rewrite/rationale as testRenameCancelsPendingAutoSaveForOldPath
    /// (see its doc comment): the original version exercised
    /// `AutoSaveService.scheduleAutoSave` directly, a call path `moveNode`
    /// doesn't actually use in production. Rewritten to drive a real
    /// EditorViewModel debounce through the SAME AutoSaveService instance
    /// `viewModel` uses, and to assert the registry directly (not just disk
    /// timing) so a broken nodeID/instance wiring would actually fail this
    /// test instead of passing for the wrong reason.
    func testMoveNodeCancelsPendingAutoSaveForOldPath() async throws {
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaultsKeys.isAutoSaveEnabled)
        UserDefaults.standard.set(0.3, forKey: AppConstants.UserDefaultsKeys.autoSaveDelay)
        defer {
            UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.isAutoSaveEnabled)
            UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.autoSaveDelay)
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folderAURL = tempDir.appendingPathComponent("folderA")
        let folderBURL = tempDir.appendingPathComponent("folderB")
        try FileManager.default.createDirectory(at: folderAURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folderBURL, withIntermediateDirectories: true)
        let fileURL = folderAURL.appendingPathComponent("post.md")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)

        let autoSaveService = AutoSaveService()
        let viewModel = SiteViewModel(fileSystemService: FileSystemService(), autoSaveService: autoSaveService)
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let folderANode = FileNode(url: folderAURL, isDirectory: true)
        let folderBNode = FileNode(url: folderBURL, isDirectory: true)
        let fileNode = FileNode(url: fileURL, isDirectory: false)
        let contentFile = ContentFile(url: fileURL, frontmatter: nil, markdownContent: "original")
        fileNode.contentFile = contentFile
        folderANode.addChild(fileNode)
        viewModel.fileNodes = [folderANode, folderBNode]
        viewModel.selectedNode = fileNode

        let editorVM = EditorViewModel(
            fileNode: fileNode,
            contentFile: contentFile,
            siteViewModel: viewModel,
            autoSaveService: autoSaveService
        )
        _ = editorVM // keep a strong reference to prevent deallocation

        editorVM.editableContent = "edited content"
        editorVM.handleContentChange() // schedules the debounce, registers with `autoSaveService`

        try await Task.sleep(for: .milliseconds(50)) // still well inside the 0.3s debounce

        await viewModel.moveNode(from: fileNode, to: folderBNode)

        // cancelDebounce awaits the Task's actual completion, so by the time
        // moveNode returns there's nothing left pending or in flight.
        let registeredAfterMove = await autoSaveService.debounceRegistrationCount
        XCTAssertEqual(registeredAfterMove, 0, "moveNode must cancel-and-await the registered debounce, not leave it pending")

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fileURL.path),
            "moveNode must cancel the pending debounced auto-save for the OLD path before moving, or the debounce recreates the file there once it fires"
        )
        // The cancelled Task never wrote (still sleeping when moveNode cancelled
        // it), so the moved file on disk still holds its ORIGINAL pre-edit
        // content, while the edit itself survives in the per-file cache.
        let movedURL = folderBURL.appendingPathComponent("post.md")
        let movedContent = try String(contentsOf: movedURL, encoding: .utf8)
        XCTAssertEqual(movedContent, "original",
                       "a cancelled (still-sleeping) debounce must not write at all - not to the old path, not to the new one either")
        XCTAssertEqual(viewModel.getEditedContent(for: fileNode.id), "edited content",
                       "the edit must survive the cancelled debounce, ready for the next auto-save or manual save")
    }

    func testMoveNodePreservesEditedContentKeyedByUUID() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folderAURL = tempDir.appendingPathComponent("folderA")
        let folderBURL = tempDir.appendingPathComponent("folderB")
        try FileManager.default.createDirectory(at: folderAURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folderBURL, withIntermediateDirectories: true)
        let fileURL = folderAURL.appendingPathComponent("post.md")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let folderANode = FileNode(url: folderAURL, isDirectory: true)
        let folderBNode = FileNode(url: folderBURL, isDirectory: true)
        let fileNode = FileNode(url: fileURL, isDirectory: false)
        fileNode.contentFile = ContentFile(url: fileURL, frontmatter: nil, markdownContent: "original")
        folderANode.addChild(fileNode)
        viewModel.fileNodes = [folderANode, folderBNode]

        viewModel.setEditedContent("unsaved edits", for: fileNode.id)

        await viewModel.moveNode(from: fileNode, to: folderBNode)

        XCTAssertEqual(viewModel.getEditedContent(for: fileNode.id), "unsaved edits",
                       "fileCacheManager is keyed by UUID, not path - cached edits must survive a move")
    }

    // MARK: - Handle Dropped File Dispatch Tests (victor-sel B.4)

    func testHandleDroppedFileMovesWhenSourceIsInsideSite() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folderAURL = tempDir.appendingPathComponent("folderA")
        let folderBURL = tempDir.appendingPathComponent("folderB")
        try FileManager.default.createDirectory(at: folderAURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folderBURL, withIntermediateDirectories: true)
        let fileURL = folderAURL.appendingPathComponent("post.md")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let folderANode = FileNode(url: folderAURL, isDirectory: true)
        let folderBNode = FileNode(url: folderBURL, isDirectory: true)
        let fileNode = FileNode(url: fileURL, isDirectory: false)
        folderANode.addChild(fileNode)
        viewModel.fileNodes = [folderANode, folderBNode]

        await viewModel.handleDroppedFile(from: fileURL, into: folderBNode)

        let expectedURL = folderBURL.appendingPathComponent("post.md")
        XCTAssertEqual(fileNode.url, expectedURL, "a drop whose source is already inside the site must MOVE, not copy")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "the original must be gone - a move, not a copy")
        XCTAssertTrue(folderBNode.children.contains { $0.id == fileNode.id })
    }

    func testHandleDroppedFileImportsWhenSourceIsOutsideSite() async throws {
        let siteDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        let outsideDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: siteDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: siteDir)
            try? FileManager.default.removeItem(at: outsideDir)
        }

        let folderURL = siteDir.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let outsideFileURL = outsideDir.appendingPathComponent("external.md")
        try "external".write(to: outsideFileURL, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: siteDir)
        let folderNode = FileNode(url: folderURL, isDirectory: true)
        viewModel.fileNodes = [folderNode]

        await viewModel.handleDroppedFile(from: outsideFileURL, into: folderNode)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideFileURL.path), "a drop from outside the site must COPY, not move - the original must remain")
        XCTAssertEqual(folderNode.children.count, 1)
        XCTAssertEqual(folderNode.children.first?.name, "external.md")
    }

    // MARK: - Close Site Tests

    func testCloseSite() {
        let viewModel = SiteViewModel()

        // Set up some state
        let node = FileNode(url: URL(fileURLWithPath: "/test/file.md"), isDirectory: false)
        viewModel.fileNodes = [node]
        viewModel.selectedNode = node
        viewModel.selectedFileID = node.id
        viewModel.currentEditingContent = "Some content"
        viewModel.recentFiles = [node]
        viewModel.markFileModified(node.id)
        viewModel.markFileSaved(node.id)

        // Close the site
        viewModel.closeSite()

        // Verify state is cleared
        XCTAssertNil(viewModel.site)
        XCTAssertTrue(viewModel.fileNodes.isEmpty)
        XCTAssertNil(viewModel.selectedNode)
        XCTAssertNil(viewModel.selectedFileID)
        XCTAssertTrue(viewModel.selectedFileIDs.isEmpty, "closeSite must clear selectedFileIDs too (victor-sel)")
        XCTAssertEqual(viewModel.currentEditingContent, "")
        XCTAssertTrue(viewModel.recentFiles.isEmpty)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }

    // MARK: - File Menu Target Resolution Tests
    // (WP1.3: File > New Post…, File > New Folder folder-targeting logic)

    func testContentRootNodeFindsTopLevelContentFolder() {
        let viewModel = SiteViewModel()
        let content = FileNode(url: URL(fileURLWithPath: "/site/content"), isDirectory: true, hugoRole: .content)
        let staticDir = FileNode(url: URL(fileURLWithPath: "/site/static"), isDirectory: true, hugoRole: .staticFiles)
        viewModel.fileNodes = [content, staticDir]

        XCTAssertEqual(viewModel.contentRootNode?.id, content.id)
    }

    func testContentRootNodeNilWhenNoContentFolder() {
        let viewModel = SiteViewModel()
        XCTAssertNil(viewModel.contentRootNode)
    }

    func testNewContentTargetFolderUsesSelectedFolderInsideContent() {
        let viewModel = SiteViewModel()
        let content = FileNode(url: URL(fileURLWithPath: "/site/content"), isDirectory: true, hugoRole: .content)
        let posts = FileNode(url: URL(fileURLWithPath: "/site/content/posts"), isDirectory: true)
        content.addChild(posts)
        viewModel.fileNodes = [content]
        viewModel.selectedNode = posts

        XCTAssertEqual(viewModel.newContentTargetFolder?.id, posts.id)
    }

    func testNewContentTargetFolderUsesParentOfSelectedFileInsideContent() {
        let viewModel = SiteViewModel()
        let content = FileNode(url: URL(fileURLWithPath: "/site/content"), isDirectory: true, hugoRole: .content)
        let posts = FileNode(url: URL(fileURLWithPath: "/site/content/posts"), isDirectory: true)
        let article = FileNode(url: URL(fileURLWithPath: "/site/content/posts/article.md"), isDirectory: false)
        content.addChild(posts)
        posts.addChild(article)
        viewModel.fileNodes = [content]
        viewModel.selectedNode = article

        XCTAssertEqual(viewModel.newContentTargetFolder?.id, posts.id)
    }

    func testNewContentTargetFolderFallsBackToContentRootWhenSelectionOutsideContent() {
        let viewModel = SiteViewModel()
        let content = FileNode(url: URL(fileURLWithPath: "/site/content"), isDirectory: true, hugoRole: .content)
        let staticDir = FileNode(url: URL(fileURLWithPath: "/site/static"), isDirectory: true, hugoRole: .staticFiles)
        viewModel.fileNodes = [content, staticDir]
        viewModel.selectedNode = staticDir

        XCTAssertEqual(viewModel.newContentTargetFolder?.id, content.id)
    }

    func testNewContentTargetFolderFallsBackToContentRootWhenNothingSelected() {
        let viewModel = SiteViewModel()
        let content = FileNode(url: URL(fileURLWithPath: "/site/content"), isDirectory: true, hugoRole: .content)
        viewModel.fileNodes = [content]
        viewModel.selectedNode = nil

        XCTAssertEqual(viewModel.newContentTargetFolder?.id, content.id)
    }

    func testNewFolderTargetFolderUsesSelectedFolderAnywhere() {
        let viewModel = SiteViewModel()
        let staticDir = FileNode(url: URL(fileURLWithPath: "/site/static"), isDirectory: true, hugoRole: .staticFiles)
        let images = FileNode(url: URL(fileURLWithPath: "/site/static/images"), isDirectory: true)
        staticDir.addChild(images)
        viewModel.fileNodes = [staticDir]
        viewModel.selectedNode = images

        XCTAssertEqual(viewModel.newFolderTargetFolder?.id, images.id)
    }

    func testNewFolderTargetFolderUsesParentOfSelectedFile() {
        let viewModel = SiteViewModel()
        let staticDir = FileNode(url: URL(fileURLWithPath: "/site/static"), isDirectory: true, hugoRole: .staticFiles)
        let file = FileNode(url: URL(fileURLWithPath: "/site/static/logo.png"), isDirectory: false)
        staticDir.addChild(file)
        viewModel.fileNodes = [staticDir]
        viewModel.selectedNode = file

        XCTAssertEqual(viewModel.newFolderTargetFolder?.id, staticDir.id)
    }

    func testNewFolderTargetFolderFallsBackToContentRootWhenNothingSelected() {
        let viewModel = SiteViewModel()
        let content = FileNode(url: URL(fileURLWithPath: "/site/content"), isDirectory: true, hugoRole: .content)
        viewModel.fileNodes = [content]
        viewModel.selectedNode = nil

        XCTAssertEqual(viewModel.newFolderTargetFolder?.id, content.id)
    }

    // MARK: - New Content Presentation Flag Tests

    func testIsNewContentPresentedDefaultsFalseAndIsSettable() {
        let viewModel = SiteViewModel()
        XCTAssertFalse(viewModel.isNewContentPresented)

        viewModel.isNewContentPresented = true
        XCTAssertTrue(viewModel.isNewContentPresented)
    }

    // MARK: - Go Menu Navigation History Tests
    // (WP1.4: Back/Forward through selectNode history)

    func testNavigationCannotGoBackOrForwardInitially() {
        let viewModel = SiteViewModel()
        XCTAssertFalse(viewModel.canNavigateBack)
        XCTAssertFalse(viewModel.canNavigateForward)
    }

    func testNavigationCannotGoBackAfterSingleSelection() {
        let viewModel = SiteViewModel()
        let node = FileNode(url: URL(fileURLWithPath: "/test/a.md"), isDirectory: false)
        viewModel.fileNodes = [node]

        viewModel.selectNode(node)

        XCTAssertFalse(viewModel.canNavigateBack, "Only one history entry - nowhere to go back to")
        XCTAssertFalse(viewModel.canNavigateForward)
    }

    func testNavigationBackReturnsToPreviouslySelectedNode() {
        let viewModel = SiteViewModel()
        let nodeA = FileNode(url: URL(fileURLWithPath: "/test/a.md"), isDirectory: false)
        let nodeB = FileNode(url: URL(fileURLWithPath: "/test/b.md"), isDirectory: false)
        viewModel.fileNodes = [nodeA, nodeB]

        viewModel.selectNode(nodeA)
        viewModel.selectNode(nodeB)
        XCTAssertTrue(viewModel.canNavigateBack)

        viewModel.navigateBack()

        assertSelection(viewModel, is: nodeA)
        XCTAssertFalse(viewModel.canNavigateBack)
        XCTAssertTrue(viewModel.canNavigateForward)
    }

    func testNavigationForwardReturnsToNodeNavigatedAwayFrom() {
        let viewModel = SiteViewModel()
        let nodeA = FileNode(url: URL(fileURLWithPath: "/test/a.md"), isDirectory: false)
        let nodeB = FileNode(url: URL(fileURLWithPath: "/test/b.md"), isDirectory: false)
        viewModel.fileNodes = [nodeA, nodeB]

        viewModel.selectNode(nodeA)
        viewModel.selectNode(nodeB)
        viewModel.navigateBack()
        assertSelection(viewModel, is: nodeA)

        viewModel.navigateForward()

        assertSelection(viewModel, is: nodeB)
        XCTAssertTrue(viewModel.canNavigateBack)
        XCTAssertFalse(viewModel.canNavigateForward)
    }

    func testNavigationBackForwardRoundTripThroughThreeNodes() {
        let viewModel = SiteViewModel()
        let nodeA = FileNode(url: URL(fileURLWithPath: "/test/a.md"), isDirectory: false)
        let nodeB = FileNode(url: URL(fileURLWithPath: "/test/b.md"), isDirectory: false)
        let nodeC = FileNode(url: URL(fileURLWithPath: "/test/c.md"), isDirectory: false)
        viewModel.fileNodes = [nodeA, nodeB, nodeC]

        viewModel.selectNode(nodeA)
        viewModel.selectNode(nodeB)
        viewModel.selectNode(nodeC)

        viewModel.navigateBack()
        assertSelection(viewModel, is: nodeB)

        viewModel.navigateBack()
        assertSelection(viewModel, is: nodeA)
        XCTAssertFalse(viewModel.canNavigateBack)

        viewModel.navigateForward()
        assertSelection(viewModel, is: nodeB)

        viewModel.navigateForward()
        assertSelection(viewModel, is: nodeC)
        XCTAssertFalse(viewModel.canNavigateForward)
    }

    func testNavigationSelectingNewNodeAfterBackDiscardsForwardHistory() {
        let viewModel = SiteViewModel()
        let nodeA = FileNode(url: URL(fileURLWithPath: "/test/a.md"), isDirectory: false)
        let nodeB = FileNode(url: URL(fileURLWithPath: "/test/b.md"), isDirectory: false)
        let nodeC = FileNode(url: URL(fileURLWithPath: "/test/c.md"), isDirectory: false)
        viewModel.fileNodes = [nodeA, nodeB, nodeC]

        viewModel.selectNode(nodeA)
        viewModel.selectNode(nodeB)
        viewModel.navigateBack()
        XCTAssertTrue(viewModel.canNavigateForward)

        // Branching off from history's middle should drop the stale "forward" entry (B)
        viewModel.selectNode(nodeC)

        XCTAssertFalse(viewModel.canNavigateForward, "Selecting a new node should discard forward history")
        XCTAssertTrue(viewModel.canNavigateBack)

        viewModel.navigateBack()
        assertSelection(viewModel, is: nodeA)
    }

    func testNavigateBackNoOpWhenAtStartOfHistory() {
        let viewModel = SiteViewModel()
        let node = FileNode(url: URL(fileURLWithPath: "/test/a.md"), isDirectory: false)
        viewModel.fileNodes = [node]
        viewModel.selectNode(node)

        viewModel.navigateBack()

        assertSelection(viewModel, is: node)
    }

    func testNavigateForwardNoOpWhenAtEndOfHistory() {
        let viewModel = SiteViewModel()
        let nodeA = FileNode(url: URL(fileURLWithPath: "/test/a.md"), isDirectory: false)
        let nodeB = FileNode(url: URL(fileURLWithPath: "/test/b.md"), isDirectory: false)
        viewModel.fileNodes = [nodeA, nodeB]
        viewModel.selectNode(nodeA)
        viewModel.selectNode(nodeB)

        viewModel.navigateForward()

        assertSelection(viewModel, is: nodeB)
    }

    func testReselectingSameNodeDoesNotGrowHistory() {
        let viewModel = SiteViewModel()
        let nodeA = FileNode(url: URL(fileURLWithPath: "/test/a.md"), isDirectory: false)
        let nodeB = FileNode(url: URL(fileURLWithPath: "/test/b.md"), isDirectory: false)
        viewModel.fileNodes = [nodeA, nodeB]

        viewModel.selectNode(nodeA)
        viewModel.selectNode(nodeB)
        // Re-selecting the currently-selected node is already a no-op in selectNode(_:);
        // history should not grow, so a single Back still lands on nodeA.
        viewModel.selectNode(nodeB)

        viewModel.navigateBack()
        assertSelection(viewModel, is: nodeA)
        XCTAssertFalse(viewModel.canNavigateBack)
    }

    func testNavigationHistoryResetOnCloseSite() {
        let viewModel = SiteViewModel()
        let nodeA = FileNode(url: URL(fileURLWithPath: "/test/a.md"), isDirectory: false)
        let nodeB = FileNode(url: URL(fileURLWithPath: "/test/b.md"), isDirectory: false)
        viewModel.fileNodes = [nodeA, nodeB]
        viewModel.selectNode(nodeA)
        viewModel.selectNode(nodeB)
        XCTAssertTrue(viewModel.canNavigateBack)

        viewModel.closeSite()

        XCTAssertFalse(viewModel.canNavigateBack)
        XCTAssertFalse(viewModel.canNavigateForward)
    }

    // MARK: - Navigation History Reload/Prune Tests
    // (Phase-1 review P0: FileNode UUIDs regenerate on every rescan, so
    // reloadSite() must reset history outright rather than let stale IDs
    // linger; separately, navigateBack()/navigateForward() must prune any
    // other dead entry - e.g. a node deleted or moved out of the tree
    // without a full reload - and continue to the next live one instead of
    // silently consuming a Back/Forward press with no visible effect.)

    func testReloadSiteResetsNavigationHistory() async {
        let viewModel = SiteViewModel()
        let nodeA = FileNode(url: URL(fileURLWithPath: "/test/a.md"), isDirectory: false)
        let nodeB = FileNode(url: URL(fileURLWithPath: "/test/b.md"), isDirectory: false)
        viewModel.fileNodes = [nodeA, nodeB]
        viewModel.selectNode(nodeA)
        viewModel.selectNode(nodeB)
        XCTAssertTrue(viewModel.canNavigateBack)

        // `site` only needs to be non-nil to pass reloadSite()'s guard; this
        // rootURL doesn't exist so the reload itself fails validation and
        // bails out harmlessly afterward (before ever touching the security-
        // scoped bookmark) - irrelevant here, since the history reset this
        // test checks happens before that reload attempt.
        let nonexistentRoot = URL(fileURLWithPath: "/nonexistent/site-\(UUID().uuidString)")
        viewModel.site = await HugoSite.create(rootURL: nonexistentRoot)

        await viewModel.reloadSite()

        XCTAssertFalse(viewModel.canNavigateBack, "All FileNode IDs die on rescan - history must not survive reloadSite()")
        XCTAssertFalse(viewModel.canNavigateForward)
    }

    func testNavigateBackPrunesDeadEntryAndContinuesToNextValidEntry() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let urlB = tempDir.appendingPathComponent("b.md")
        try "b".write(to: urlB, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel()
        let nodeA = FileNode(url: URL(fileURLWithPath: "/test/a.md"), isDirectory: false)
        let nodeB = FileNode(url: urlB, isDirectory: false)
        let nodeC = FileNode(url: URL(fileURLWithPath: "/test/c.md"), isDirectory: false)
        viewModel.fileNodes = [nodeA, nodeB, nodeC]

        viewModel.selectNode(nodeA)
        viewModel.selectNode(nodeB)
        viewModel.selectNode(nodeC)

        // Actually delete nodeB through the real removal path - this both drops
        // it from the tree and purges SiteViewModel's node-lookup cache
        // (nodeByID), exactly like a user deleting a file via the sidebar would.
        // (A direct `fileNodes = [...]` reassignment isn't equivalent: findNode(id:)
        // checks nodeByID first, and selectNode's selectedFileID didSet had
        // already opportunistically cached nodeB there before this point.)
        await viewModel.moveToTrash(node: nodeB)

        viewModel.navigateBack()

        assertSelection(viewModel, is: nodeA)
        XCTAssertFalse(viewModel.canNavigateBack, "B should have been pruned, leaving only A behind the cursor")
    }

    func testNavigateForwardPrunesDeadEntryAndContinuesToNextValidEntry() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let urlB = tempDir.appendingPathComponent("b.md")
        try "b".write(to: urlB, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel()
        let nodeA = FileNode(url: URL(fileURLWithPath: "/test/a.md"), isDirectory: false)
        let nodeB = FileNode(url: urlB, isDirectory: false)
        let nodeC = FileNode(url: URL(fileURLWithPath: "/test/c.md"), isDirectory: false)
        viewModel.fileNodes = [nodeA, nodeB, nodeC]

        viewModel.selectNode(nodeA)
        viewModel.selectNode(nodeB)
        viewModel.selectNode(nodeC)
        viewModel.navigateBack()
        viewModel.navigateBack()
        assertSelection(viewModel, is: nodeA)

        // Delete nodeB (the entry between the cursor and nodeC) via the real
        // removal path - see comment above for why this (not a direct
        // `fileNodes = [...]` reassignment) is what actually makes it dead.
        await viewModel.moveToTrash(node: nodeB)

        viewModel.navigateForward()

        assertSelection(viewModel, is: nodeC)
        XCTAssertFalse(viewModel.canNavigateForward, "B should have been pruned, leaving only C ahead of the cursor")
    }

    // MARK: - Sidebar Drop Import Tests (W3.3/victor-dnd, Phase-end review Fix A)
    // Phase-end review P1: filterNodesRecursively hands FolderRowWithSheets an
    // ephemeral FileNode COPY (fresh UUID) for folders with a mix of matching and
    // non-matching children under an active search - attaching an import directly
    // to that copy would make the file land on disk but vanish from the sidebar on
    // the next filter recompute. importDroppedFile must resolve the canonical node
    // by URL before attaching anything.

    func testImportDroppedFileDuringActiveSearchAttachesToCanonicalFolder() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let contentDir = tempDir.appendingPathComponent("content")
        try FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)

        // A folder with one matching and one non-matching child forces
        // filterNodesRecursively into the "create a filtered copy" branch instead of
        // reusing the canonical node (see its doc comment a few hundred lines up).
        let matchingChild = FileNode(url: contentDir.appendingPathComponent("hello.md"), isDirectory: false)
        let nonMatchingChild = FileNode(url: contentDir.appendingPathComponent("world.md"), isDirectory: false)
        let contentFolder = FileNode(url: contentDir, isDirectory: true)
        contentFolder.addChild(matchingChild)
        contentFolder.addChild(nonMatchingChild)

        let viewModel = SiteViewModel()
        viewModel.fileNodes = [contentFolder]
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        viewModel.searchQuery = "hello"

        // Sanity check: confirm the filtered node really is a distinct copy, i.e.
        // that this test actually exercises the bug scenario rather than the
        // already-safe "all children match" path.
        let filteredFolder = try XCTUnwrap(viewModel.filteredNodes.first)
        XCTAssertNotEqual(
            filteredFolder.id, contentFolder.id,
            "Expected filterNodesRecursively to hand out a copy under this search"
        )

        let sourceURL = tempDir.appendingPathComponent("external.png")
        try "img-bytes".write(to: sourceURL, atomically: true, encoding: .utf8)

        // Simulates FolderRowWithSheets's dropDestination handler, which only ever
        // sees whatever filteredNodes produced - i.e. the copy, not contentFolder.
        await viewModel.importDroppedFile(from: sourceURL, into: filteredFolder)

        XCTAssertEqual(
            contentFolder.children.count, 3,
            "Import must attach to the canonical folder's real children, not the discarded filtered copy"
        )
        let importedNode = try XCTUnwrap(
            contentFolder.children.first { $0.name == "external.png" },
            "Imported node not found under the canonical folder"
        )
        XCTAssertEqual(
            viewModel.findNode(id: importedNode.id)?.id, importedNode.id,
            "Imported node must be discoverable via findNode(id:) (registerNode must have run)"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedNode.url.path))
    }

    func testImportDroppedFileSetsErrorMessageOnFailure() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folder = FileNode(url: tempDir.appendingPathComponent("static"), isDirectory: true)

        let viewModel = SiteViewModel()
        viewModel.fileNodes = [folder]
        viewModel.site = await HugoSite.create(rootURL: tempDir)

        XCTAssertNil(viewModel.errorMessage)

        // Source file doesn't exist on disk, so the copy inside importFile throws
        let missingSource = tempDir.appendingPathComponent("does-not-exist.png")
        await viewModel.importDroppedFile(from: missingSource, into: folder)

        XCTAssertNotNil(viewModel.errorMessage, "Failure must surface via errorMessage, matching the editor drop path")
        XCTAssertTrue(folder.children.isEmpty, "Nothing should have been inserted into the tree on failure")
    }

    // MARK: - Go Menu Top-Level Folder Lookup Tests

    func testTopLevelFolderFindsMatchingRole() {
        let viewModel = SiteViewModel()
        let content = FileNode(url: URL(fileURLWithPath: "/site/content"), isDirectory: true, hugoRole: .content)
        let staticDir = FileNode(url: URL(fileURLWithPath: "/site/static"), isDirectory: true, hugoRole: .staticFiles)
        viewModel.fileNodes = [content, staticDir]

        XCTAssertEqual(viewModel.topLevelFolder(for: .content)?.id, content.id)
        XCTAssertEqual(viewModel.topLevelFolder(for: .staticFiles)?.id, staticDir.id)
        XCTAssertNil(viewModel.topLevelFolder(for: .layouts))
    }

    // MARK: - Toggle Tests

    func testToggleInspector() {
        let viewModel = SiteViewModel()
        let initial = AppSettings.shared.isInspectorVisible

        viewModel.toggleInspector()
        XCTAssertEqual(AppSettings.shared.isInspectorVisible, !initial)

        viewModel.toggleInspector()
        XCTAssertEqual(AppSettings.shared.isInspectorVisible, initial)
    }

    func testToggleFocusMode() {
        let viewModel = SiteViewModel()
        XCTAssertFalse(viewModel.isFocusModeActive)

        viewModel.toggleFocusMode()
        XCTAssertTrue(viewModel.isFocusModeActive)

        viewModel.toggleFocusMode()
        XCTAssertFalse(viewModel.isFocusModeActive)
    }

    func testExitFocusMode() {
        let viewModel = SiteViewModel()

        viewModel.toggleFocusMode()
        XCTAssertTrue(viewModel.isFocusModeActive)

        viewModel.exitFocusMode()
        XCTAssertFalse(viewModel.isFocusModeActive)

        // Calling exitFocusMode when not active should still leave it inactive
        viewModel.exitFocusMode()
        XCTAssertFalse(viewModel.isFocusModeActive)
    }

    // MARK: - Preferences Persistence Tests
    //
    // Preference persistence (auto-save, layout mode, highlight line, font size,
    // inspector visibility) moved to AppSettings (see AppSettingsTests). These
    // tests confirm SiteViewModel now reads/writes through the shared instance.

    func testAutoSaveEnabledPersistence() {
        AppSettings.shared.isAutoSaveEnabled = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.isAutoSaveEnabled))

        AppSettings.shared.isAutoSaveEnabled = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.isAutoSaveEnabled))
    }

    func testLayoutModePersistence() {
        AppSettings.shared.layoutMode = .editor
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.editorLayoutMode),
            EditorLayoutMode.editor.rawValue
        )

        AppSettings.shared.layoutMode = .preview
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.editorLayoutMode),
            EditorLayoutMode.preview.rawValue
        )
    }

    func testHighlightCurrentLinePersistence() {
        AppSettings.shared.highlightCurrentLine = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.highlightCurrentLine))

        AppSettings.shared.highlightCurrentLine = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.highlightCurrentLine))
    }

    func testEditorFontSizePersistence() {
        AppSettings.shared.editorFontSize = 16.0
        XCTAssertEqual(
            UserDefaults.standard.double(forKey: AppConstants.UserDefaultsKeys.editorFontSize),
            16.0
        )
    }

    func testAutoSaveDelayPersistence() {
        AppSettings.shared.autoSaveDelay = 5.0
        XCTAssertEqual(
            UserDefaults.standard.double(forKey: AppConstants.UserDefaultsKeys.autoSaveDelay),
            5.0
        )
    }

    func testInspectorVisiblePersistence() {
        AppSettings.shared.isInspectorVisible = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.isInspectorVisible))

        AppSettings.shared.isInspectorVisible = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.isInspectorVisible))
    }

    // MARK: - Total File Count Tests

    func testTotalFileCountEmpty() {
        let viewModel = SiteViewModel()
        XCTAssertEqual(viewModel.totalFileCount, 0)
    }

    func testTotalFileCountFlat() {
        let viewModel = SiteViewModel()
        let node1 = FileNode(url: URL(fileURLWithPath: "/test/file1.md"), isDirectory: false)
        let node2 = FileNode(url: URL(fileURLWithPath: "/test/file2.md"), isDirectory: false)
        let node3 = FileNode(url: URL(fileURLWithPath: "/test/file3.txt"), isDirectory: false) // Not markdown
        viewModel.fileNodes = [node1, node2, node3]

        XCTAssertEqual(viewModel.totalFileCount, 2, "Only counts markdown files")
    }

    func testTotalFileCountNested() {
        let viewModel = SiteViewModel()

        let directory = FileNode(url: URL(fileURLWithPath: "/test/posts"), isDirectory: true)
        let child1 = FileNode(url: URL(fileURLWithPath: "/test/posts/post1.md"), isDirectory: false)
        let child2 = FileNode(url: URL(fileURLWithPath: "/test/posts/post2.md"), isDirectory: false)
        directory.children = [child1, child2]

        let rootFile = FileNode(url: URL(fileURLWithPath: "/test/index.md"), isDirectory: false)

        viewModel.fileNodes = [directory, rootFile]

        XCTAssertEqual(viewModel.totalFileCount, 3)
    }

    // MARK: - Select Node Tests

    func testSelectNodeUpdatesSelection() {
        let viewModel = SiteViewModel()
        let node = FileNode(url: URL(fileURLWithPath: "/test/file.md"), isDirectory: false)
        viewModel.fileNodes = [node]

        viewModel.selectNode(node)

        XCTAssertEqual(viewModel.selectedNode?.id, node.id)
        XCTAssertEqual(viewModel.selectedFileID, node.id)
        XCTAssertEqual(viewModel.selectedFileIDs, [node.id], "selectNode must also collapse selectedFileIDs to a singleton (victor-sel)")
    }

    func testSelectNilNode() {
        let viewModel = SiteViewModel()
        let node = FileNode(url: URL(fileURLWithPath: "/test/file.md"), isDirectory: false)
        // Node must be in the tree: the canonical selection path resolves by
        // ID via findNode (victor-sel), matching production where every
        // selectNode caller passes a tree-resident node.
        viewModel.fileNodes = [node]

        viewModel.selectNode(node)
        XCTAssertNotNil(viewModel.selectedNode)

        viewModel.selectNode(nil)
        XCTAssertNil(viewModel.selectedNode)
        XCTAssertNil(viewModel.selectedFileID)
        XCTAssertTrue(viewModel.selectedFileIDs.isEmpty, "selectNode(nil) must also clear selectedFileIDs (victor-sel)")
    }

    func testSelectSameNodeNoOp() {
        let viewModel = SiteViewModel()
        let node = FileNode(url: URL(fileURLWithPath: "/test/file.md"), isDirectory: false)
        // In-tree for findNode resolution (victor-sel) - without this the
        // selectedNode assertions compare nil to nil and prove nothing.
        viewModel.fileNodes = [node]

        viewModel.selectNode(node)
        let firstSelectedID = viewModel.selectedNode?.id
        XCTAssertNotNil(firstSelectedID, "fixture must actually select - guards against vacuous nil == nil passes")

        // Select same node again
        viewModel.selectNode(node)

        XCTAssertEqual(viewModel.selectedNode?.id, firstSelectedID, "Should still be the same node")
        XCTAssertEqual(viewModel.selectedFileIDs, [node.id], "selectedFileIDs must still be the singleton after a no-op re-select (victor-sel)")
    }

    func testSelectPageBundleSelectsIndexFile() {
        let viewModel = SiteViewModel()

        // Create a page bundle (directory with index.md)
        let bundle = FileNode(url: URL(fileURLWithPath: "/test/my-post"), isDirectory: true, isPageBundle: true)
        let indexFile = FileNode(url: URL(fileURLWithPath: "/test/my-post/index.md"), isDirectory: false)
        bundle.children = [indexFile]
        indexFile.parent = bundle

        viewModel.fileNodes = [bundle]

        // Selecting the bundle should select the index file instead
        viewModel.selectNode(bundle)

        XCTAssertEqual(viewModel.selectedNode?.id, indexFile.id, "Should select the index file, not the bundle")
        XCTAssertEqual(viewModel.selectedFileIDs, [indexFile.id], "selectedFileIDs must reflect the redirected index file, not the bundle (victor-sel)")
    }

    // MARK: - Expand to Node Tests

    func testExpandToNode() {
        let viewModel = SiteViewModel()

        // Create nested structure: root/posts/2024/article.md
        let root = FileNode(url: URL(fileURLWithPath: "/root"), isDirectory: true)
        let posts = FileNode(url: URL(fileURLWithPath: "/root/posts"), isDirectory: true)
        let year = FileNode(url: URL(fileURLWithPath: "/root/posts/2024"), isDirectory: true)
        let article = FileNode(url: URL(fileURLWithPath: "/root/posts/2024/article.md"), isDirectory: false)

        root.children = [posts]
        posts.children = [year]
        year.children = [article]

        posts.parent = root
        year.parent = posts
        article.parent = year

        viewModel.fileNodes = [root]

        // Initially nothing is expanded
        XCTAssertFalse(root.isExpanded)
        XCTAssertFalse(posts.isExpanded)
        XCTAssertFalse(year.isExpanded)

        // Expand to the article
        viewModel.expandToNode(article)

        // All parent folders should now be expanded
        XCTAssertTrue(root.isExpanded)
        XCTAssertTrue(posts.isExpanded)
        XCTAssertTrue(year.isExpanded)
    }

    func testSelectAndRevealNode() {
        let viewModel = SiteViewModel()

        let root = FileNode(url: URL(fileURLWithPath: "/root"), isDirectory: true)
        let posts = FileNode(url: URL(fileURLWithPath: "/root/posts"), isDirectory: true)
        let article = FileNode(url: URL(fileURLWithPath: "/root/posts/article.md"), isDirectory: false)

        root.children = [posts]
        posts.children = [article]

        posts.parent = root
        article.parent = posts

        viewModel.fileNodes = [root]

        XCTAssertFalse(root.isExpanded)
        XCTAssertFalse(posts.isExpanded)

        viewModel.selectAndRevealNode(article)

        // Should be selected
        XCTAssertEqual(viewModel.selectedNode?.id, article.id)
        XCTAssertEqual(viewModel.selectedFileIDs, [article.id], "selectedFileIDs must reflect the revealed node (victor-sel)")
        // Parents should be expanded
        XCTAssertTrue(root.isExpanded)
        XCTAssertTrue(posts.isExpanded)
    }

    // MARK: - Auto-Expanded Nodes Tests

    func testAutoExpandedNodeIDsClearedOnEmptySearch() {
        let viewModel = SiteViewModel()

        let directory = FileNode(url: URL(fileURLWithPath: "/test/posts"), isDirectory: true)
        let child = FileNode(url: URL(fileURLWithPath: "/test/posts/hello.md"), isDirectory: false)
        directory.children = [child]
        child.parent = directory

        viewModel.fileNodes = [directory]

        // Search for something that matches
        viewModel.searchQuery = "hello"
        _ = viewModel.filteredNodes

        XCTAssertTrue(viewModel.shouldAutoExpand(directory))

        // Clear search
        viewModel.searchQuery = ""
        _ = viewModel.filteredNodes

        XCTAssertFalse(viewModel.shouldAutoExpand(directory))
    }

    // MARK: - Filtered Nodes Caching Tests

    func testFilteredNodesCacheReturnsSameResultOnRepeatedAccess() {
        let viewModel = SiteViewModel()
        let node1 = FileNode(url: URL(fileURLWithPath: "/test/hello.md"), isDirectory: false)
        let node2 = FileNode(url: URL(fileURLWithPath: "/test/world.md"), isDirectory: false)
        viewModel.fileNodes = [node1, node2]

        viewModel.searchQuery = "hello"

        // First access
        let result1 = viewModel.filteredNodes
        // Second access should return cached result
        let result2 = viewModel.filteredNodes

        XCTAssertEqual(result1.count, result2.count)
        XCTAssertEqual(result1.first?.name, result2.first?.name)
    }

    func testFilteredNodesCacheInvalidatedOnQueryChange() {
        let viewModel = SiteViewModel()
        let node1 = FileNode(url: URL(fileURLWithPath: "/test/hello.md"), isDirectory: false)
        let node2 = FileNode(url: URL(fileURLWithPath: "/test/world.md"), isDirectory: false)
        viewModel.fileNodes = [node1, node2]

        viewModel.searchQuery = "hello"
        let result1 = viewModel.filteredNodes
        XCTAssertEqual(result1.count, 1)
        XCTAssertEqual(result1.first?.name, "hello.md")

        // Change query - cache should be invalidated
        viewModel.searchQuery = "world"
        let result2 = viewModel.filteredNodes
        XCTAssertEqual(result2.count, 1)
        XCTAssertEqual(result2.first?.name, "world.md")
    }

    func testFilteredNodesCacheInvalidatedOnCloseSite() {
        let viewModel = SiteViewModel()
        let node = FileNode(url: URL(fileURLWithPath: "/test/hello.md"), isDirectory: false)
        viewModel.fileNodes = [node]

        viewModel.searchQuery = "hello"
        let result1 = viewModel.filteredNodes
        XCTAssertEqual(result1.count, 1)

        // Close site - cache should be invalidated
        viewModel.closeSite()

        // After closing, fileNodes is empty so filtered should be empty too
        XCTAssertTrue(viewModel.filteredNodes.isEmpty)
        XCTAssertTrue(viewModel.selectedFileIDs.isEmpty)
    }

    // MARK: - Lead Derivation Tests (victor-sel, SELECTION-MODEL-MEMO.md section 1)
    //
    // Each test drives `selectedFileIDs = ...` directly, simulating what
    // `List(selection:)` does on click/shift-click/cmd-click/Cmd+A, and
    // asserts `selectedNode`/`selectedFileID` land on the exact id the
    // algorithm in SELECTION-MODEL-MEMO.md section 1 predicts.

    func testLeadDerivation_singleAdd_becomesLead() {
        let viewModel = SiteViewModel()
        let nodeA = FileNode(url: URL(fileURLWithPath: "/test/a.md"), isDirectory: false)
        let nodeB = FileNode(url: URL(fileURLWithPath: "/test/b.md"), isDirectory: false)
        viewModel.fileNodes = [nodeA, nodeB]

        // Simulates a plain click on A from an empty selection.
        viewModel.selectedFileIDs = [nodeA.id]

        assertSelection(viewModel, is: nodeA)
        assertSelectionInvariant(viewModel)
    }

    func testLeadDerivation_removalKeepingLead_leadUnchanged() {
        let viewModel = SiteViewModel()
        let nodeA = FileNode(url: URL(fileURLWithPath: "/test/a.md"), isDirectory: false)
        let nodeB = FileNode(url: URL(fileURLWithPath: "/test/b.md"), isDirectory: false)
        let nodeC = FileNode(url: URL(fileURLWithPath: "/test/c.md"), isDirectory: false)
        viewModel.fileNodes = [nodeA, nodeB, nodeC]

        viewModel.selectNode(nodeA) // lead = A
        // Shift-click extends the selection to include B and C, lead stays A
        // (rule 3: the existing lead survives the change). Not asserted via
        // assertSelection here - the Set is a 3-member selection, not a
        // singleton, so only the lead is checked at this intermediate step.
        viewModel.selectedFileIDs = [nodeA.id, nodeB.id, nodeC.id]
        XCTAssertEqual(viewModel.selectedNode?.id, nodeA.id, "existing lead survives a multi-add that still contains it")

        // Cmd-click deselects C (some OTHER member, not the lead).
        viewModel.selectedFileIDs = [nodeA.id, nodeB.id]

        XCTAssertEqual(viewModel.selectedNode?.id, nodeA.id, "existing lead survives a removal of OTHER members")
        assertSelectionInvariant(viewModel)
    }

    func testLeadDerivation_removalOfLead_fallsBackToTreeOrderFirstSurvivor() {
        let viewModel = SiteViewModel()
        let nodeA = FileNode(url: URL(fileURLWithPath: "/test/a.md"), isDirectory: false)
        let nodeB = FileNode(url: URL(fileURLWithPath: "/test/b.md"), isDirectory: false)
        let nodeC = FileNode(url: URL(fileURLWithPath: "/test/c.md"), isDirectory: false)
        viewModel.fileNodes = [nodeA, nodeB, nodeC]

        viewModel.selectNode(nodeB) // lead = B
        // Not a singleton Set here either - only the lead is checked.
        viewModel.selectedFileIDs = [nodeB.id, nodeC.id] // add C, lead stays B
        XCTAssertEqual(viewModel.selectedNode?.id, nodeB.id, "existing lead survives adding C")

        // Cmd-click deselects B - the lead itself - leaving only C.
        viewModel.selectedFileIDs = [nodeC.id]

        XCTAssertEqual(viewModel.selectedNode?.id, nodeC.id, "lead falls back to the surviving member")
        assertSelectionInvariant(viewModel)
    }

    func testLeadDerivation_clearingSelection_leadBecomesNil() {
        let viewModel = SiteViewModel()
        let nodeA = FileNode(url: URL(fileURLWithPath: "/test/a.md"), isDirectory: false)
        viewModel.fileNodes = [nodeA]

        viewModel.selectNode(nodeA)
        XCTAssertNotNil(viewModel.selectedNode)

        viewModel.selectedFileIDs = []

        assertSelection(viewModel, is: nil)
        assertSelectionInvariant(viewModel)
    }

    func testLeadDerivation_selectAllWithExistingLead_leadUnchanged() {
        let viewModel = SiteViewModel()
        let nodeA = FileNode(url: URL(fileURLWithPath: "/test/a.md"), isDirectory: false)
        let nodeB = FileNode(url: URL(fileURLWithPath: "/test/b.md"), isDirectory: false)
        let nodeC = FileNode(url: URL(fileURLWithPath: "/test/c.md"), isDirectory: false)
        viewModel.fileNodes = [nodeA, nodeB, nodeC]

        viewModel.selectNode(nodeB) // lead = B
        // Cmd+A while B is already the lead.
        viewModel.selectedFileIDs = [nodeA.id, nodeB.id, nodeC.id]

        XCTAssertEqual(viewModel.selectedNode?.id, nodeB.id, "select-all with an existing lead must not move it")
        assertSelectionInvariant(viewModel)
    }

    func testLeadDerivation_selectAllFromEmpty_leadBecomesTreeOrderFirst() {
        let viewModel = SiteViewModel()
        let nodeA = FileNode(url: URL(fileURLWithPath: "/test/a.md"), isDirectory: false)
        let folder = FileNode(url: URL(fileURLWithPath: "/test/folder"), isDirectory: true)
        let nodeInFolder = FileNode(url: URL(fileURLWithPath: "/test/folder/inner.md"), isDirectory: false)
        let nodeB = FileNode(url: URL(fileURLWithPath: "/test/b.md"), isDirectory: false)
        folder.children = [nodeInFolder]
        nodeInFolder.parent = folder
        // Mixed files/folders, known tree order: A, folder, folder's child, B.
        viewModel.fileNodes = [nodeA, folder, nodeB]

        // Cmd+A with nothing selected - includes a folder and its nested child.
        viewModel.selectedFileIDs = [nodeB.id, nodeInFolder.id, folder.id, nodeA.id]

        XCTAssertEqual(viewModel.selectedNode?.id, nodeA.id, "no surviving lead - falls back to the top of the sidebar in tree order")
        assertSelectionInvariant(viewModel)
    }

    func testLeadDerivation_multiAddNoSurvivingLead_fallsBackToTreeOrderFirstOfAdded() {
        let viewModel = SiteViewModel()
        let nodeA = FileNode(url: URL(fileURLWithPath: "/test/a.md"), isDirectory: false)
        let folder = FileNode(url: URL(fileURLWithPath: "/test/folder"), isDirectory: true)
        let nodeInFolder = FileNode(url: URL(fileURLWithPath: "/test/folder/inner.md"), isDirectory: false)
        let nodeC = FileNode(url: URL(fileURLWithPath: "/test/c.md"), isDirectory: false)
        folder.children = [nodeInFolder]
        nodeInFolder.parent = folder
        // Tree order: A, folder, folder's child, C.
        viewModel.fileNodes = [nodeA, folder, nodeC]

        viewModel.selectNode(nodeA) // lead = A
        // Shift-click range (folder's child)...C that doesn't include A - a
        // fresh multi-add with no surviving old lead.
        viewModel.selectedFileIDs = [nodeC.id, nodeInFolder.id]

        XCTAssertEqual(viewModel.selectedNode?.id, nodeInFolder.id, "deterministic fallback: tree-order-first of the newly-added members")
        assertSelectionInvariant(viewModel)
    }

    // MARK: - Canonical Path Side-Effect Tests (victor-sel, orchestrator correction)
    //
    // The memo's original "applySelectionChange sets selectedNode/selectedFileID
    // as plain assignments, never through selectNode" construction (its Risks
    // section) directly contradicted the memo's own section 4 claim that
    // "single-click-to-select already opens the file as a side effect of
    // selectNode's content loading": selectedFileID's own didSet still fired
    // and called selectNode, but immediately early-returned once selectedNode
    // already matched - silently skipping content loading, navigation
    // history, and recent-files tracking for every selection made through the
    // List's Set binding (i.e. every plain click). The orchestrator's fix
    // (isApplyingSelection + performLeadChange, both in SiteViewModel.swift)
    // makes applySelectionChange the canonical path that OWNS those side
    // effects. These tests prove the fix - each drives selectedFileIDs (or
    // the legacy selectedFileID) directly, the way SwiftUI's List binding or
    // an external caller would, and never calls selectNode(_:) itself.

    func testSelectedFileIDsDirectWrite_loadsContentLikeSelectNode() {
        let viewModel = SiteViewModel()
        let node = FileNode(url: URL(fileURLWithPath: "/test/file.md"), isDirectory: false)
        node.contentFile = ContentFile(url: node.url, frontmatter: nil, markdownContent: "hello world")
        viewModel.fileNodes = [node]

        // Simulates the List's native click write - NOT calling selectNode.
        viewModel.selectedFileIDs = [node.id]

        XCTAssertEqual(viewModel.selectedNode?.id, node.id)
        XCTAssertEqual(viewModel.selectedFileID, node.id)
        XCTAssertEqual(viewModel.selectedFileIDs, [node.id])
        XCTAssertEqual(viewModel.currentEditingContent, "hello world", "content must load through the Set path exactly like selectNode used to")
        XCTAssertEqual(viewModel.recentFiles.map(\.id), [node.id], "addRecentFile must fire through the Set path too")
        assertSelectionInvariant(viewModel)
    }

    func testSelectedFileIDsDirectWrite_pageBundleRedirectsToIndexFile() {
        let viewModel = SiteViewModel()
        let bundle = FileNode(url: URL(fileURLWithPath: "/test/my-post"), isDirectory: true, isPageBundle: true)
        let indexFile = FileNode(url: URL(fileURLWithPath: "/test/my-post/index.md"), isDirectory: false)
        bundle.children = [indexFile]
        indexFile.parent = bundle
        viewModel.fileNodes = [bundle]

        // Simulates clicking the bundle folder's own row directly (not the
        // index file row) - a single-member Set write, not a selectNode call.
        viewModel.selectedFileIDs = [bundle.id]

        XCTAssertEqual(viewModel.selectedNode?.id, indexFile.id, "a single-member selection of a page-bundle folder must redirect to its index file")
        XCTAssertEqual(viewModel.selectedFileIDs, [indexFile.id], "the Set itself must be rewritten to the index file's id, not just the derived lead")
        assertSelectionInvariant(viewModel)
    }

    func testSelectedFileIDsDirectWrite_pageBundleInMultiSelectionDoesNotRedirect() {
        let viewModel = SiteViewModel()
        let bundle = FileNode(url: URL(fileURLWithPath: "/test/my-post"), isDirectory: true, isPageBundle: true)
        let indexFile = FileNode(url: URL(fileURLWithPath: "/test/my-post/index.md"), isDirectory: false)
        bundle.children = [indexFile]
        indexFile.parent = bundle
        let other = FileNode(url: URL(fileURLWithPath: "/test/other.md"), isDirectory: false)
        viewModel.fileNodes = [bundle, other]

        viewModel.selectNode(other) // lead = other (a plain file, not the bundle)
        // Cmd-click adds the bundle folder itself to the selection. Existing
        // lead (other) survives per rule 3 - the narrow property under test
        // is that the SET itself must not silently rewrite the bundle's own
        // id to its index file's id just because it's present in a 2+ member
        // selection.
        viewModel.selectedFileIDs = [bundle.id, other.id]

        XCTAssertEqual(viewModel.selectedFileIDs, [bundle.id, other.id], "a multi-selection must never redirect a bundle folder to its index file")
        XCTAssertEqual(viewModel.selectedNode?.id, other.id, "existing lead (other) survives, unaffected by the bundle joining the selection")
        assertSelectionInvariant(viewModel)
    }

    func testSelectedFileIDsDirectWrite_recordsNavigationHistory() {
        let viewModel = SiteViewModel()
        let nodeA = FileNode(url: URL(fileURLWithPath: "/test/a.md"), isDirectory: false)
        let nodeB = FileNode(url: URL(fileURLWithPath: "/test/b.md"), isDirectory: false)
        viewModel.fileNodes = [nodeA, nodeB]

        // Mirrors testNavigationBackReturnsToPreviouslySelectedNode, but
        // drives selection via direct Set writes (simulating List clicks)
        // instead of calling selectNode.
        viewModel.selectedFileIDs = [nodeA.id]
        viewModel.selectedFileIDs = [nodeB.id]
        XCTAssertTrue(viewModel.canNavigateBack, "navigation history must record through the Set write path too")

        viewModel.navigateBack()

        assertSelection(viewModel, is: nodeA)
        XCTAssertFalse(viewModel.canNavigateBack)
        XCTAssertTrue(viewModel.canNavigateForward)
    }

    func testSelectedFileIDDirectWrite_collapsesToSetAndFiresSideEffectsExactlyOnce() {
        let viewModel = SiteViewModel()
        let nodeA = FileNode(url: URL(fileURLWithPath: "/test/a.md"), isDirectory: false)
        let nodeB = FileNode(url: URL(fileURLWithPath: "/test/b.md"), isDirectory: false)
        viewModel.fileNodes = [nodeA, nodeB]

        // Legacy external write path (bypasses selectNode AND selectedFileIDs
        // directly) - must collapse into the canonical Set and run side
        // effects exactly once per write: not zero (the pre-correction bug,
        // where selectedFileID's didSet called selectNode but immediately
        // early-returned) and not twice (a reentrancy bug re-entering
        // applySelectionChange via isApplyingSelection failing to suppress it).
        viewModel.selectedFileID = nodeA.id
        XCTAssertEqual(viewModel.selectedFileIDs, [nodeA.id], "selectedFileID's didSet must collapse into the canonical Set")
        XCTAssertFalse(viewModel.canNavigateBack, "first selection: nowhere to go back to yet - proves this pushed exactly one history entry, not zero")

        viewModel.selectedFileID = nodeB.id
        XCTAssertEqual(viewModel.selectedFileIDs, [nodeB.id])
        XCTAssertTrue(viewModel.canNavigateBack, "second selection must have pushed exactly one more history entry")

        viewModel.navigateBack()
        assertSelection(viewModel, is: nodeA)
        XCTAssertFalse(viewModel.canNavigateBack, "exactly two entries total - a reentrant double-fire on either write would leave extra history behind")

        assertSelectionInvariant(viewModel)
    }

    // MARK: - Invalidation Contract Tests (victor-sel, SELECTION-MODEL-MEMO.md section 8)
    //
    // Mirrors testMarkFileModifiedFiresObservationOnActualTransition/
    // testMarkFileModifiedIsNoOpWhenAlreadyModified (:104-144) for
    // selectedFileIDs - the guarded no-op on identical-Set reassignment is
    // the highest-risk item in the whole design (a naive unconditional
    // didSet would turn every List-internal re-delivery of the same
    // selection into an Observation event, the same class of bug as the two
    // prior keystroke-lag incidents).

    func testSelectedFileIDsFiresObservationOnActualTransition() {
        let viewModel = SiteViewModel()
        let nodeID = UUID()

        nonisolated(unsafe) var observedChange = false
        withObservationTracking {
            _ = viewModel.selectedFileIDs
        } onChange: {
            observedChange = true
        }

        viewModel.selectedFileIDs = [nodeID] // empty -> non-empty: must fire

        XCTAssertTrue(observedChange, "Sanity check: an actual transition must still fire Observation")
    }

    /// Re-verified after the orchestrator's isApplyingSelection correction:
    /// at the moment of this test's second (redundant) assignment,
    /// isApplyingSelection is already back to false (reset via `defer` at the
    /// end of the first assignment's applySelectionChange call), so the
    /// didSet guard reduces to the original `selectedFileIDs != oldValue`
    /// check - unaffected by the reentrancy-suppression addition.
    func testSelectedFileIDsIsNoOpWhenReassignedSameSet() {
        let viewModel = SiteViewModel()
        let nodeID = UUID()
        viewModel.selectedFileIDs = [nodeID]

        nonisolated(unsafe) var observedChange = false
        withObservationTracking {
            _ = viewModel.selectedFileIDs
        } onChange: {
            observedChange = true
        }

        viewModel.selectedFileIDs = [nodeID] // reassigning the identical Set

        XCTAssertFalse(
            observedChange,
            "Repeated identical Set reassignment must not fire Observation (List can and does re-deliver " +
            "the same selection on some internal updates)"
        )
    }

    // MARK: - Batch Trash Tests (victor-sel, SELECTION-MODEL-MEMO.md section 5)
    //
    // No injectable spy is available for FileOperationsService/FileSystemService
    // within this package's touchable-file scope, so these exercise real disk
    // I/O via temp directories (mirroring the existing rename/moveToTrash tests
    // above). "Trashed exactly once, not twice" for a pruned descendant is
    // verified indirectly: if pruning failed and a second trashItem call ran
    // against the descendant's now-vanished path (removed when its ancestor
    // was trashed), FileManager.trashItem throws and populates errorMessage -
    // that's the observable proxy for the call-count assertion the memo asks for.

    func testMoveToTrashBatch_prunesDescendantsOfSelectedFolder() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folderURL = tempDir.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let childURL = folderURL.appendingPathComponent("child.md")
        try "child".write(to: childURL, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let folderNode = FileNode(url: folderURL, isDirectory: true)
        let childNode = FileNode(url: childURL, isDirectory: false)
        folderNode.addChild(childNode)
        viewModel.fileNodes = [folderNode]

        // Select the folder AND its own child - pruning should trash the
        // folder only.
        await viewModel.moveToTrash(nodes: [folderNode, childNode])

        XCTAssertNil(viewModel.errorMessage, "pruning must drop the child before trashing, or the second trashItem call for its now-gone path fails")
        XCTAssertTrue(viewModel.fileNodes.isEmpty, "the folder (and its child with it) should be gone from the tree")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folderURL.path))
    }

    func testMoveToTrashBatch_unrelatedSiblingsAllTrashed() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let urlA = tempDir.appendingPathComponent("a.md")
        let urlB = tempDir.appendingPathComponent("b.md")
        try "a".write(to: urlA, atomically: true, encoding: .utf8)
        try "b".write(to: urlB, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let nodeA = FileNode(url: urlA, isDirectory: false)
        let nodeB = FileNode(url: urlB, isDirectory: false)
        viewModel.fileNodes = [nodeA, nodeB]

        await viewModel.moveToTrash(nodes: [nodeA, nodeB])

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.fileNodes.isEmpty, "no pruning should occur for unrelated siblings - both get trashed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: urlA.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: urlB.path))
    }

    func testMoveToTrashBatch_clearsSelectionAndFallsBackWhenLeadIsTrashed() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let urlA = tempDir.appendingPathComponent("a.md")
        let urlB = tempDir.appendingPathComponent("b.md")
        try "a".write(to: urlA, atomically: true, encoding: .utf8)
        try "b".write(to: urlB, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let nodeA = FileNode(url: urlA, isDirectory: false)
        let nodeB = FileNode(url: urlB, isDirectory: false)
        viewModel.fileNodes = [nodeA, nodeB]

        viewModel.selectNode(nodeA) // lead = A
        viewModel.selectedFileIDs = [nodeA.id, nodeB.id] // A and B selected, A is lead

        // Trash only the lead (A) - B remains untouched.
        await viewModel.moveToTrash(nodes: [nodeA])

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.selectedNode?.id, nodeB.id, "lead falls back to the surviving selected member")
        XCTAssertEqual(viewModel.selectedFileIDs, [nodeB.id])
        assertSelectionInvariant(viewModel)
    }

    func testMoveToTrashBatch_clearsSelectionEntirelyWhenAllTrashed() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let urlA = tempDir.appendingPathComponent("a.md")
        let urlB = tempDir.appendingPathComponent("b.md")
        try "a".write(to: urlA, atomically: true, encoding: .utf8)
        try "b".write(to: urlB, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let nodeA = FileNode(url: urlA, isDirectory: false)
        let nodeB = FileNode(url: urlB, isDirectory: false)
        viewModel.fileNodes = [nodeA, nodeB]

        viewModel.selectedFileIDs = [nodeA.id, nodeB.id] // lead = A (tree-order-first, no prior selection)

        await viewModel.moveToTrash(nodes: [nodeA, nodeB])

        XCTAssertNil(viewModel.errorMessage)
        assertSelection(viewModel, is: nil)
        assertSelectionInvariant(viewModel)
    }

    // MARK: - Undo/Redo Tests (victor-und, Docs/MAC-ARSED-GAP-PLAN.md Phase C.1)
    //
    // `SiteViewModel.registerFileOpUndo` registers `UndoManager.registerUndo(withTarget:handler:)`,
    // whose handler is synchronous - the handler spawns a `Task { @MainActor in ... }`
    // to run the actual (async) inverse file operation. That means
    // `undoManager.undo()`/`.redo()` return before the inverse has actually
    // finished, so these tests poll via `waitUntilUndoSettled` rather than
    // asserting immediately after the call - mirrors the `Task.sleep`-based
    // polling already used elsewhere in this suite (AutoSaveServiceTests,
    // EditorViewModelTests) instead of a single fixed sleep, so they aren't
    // flaky under load.

    /// Polls `condition` until it returns true or `timeout` elapses. See the
    /// MARK comment above for why undo/redo tests need this instead of a
    /// synchronous assertion right after `undo()`/`redo()`.
    private func waitUntilUndoSettled(
        timeout: TimeInterval = 2.0,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("Undo/redo did not settle within \(timeout)s", file: file, line: line)
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func testUndoRenameRestoresOldNameAndRedoReapplies() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("post.md")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let node = FileNode(url: fileURL, isDirectory: false)
        viewModel.fileNodes = [node]

        await viewModel.renameFile(node: node, to: "renamed.md")

        let renamedURL = tempDir.appendingPathComponent("renamed.md")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(node.url, renamedURL)
        XCTAssertEqual(undoManager.undoActionName, "Rename")

        undoManager.undo()
        try await waitUntilUndoSettled { node.url == fileURL }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "undo must restore the file at its original path")
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamedURL.path))

        undoManager.redo()
        try await waitUntilUndoSettled { node.url == renamedURL }
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURL.path), "redo must re-apply the rename")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testUndoMoveReturnsToOriginalFolderAndRedoReapplies() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folderAURL = tempDir.appendingPathComponent("folderA")
        let folderBURL = tempDir.appendingPathComponent("folderB")
        try FileManager.default.createDirectory(at: folderAURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folderBURL, withIntermediateDirectories: true)
        let fileURL = folderAURL.appendingPathComponent("post.md")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let folderANode = FileNode(url: folderAURL, isDirectory: true)
        let folderBNode = FileNode(url: folderBURL, isDirectory: true)
        let fileNode = FileNode(url: fileURL, isDirectory: false)
        folderANode.addChild(fileNode)
        viewModel.fileNodes = [folderANode, folderBNode]

        await viewModel.moveNode(from: fileNode, to: folderBNode)

        let movedURL = folderBURL.appendingPathComponent("post.md")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(fileNode.url, movedURL)
        XCTAssertEqual(undoManager.undoActionName, "Move")

        undoManager.undo()
        try await waitUntilUndoSettled { fileNode.parent?.id == folderANode.id }
        XCTAssertEqual(fileNode.url, fileURL, "undo must return the file to its original folder/path")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: movedURL.path))
        XCTAssertTrue(folderANode.children.contains { $0.id == fileNode.id })
        XCTAssertFalse(folderBNode.children.contains { $0.id == fileNode.id })

        undoManager.redo()
        try await waitUntilUndoSettled { fileNode.parent?.id == folderBNode.id }
        XCTAssertEqual(fileNode.url, movedURL, "redo must re-apply the move")
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedURL.path))
        XCTAssertFalse(folderANode.children.contains { $0.id == fileNode.id })
    }

    func testUndoDuplicateTrashesTheCopyAndRedoRestoresIt() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("post.md")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let node = FileNode(url: fileURL, isDirectory: false)
        viewModel.fileNodes = [node]

        await viewModel.duplicateFile(node: node)

        let duplicateURL = tempDir.appendingPathComponent("post copy.md")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.fileNodes.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: duplicateURL.path))
        XCTAssertEqual(undoManager.undoActionName, "Duplicate")

        undoManager.undo()
        try await waitUntilUndoSettled { viewModel.fileNodes.count == 1 }
        XCTAssertFalse(FileManager.default.fileExists(atPath: duplicateURL.path), "undo must trash the duplicate, not the original")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "the original must be untouched")

        undoManager.redo()
        try await waitUntilUndoSettled { viewModel.fileNodes.count == 2 }
        XCTAssertTrue(FileManager.default.fileExists(atPath: duplicateURL.path), "redo must restore the duplicate from the Trash")
    }

    func testUndoTrashRestoresFileAtOriginalPathAndRedoReTrashes() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let urlA = tempDir.appendingPathComponent("a.md")
        try "a".write(to: urlA, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let nodeA = FileNode(url: urlA, isDirectory: false)
        viewModel.fileNodes = [nodeA]

        await viewModel.moveToTrash(node: nodeA)

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.fileNodes.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: urlA.path))
        XCTAssertEqual(undoManager.undoActionName, "Move to Trash")

        undoManager.undo()
        try await waitUntilUndoSettled { !viewModel.fileNodes.isEmpty }
        XCTAssertTrue(FileManager.default.fileExists(atPath: urlA.path), "undo must restore the file at its original path")
        XCTAssertTrue(viewModel.fileNodes.first === nodeA, "the restored node must be the same FileNode instance, not a rebuilt copy")

        undoManager.redo()
        try await waitUntilUndoSettled { viewModel.fileNodes.isEmpty }
        XCTAssertFalse(FileManager.default.fileExists(atPath: urlA.path), "redo must re-trash the file")
    }

    /// Batch of 2 (one file, one folder) - undo must restore both on disk at
    /// their original paths, re-insert the folder's own child too (trashing
    /// a folder unregisters/removes its whole subtree, so restoring it must
    /// bring the subtree back), and re-insert both nodes in sorted position
    /// (directories first, then alphabetical - `FileNode.sortChildren`'s
    /// convention) among the untouched survivor.
    func testUndoTrashBatchRestoresFilesAndFolderInSortedPositionAndRedoReTrashesAll() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let urlA = tempDir.appendingPathComponent("a.md")
        try "a".write(to: urlA, atomically: true, encoding: .utf8)

        let folderURL = tempDir.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let childURL = folderURL.appendingPathComponent("child.md")
        try "child".write(to: childURL, atomically: true, encoding: .utf8)

        let urlZ = tempDir.appendingPathComponent("z.md")
        try "z".write(to: urlZ, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager

        let nodeA = FileNode(url: urlA, isDirectory: false)          // survives untouched
        let folderNode = FileNode(url: folderURL, isDirectory: true)
        let childNode = FileNode(url: childURL, isDirectory: false)
        folderNode.addChild(childNode)
        let nodeZ = FileNode(url: urlZ, isDirectory: false)          // survives untouched
        viewModel.fileNodes = [nodeA, folderNode, nodeZ]

        await viewModel.moveToTrash(nodes: [folderNode, nodeZ])

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.fileNodes.map(\.id), [nodeA.id], "only the untouched survivor should remain")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folderURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: urlZ.path))
        XCTAssertEqual(undoManager.undoActionName, "Move to Trash")

        undoManager.undo()
        try await waitUntilUndoSettled { viewModel.fileNodes.count == 3 }
        XCTAssertTrue(FileManager.default.fileExists(atPath: folderURL.path), "the folder must be restored")
        XCTAssertTrue(FileManager.default.fileExists(atPath: childURL.path), "the folder's child must come back with it")
        XCTAssertTrue(FileManager.default.fileExists(atPath: urlZ.path), "the file must be restored")
        XCTAssertEqual(
            viewModel.fileNodes.map(\.id), [folderNode.id, nodeA.id, nodeZ.id],
            "restored nodes must land in sorted position (directories first, then alphabetical), not just appended"
        )
        XCTAssertEqual(viewModel.findNode(id: childNode.id)?.id, childNode.id, "the folder's child must be re-registered, not just re-attached")

        undoManager.redo()
        try await waitUntilUndoSettled { viewModel.fileNodes.count == 1 }
        XCTAssertEqual(viewModel.fileNodes.map(\.id), [nodeA.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folderURL.path), "redo must re-trash the folder")
        XCTAssertFalse(FileManager.default.fileExists(atPath: urlZ.path), "redo must re-trash the file")
    }

    /// All four file operations must still work when no window (and therefore
    /// no `UndoManager`) is attached - `SiteViewModel.undoManager` defaults to
    /// nil, and every `registerFileOpUndo` call must no-op rather than crash.
    func testFileOpsWorkWithoutUndoManagerAttached() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("post.md")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)
        let folderURL = tempDir.appendingPathComponent("archive")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        XCTAssertNil(viewModel.undoManager, "sanity check - this test exercises the unwired-window path")

        let node = FileNode(url: fileURL, isDirectory: false)
        let folderNode = FileNode(url: folderURL, isDirectory: true)
        viewModel.fileNodes = [node, folderNode]

        await viewModel.renameFile(node: node, to: "renamed.md")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(node.url, tempDir.appendingPathComponent("renamed.md"))

        await viewModel.moveNode(from: node, to: folderNode)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(folderNode.children.contains { $0.id == node.id })

        await viewModel.duplicateFile(node: node)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(folderNode.children.count, 2)
        guard let duplicateNode = folderNode.children.first(where: { $0.id != node.id }) else {
            return XCTFail("duplicate node not found")
        }

        await viewModel.moveToTrash(node: duplicateNode)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(folderNode.children.map(\.id), [node.id])
    }

    // MARK: - Undo/Redo Re-entrancy Tests (victor-und, program-review D.R finding)
    //
    // UndoManager treats an undo/redo action as "complete" the instant its
    // synchronous handler returns - canUndo/canRedo and the Edit menu
    // re-enable immediately, even though the actual file operation is still
    // an in-flight async Task (see `SiteViewModel.lastFileOpUndoTask`'s doc
    // comment). These tests fire undo()/redo() back-to-back with NO settle
    // wait in between - exactly the rapid-mash window that would otherwise
    // run two inverse operations concurrently - then settle ONCE at the end
    // via `waitUntilUndoSettled` and assert the final state is coherent.

    func testRapidUndoRedoRenameSettlesToRedoneState() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("post.md")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let node = FileNode(url: fileURL, isDirectory: false)
        viewModel.fileNodes = [node]

        await viewModel.renameFile(node: node, to: "renamed.md")
        let renamedURL = tempDir.appendingPathComponent("renamed.md")
        XCTAssertEqual(node.url, renamedURL)

        // No settle wait between these two - the second call's handler fires
        // while the first's inverse rename is still in flight (or hasn't
        // even started). Without the FIFO queue, this races two concurrent
        // `renameFile` calls against the same node/path.
        undoManager.undo()
        undoManager.redo()

        try await waitUntilUndoSettled { node.url == renamedURL }
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURL.path), "must settle to the redone (renamed) state")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "the original path must not still exist - no split-brain disk state")
    }

    func testRapidDoubleUndoRenameNoOpsSafelyOnEmptyStack() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("post.md")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let node = FileNode(url: fileURL, isDirectory: false)
        viewModel.fileNodes = [node]

        await viewModel.renameFile(node: node, to: "renamed.md")
        let renamedURL = tempDir.appendingPathComponent("renamed.md")
        XCTAssertTrue(undoManager.canUndo)

        // Double-tap undo with only one undo action ever registered - the
        // second call finds an empty undo stack (UndoManager's own
        // canUndo-gating no-ops it) and must not crash or corrupt state.
        undoManager.undo()
        undoManager.undo()

        try await waitUntilUndoSettled { node.url == fileURL }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamedURL.path))
        XCTAssertTrue(undoManager.canRedo, "the single undo must still have registered exactly one redo action, not zero or two")
    }

    func testRapidUndoRedoMoveSettlesToRedoneState() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folderAURL = tempDir.appendingPathComponent("folderA")
        let folderBURL = tempDir.appendingPathComponent("folderB")
        try FileManager.default.createDirectory(at: folderAURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folderBURL, withIntermediateDirectories: true)
        let fileURL = folderAURL.appendingPathComponent("post.md")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let folderANode = FileNode(url: folderAURL, isDirectory: true)
        let folderBNode = FileNode(url: folderBURL, isDirectory: true)
        let fileNode = FileNode(url: fileURL, isDirectory: false)
        folderANode.addChild(fileNode)
        viewModel.fileNodes = [folderANode, folderBNode]

        await viewModel.moveNode(from: fileNode, to: folderBNode)
        let movedURL = folderBURL.appendingPathComponent("post.md")
        XCTAssertEqual(fileNode.url, movedURL)

        // No settle wait between these two - same re-entrancy window as the
        // rename test above, but exercising the tree-reparenting path
        // (`parent.children` mutation) rather than just node.url/disk.
        undoManager.undo()
        undoManager.redo()

        try await waitUntilUndoSettled { fileNode.parent?.id == folderBNode.id }
        XCTAssertEqual(fileNode.url, movedURL, "must settle to the redone (moved) state")
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedURL.path))
        XCTAssertFalse(folderANode.children.contains { $0.id == fileNode.id }, "must not be reparented into both folders - no split-brain tree state")
        XCTAssertTrue(folderBNode.children.contains { $0.id == fileNode.id })
    }

    /// Trash chain rapid undo→redo→undo (three ping-pong steps, no settle
    /// wait between any of them) - this is the specific case program review
    /// flagged: a synchronous `switch box.state` read at handler-fire time
    /// would see a STALE generation here, since none of the three inverse
    /// operations have had a chance to run (let alone finish and update the
    /// box) by the time all three handlers have fired. Asserts the box
    /// settles to a single coherent generation - exactly one node, not
    /// duplicated or lost across the three steps.
    func testRapidTrashChainUndoRedoUndoSettlesCoherently() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let urlA = tempDir.appendingPathComponent("a.md")
        try "a".write(to: urlA, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel(fileSystemService: FileSystemService())
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let nodeA = FileNode(url: urlA, isDirectory: false)
        viewModel.fileNodes = [nodeA]

        await viewModel.moveToTrash(node: nodeA)
        XCTAssertTrue(viewModel.fileNodes.isEmpty)

        // undo (restore) -> redo (re-trash) -> undo (restore) again, all
        // fired before any of the three inverse operations has settled.
        undoManager.undo()
        undoManager.redo()
        undoManager.undo()

        try await waitUntilUndoSettled { !viewModel.fileNodes.isEmpty }
        XCTAssertEqual(viewModel.fileNodes.count, 1, "must not duplicate or lose the node across the three rapid ping-pong steps")
        XCTAssertTrue(viewModel.fileNodes.first === nodeA, "must be the same FileNode instance throughout, not a stray rebuilt copy")
        XCTAssertTrue(FileManager.default.fileExists(atPath: urlA.path), "must be restored on disk at its original path")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(undoManager.canRedo, "net three steps from one undo action land on redo (re-trash) being next")
        XCTAssertFalse(undoManager.canUndo)
    }
}
