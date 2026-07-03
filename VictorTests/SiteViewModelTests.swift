import XCTest
@testable import Victor

/// Tests for SiteViewModel
@MainActor
final class SiteViewModelTests: XCTestCase {

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
        // Clear relevant UserDefaults
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.isAutoSaveEnabled)
        defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.editorLayoutMode)
        defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.highlightCurrentLine)
        defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.editorFontSize)
        defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.autoSaveDelay)
        defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.isInspectorVisible)

        let viewModel = SiteViewModel()

        // Check defaults
        XCTAssertTrue(viewModel.isAutoSaveEnabled, "Auto-save should default to true")
        XCTAssertEqual(viewModel.layoutMode, .split, "Layout mode should default to split")
        XCTAssertTrue(viewModel.highlightCurrentLine, "Highlight current line should default to true")
        XCTAssertEqual(viewModel.editorFontSize, 13.0, "Font size should default to 13")
        XCTAssertEqual(viewModel.autoSaveDelay, 2.0, "Auto-save delay should default to 2 seconds")
        XCTAssertFalse(viewModel.isInspectorVisible, "Inspector should default to hidden")
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

    func testSaveAllModifiedFilesWritesEditedContentNotStaleContent() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("post.md")
        try "original content".write(to: fileURL, atomically: true, encoding: .utf8)

        let viewModel = SiteViewModel()
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

    // MARK: - Toggle Tests

    func testToggleInspector() {
        let viewModel = SiteViewModel()
        let initial = viewModel.isInspectorVisible

        viewModel.toggleInspector()
        XCTAssertEqual(viewModel.isInspectorVisible, !initial)

        viewModel.toggleInspector()
        XCTAssertEqual(viewModel.isInspectorVisible, initial)
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

    func testAutoSaveEnabledPersistence() {
        let viewModel = SiteViewModel()

        viewModel.isAutoSaveEnabled = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.isAutoSaveEnabled))

        viewModel.isAutoSaveEnabled = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.isAutoSaveEnabled))
    }

    func testLayoutModePersistence() {
        let viewModel = SiteViewModel()

        viewModel.layoutMode = .editor
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.editorLayoutMode),
            EditorLayoutMode.editor.rawValue
        )

        viewModel.layoutMode = .preview
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.editorLayoutMode),
            EditorLayoutMode.preview.rawValue
        )
    }

    func testHighlightCurrentLinePersistence() {
        let viewModel = SiteViewModel()

        viewModel.highlightCurrentLine = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.highlightCurrentLine))

        viewModel.highlightCurrentLine = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.highlightCurrentLine))
    }

    func testEditorFontSizePersistence() {
        let viewModel = SiteViewModel()

        viewModel.editorFontSize = 16.0
        XCTAssertEqual(
            UserDefaults.standard.double(forKey: AppConstants.UserDefaultsKeys.editorFontSize),
            16.0
        )
    }

    func testAutoSaveDelayPersistence() {
        let viewModel = SiteViewModel()

        viewModel.autoSaveDelay = 5.0
        XCTAssertEqual(
            UserDefaults.standard.double(forKey: AppConstants.UserDefaultsKeys.autoSaveDelay),
            5.0
        )
    }

    func testInspectorVisiblePersistence() {
        let viewModel = SiteViewModel()

        viewModel.isInspectorVisible = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.isInspectorVisible))

        viewModel.isInspectorVisible = false
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
