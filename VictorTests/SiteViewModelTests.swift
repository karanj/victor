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

        await viewModel.renameFile(node: node, to: "renamed.md")

        // Same object instance throughout - `url` was mutated in place, not
        // swapped for a new node, so Observation propagates without needing
        // the old selectedNode = nil; selectedNode = node poke.
        XCTAssertTrue(viewModel.selectedNode === node)
        XCTAssertEqual(viewModel.selectedNode?.url, tempDir.appendingPathComponent("renamed.md"))
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
    /// AFTER the rename completes. Exercises the injected AutoSaveService seam
    /// (victor-zw4) directly against AutoSaveService's own actor-tracked
    /// debounce dictionary.
    func testRenameCancelsPendingAutoSaveForOldPath() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("post.md")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)

        UserDefaults.standard.set(0.3, forKey: AppConstants.UserDefaultsKeys.autoSaveDelay)
        defer { UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.autoSaveDelay) }

        let autoSaveService = AutoSaveService()
        let viewModel = SiteViewModel(fileSystemService: FileSystemService(), autoSaveService: autoSaveService)
        viewModel.site = await HugoSite.create(rootURL: tempDir)
        let node = FileNode(url: fileURL, isDirectory: false)
        node.contentFile = ContentFile(url: fileURL, frontmatter: nil, markdownContent: "original")
        viewModel.fileNodes = [node]

        let saveLanded = expectation(description: "a pre-rename debounce must not fire after the rename")
        saveLanded.isInverted = true

        await autoSaveService.scheduleAutoSave(
            fileURL: fileURL,
            content: "content from a debounce scheduled before the rename",
            lastModified: Date.distantPast,
            onConflict: { .keepLocal },
            onSuccess: { _ in saveLanded.fulfill() },
            onError: { _ in }
        )

        await viewModel.renameFile(node: node, to: "renamed.md")

        await fulfillment(of: [saveLanded], timeout: 0.6)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fileURL.path),
            "renameFile must cancel the pending debounced auto-save for the OLD path before renaming, or the debounce recreates the file there once it fires"
        )
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

        XCTAssertEqual(viewModel.selectedNode?.id, nodeA.id)
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
        XCTAssertEqual(viewModel.selectedNode?.id, nodeA.id)

        viewModel.navigateForward()

        XCTAssertEqual(viewModel.selectedNode?.id, nodeB.id)
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
        XCTAssertEqual(viewModel.selectedNode?.id, nodeB.id)

        viewModel.navigateBack()
        XCTAssertEqual(viewModel.selectedNode?.id, nodeA.id)
        XCTAssertFalse(viewModel.canNavigateBack)

        viewModel.navigateForward()
        XCTAssertEqual(viewModel.selectedNode?.id, nodeB.id)

        viewModel.navigateForward()
        XCTAssertEqual(viewModel.selectedNode?.id, nodeC.id)
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
        XCTAssertEqual(viewModel.selectedNode?.id, nodeA.id)
    }

    func testNavigateBackNoOpWhenAtStartOfHistory() {
        let viewModel = SiteViewModel()
        let node = FileNode(url: URL(fileURLWithPath: "/test/a.md"), isDirectory: false)
        viewModel.fileNodes = [node]
        viewModel.selectNode(node)

        viewModel.navigateBack()

        XCTAssertEqual(viewModel.selectedNode?.id, node.id, "Should remain on the only history entry")
    }

    func testNavigateForwardNoOpWhenAtEndOfHistory() {
        let viewModel = SiteViewModel()
        let nodeA = FileNode(url: URL(fileURLWithPath: "/test/a.md"), isDirectory: false)
        let nodeB = FileNode(url: URL(fileURLWithPath: "/test/b.md"), isDirectory: false)
        viewModel.fileNodes = [nodeA, nodeB]
        viewModel.selectNode(nodeA)
        viewModel.selectNode(nodeB)

        viewModel.navigateForward()

        XCTAssertEqual(viewModel.selectedNode?.id, nodeB.id, "Should remain on the most recent selection")
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
        XCTAssertEqual(viewModel.selectedNode?.id, nodeA.id)
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

        XCTAssertEqual(viewModel.selectedNode?.id, nodeA.id,
                        "One Back press should skip the dead B entry entirely and land on A, not silently no-op")
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
        XCTAssertEqual(viewModel.selectedNode?.id, nodeA.id)

        // Delete nodeB (the entry between the cursor and nodeC) via the real
        // removal path - see comment above for why this (not a direct
        // `fileNodes = [...]` reassignment) is what actually makes it dead.
        await viewModel.moveToTrash(node: nodeB)

        viewModel.navigateForward()

        XCTAssertEqual(viewModel.selectedNode?.id, nodeC.id,
                        "One Forward press should skip the dead B entry entirely and land on C, not silently no-op")
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
    }

    func testSelectNilNode() {
        let viewModel = SiteViewModel()
        let node = FileNode(url: URL(fileURLWithPath: "/test/file.md"), isDirectory: false)

        viewModel.selectNode(node)
        XCTAssertNotNil(viewModel.selectedNode)

        viewModel.selectNode(nil)
        XCTAssertNil(viewModel.selectedNode)
        XCTAssertNil(viewModel.selectedFileID)
    }

    func testSelectSameNodeNoOp() {
        let viewModel = SiteViewModel()
        let node = FileNode(url: URL(fileURLWithPath: "/test/file.md"), isDirectory: false)

        viewModel.selectNode(node)
        let firstSelectedID = viewModel.selectedNode?.id

        // Select same node again
        viewModel.selectNode(node)

        XCTAssertEqual(viewModel.selectedNode?.id, firstSelectedID, "Should still be the same node")
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
    }
}
