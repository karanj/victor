import AppKit
import Foundation
import SwiftUI

// MARK: - Editor Layout Mode

/// Represents the three layout modes for the editor/preview area
enum EditorLayoutMode: String, CaseIterable {
    /// Full-width editor only (preview hidden)
    case editor
    /// Full-width preview only (editor hidden)
    case preview
    /// Side-by-side editor and preview (default, current behavior)
    case split

    /// Display name for UI
    var displayName: String {
        switch self {
        case .editor: return "Editor"
        case .preview: return "Preview"
        case .split: return "Split"
        }
    }

    /// SF Symbol icon name
    var iconName: String {
        switch self {
        case .editor: return "doc.text"
        case .preview: return "eye"
        case .split: return "rectangle.split.2x1"
        }
    }
}

// MARK: - Pane Focus Direction

/// W5.1 (victor-kbd): direction of pane-focus traversal requested from the
/// View menu (Cmd+Option+Left/Right), consumed by `ContentView`'s
/// `@FocusState<AppPane?>`. Mirrors the app's Xcode-style navigator/editor/
/// inspector traversal convention.
enum PaneFocusDirection {
    case previous
    case next
}

/// Main view model managing the Hugo site state
@MainActor
@Observable
class SiteViewModel {
    /// Currently opened Hugo site
    var site: HugoSite?

    /// File nodes (flat list in Phase 1, tree in Phase 4)
    var fileNodes: [FileNode] = []

    /// Fast lookup table for nodes by ID (O(1) instead of O(n) tree traversal)
    private var nodeByID: [UUID: FileNode] = [:]

    /// Manages LRU caching of edited file content
    private let fileCacheManager = FileCacheManager()

    /// Currently selected file node
    var selectedNode: FileNode?

    /// Held for the duration of `applySelectionChange` so its writes to
    /// `selectedNode`/`selectedFileID`/`selectedFileIDs` don't re-enter their own `didSet`s.
    private var isApplyingSelection = false

    /// Legacy single-selection write path. Collapses into `selectedFileIDs` so
    /// `applySelectionChange` stays the only place that derives the lead.
    var selectedFileID: FileNode.ID? {
        didSet {
            guard !isApplyingSelection, selectedFileID != oldValue else { return }
            selectedFileIDs = selectedFileID.map { [$0] } ?? []
        }
    }

    /// Source of truth for FileListView's `List(selection:)` under multi-select.
    /// Transition-only state (CLAUDE.md per-keystroke contract). `selectedNode`/
    /// `selectedFileID` are the derived *lead*. See Docs/SELECTION-MODEL-MEMO.md.
    var selectedFileIDs: Set<FileNode.ID> = [] {
        didSet {
            // List re-delivers an identical Set on some internal updates (drag-select
            // intermediates); recomputing the lead each time fires Observation for nothing.
            guard !isApplyingSelection, selectedFileIDs != oldValue else { return }
            applySelectionChange(oldIDs: oldValue)
        }
    }

    /// Derives the lead from a `selectedFileIDs` change and applies it via
    /// `performLeadChange`, the only place lead-change side effects run (content load,
    /// history, recents, inspector). Derivation rules: Docs/SELECTION-MODEL-MEMO.md §1.
    private func applySelectionChange(oldIDs: Set<FileNode.ID>) {
        isApplyingSelection = true
        defer { isApplyingSelection = false }

        let newIDs = selectedFileIDs
        let lead: FileNode.ID?

        if newIDs.isEmpty {
            // Rule 1: nothing selected.
            lead = nil
        } else if let currentLead = selectedNode?.id, newIDs.contains(currentLead) {
            // Rule 3: existing lead survives the change (pure removal of
            // OTHER members, or a select-all/range-extend that keeps it).
            lead = currentLead
        } else {
            // Rule 4: no surviving lead - deterministic fallback.
            let added = newIDs.subtracting(oldIDs)
            if added.count == 1 {
                // Single new element added (click, cmd-click add, arrow-key move).
                lead = added.first!
            } else if added.count > 1 {
                // Multi-add with no surviving old lead (e.g. a shift-click
                // range that doesn't include the old lead, or select-all from
                // nothing selected).
                lead = firstInTreeOrder(of: added)
            } else {
                // added is empty and the old lead is gone - pure removal that
                // dropped the lead (e.g. cmd-click deselecting the lead row,
                // or a batch trash of the lead - see moveToTrash(nodes:)).
                lead = firstInTreeOrder(of: newIDs)
            }
        }

        var leadNode = lead.flatMap { findNode(id: $0) }

        // Page-bundle redirect ONLY for a single-member selection - mirrors
        // the redirect selectNode(_:) used to do inline. A bundle folder
        // cmd-clicked into a 2+ selection stays itself; multi-selections
        // never redirect. Reassigning selectedFileIDs here is safe under
        // isApplyingSelection (suppressed re-entry into this same method).
        if newIDs.count == 1, let bundle = leadNode, bundle.isPageBundle, let indexFile = bundle.indexFile {
            selectedFileIDs = [indexFile.id]
            leadNode = indexFile
        }

        if leadNode?.id != selectedNode?.id {
            // Lead actually changed (including nil, per rule 1) - run the
            // side effects.
            performLeadChange(to: leadNode)
        } else {
            // Lead unchanged (rule 3's common case, or a mouse-drag's
            // intermediate Set deliveries) - keep selectedFileID in sync
            // without re-running side effects, so those stay cheap.
            selectedFileID = leadNode?.id
        }
    }

    /// Lead-change side effects plus the final `selectedNode`/`selectedFileID` writes.
    /// Called only from `applySelectionChange`, which suppresses `didSet` re-entry.
    private func performLeadChange(to node: FileNode?) {
        // OPTIMISTIC UPDATE: Update UI immediately, before any loading
        selectedNode = node

        // Record for Go > Back/Forward (no-ops while replaying history itself)
        if let node {
            pushNavigationHistory(node)
        }

        // Auto-hide inspector when switching to a non-markdown file
        // (The inspector toolbar button is only shown for markdown files,
        // so we need to auto-dismiss to prevent the user being stuck)
        if AppSettings.shared.isInspectorVisible && (node == nil || !node!.isMarkdownFile) {
            AppSettings.shared.isInspectorVisible = false
        }

        // Plain assignment - suppressed by isApplyingSelection, doesn't
        // re-enter selectedFileID's didSet.
        selectedFileID = node?.id

        // Persist selected file path for restoration on next launch
        if let path = node?.url.path {
            UserDefaults.standard.set(path, forKey: AppConstants.UserDefaultsKeys.lastSelectedFilePath)
        } else {
            UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.lastSelectedFilePath)
        }

        // Load content based on file type
        // Only initialize content if there's no existing edited content for this file
        // (preserves unsaved edits when switching between files)
        if let node, node.isMarkdownFile {
            if let contentFile = node.contentFile {
                // Content already loaded - only set if no existing edits
                if !fileCacheManager.hasContent(for: node.id) {
                    fileCacheManager.setContent(contentFile.markdownContent, for: node.id)
                }
                addRecentFile(node)
                updateContentCache(accessedNodeID: node.id)
            } else {
                // Content not loaded - load in background
                isLoadingFile = true
                Task { [weak self] in
                    guard let self = self else { return }
                    await self.loadFileContent(for: node)
                    // Only update content if this node is still selected and has no edits
                    if node.id == self.selectedNode?.id,
                       !self.fileCacheManager.hasContent(for: node.id) {
                        self.fileCacheManager.setContent(node.contentFile?.markdownContent ?? "", for: node.id)
                    }
                    if node.id == self.selectedNode?.id {
                        self.addRecentFile(node)
                        self.updateContentCache(accessedNodeID: node.id)
                    }
                    self.isLoadingFile = false
                }
            }
        } else if let node, node.isEditable && node.fileType.isTextBased {
            // Non-markdown editable text file
            if node.textFile == nil {
                isLoadingFile = true
                Task { [weak self] in
                    guard let self = self else { return }
                    await self.loadTextFileContent(for: node)
                    self.isLoadingFile = false
                }
            }
        }
        // For non-editable files and folders, no content loading needed
    }

    /// Members of `ids` in display order (the traversal FileListView renders). Used for
    /// deterministic lead fallback and Cmd+C ordering, instead of Set-iteration order.
    func treeOrderIndex(of ids: Set<FileNode.ID>) -> [FileNode.ID] {
        var result: [FileNode.ID] = []
        func visit(_ nodes: [FileNode]) {
            for node in nodes {
                if ids.contains(node.id) {
                    result.append(node.id)
                }
                if node.isDirectory {
                    visit(node.children)
                }
            }
        }
        visit(filteredNodes)
        return result
    }

    /// The tree-order-first member of `ids` - see `treeOrderIndex(of:)`.
    private func firstInTreeOrder(of ids: Set<FileNode.ID>) -> FileNode.ID? {
        treeOrderIndex(of: ids).first
    }

    /// Bumped on every edited-content write. The one signal views may observe to react to
    /// typing (preview, inspector stats - each debounced); `FileCacheManager` is
    /// deliberately not @Observable. Menu/chrome must use `isFileModified` instead.
    private(set) var editedContentVersion: Int = 0

    /// Current editing content (for preview sync across layout modes)
    /// Computed property that reads/writes from cache based on selected node
    var currentEditingContent: String {
        get {
            guard let nodeID = selectedNode?.id else { return "" }
            return fileCacheManager.getContent(for: nodeID) ?? ""
        }
        set {
            guard let nodeID = selectedNode?.id else { return }
            setEditedContent(newValue, for: nodeID)
        }
    }

    /// Get edited content for a specific file by ID (regardless of which file is selected)
    /// Used by EditorViewModel to retrieve content for its specific file
    func getEditedContent(for nodeID: UUID) -> String? {
        return fileCacheManager.getContent(for: nodeID)
    }

    /// Set edited content for a specific file by ID (regardless of which file is selected)
    /// Used by EditorViewModel to update content for its specific file.
    /// The single write path for edited content - bumps editedContentVersion.
    func setEditedContent(_ content: String, for nodeID: UUID) {
        fileCacheManager.setContent(content, for: nodeID)
        editedContentVersion += 1
    }

    /// Live preview enabled state (controls real-time updates in split view)
    var isLivePreviewEnabled: Bool = true

    /// Focus mode active state (not persisted - always starts inactive)
    var isFocusModeActive: Bool = false

    // MARK: - Hugo Server State

    /// Current Hugo development server status
    var hugoServerStatus: HugoServerStatus = .stopped

    /// Whether the Hugo server is currently running
    var isHugoServerRunning: Bool {
        hugoServerStatus.isRunning
    }

    /// Build errors from the Hugo server
    var hugoBuildErrors: [HugoBuildError] = []

    /// Server URL when running
    var hugoServerURL: URL?

    /// Whether to use live preview (Hugo server) instead of markdown preview
    var useLivePreview: Bool = false

    /// Loading state (for site loading)
    var isLoading = false

    /// Loading state for file content (prevents flash during file switch)
    var isLoadingFile = false

    /// Error message
    var errorMessage: String?

    /// Search query
    var searchQuery = ""

    /// Trigger to focus search field
    var shouldFocusSearch = false

    /// Pane-traversal direction requested by the View menu; `ContentView` observes and
    /// resets to nil once consumed (its `@FocusState` isn't reachable from `VictorApp`).
    var paneFocusDirection: PaneFocusDirection?

    /// Whether global search panel is presented
    var isGlobalSearchPresented = false

    /// Whether the "New Post…" sheet (NewContentView) is presented.
    /// Set by File > New Post… (Cmd+N); the presenting view resolves the
    /// target directory via `newContentTargetFolder` when it fires.
    var isNewContentPresented = false

    /// Recently opened files (for Quick Open)
    var recentFiles: [FileNode] = []

    /// Maximum number of recent files to track
    private let maxRecentFiles = 10

    // MARK: - Specialized File Properties (delegated to SpecializedFileManager)

    /// Hugo configuration (loaded when a config file is selected)
    var hugoConfig: HugoConfig? {
        get { specializedFileManager.hugoConfig }
        set { specializedFileManager.hugoConfig = newValue }
    }

    /// Whether the Hugo config is currently loading
    var isLoadingConfig: Bool { specializedFileManager.isLoadingConfig }

    /// Currently loaded data file (computed from per-file storage based on selected node)
    var currentDataFile: DataFile? {
        get {
            guard let url = selectedNode?.url else { return nil }
            return specializedFileManager.getDataFile(for: url)
        }
        set {
            guard let url = selectedNode?.url else { return }
            specializedFileManager.setDataFile(newValue, for: url)
        }
    }

    /// Whether a data file is currently loading
    var isLoadingDataFile: Bool { specializedFileManager.isLoadingDataFile }

    /// Error from last data file load attempt (to prevent infinite retry)
    var dataFileLoadError: String? { specializedFileManager.dataFileLoadError }

    /// URL of the last failed data file load (to prevent infinite retry)
    var failedDataFileURL: URL? { specializedFileManager.failedDataFileURL }

    /// Currently loaded template (computed from per-file storage based on selected node)
    var currentTemplate: Template? {
        get {
            guard let url = selectedNode?.url else { return nil }
            return specializedFileManager.getTemplate(for: url)
        }
        set {
            guard let url = selectedNode?.url else { return }
            specializedFileManager.setTemplate(newValue, for: url)
        }
    }

    /// Whether a template is currently loading
    var isLoadingTemplate: Bool { specializedFileManager.isLoadingTemplate }

    /// Error from last template load attempt
    var templateLoadError: String? { specializedFileManager.templateLoadError }

    /// URL of the last failed template load
    var failedTemplateURL: URL? { specializedFileManager.failedTemplateURL }

    /// Currently loaded archetype (computed from per-file storage based on selected node)
    var currentArchetype: Archetype? {
        get {
            guard let url = selectedNode?.url else { return nil }
            return specializedFileManager.getArchetype(for: url)
        }
        set {
            guard let url = selectedNode?.url else { return }
            specializedFileManager.setArchetype(newValue, for: url)
        }
    }

    /// Whether an archetype is currently loading
    var isLoadingArchetype: Bool { specializedFileManager.isLoadingArchetype }

    /// Error from last archetype load attempt
    var archetypeLoadError: String? { specializedFileManager.archetypeLoadError }

    /// URL of the last failed archetype load
    var failedArchetypeURL: URL? { specializedFileManager.failedArchetypeURL }

    /// Maximum number of ContentFiles to keep cached in memory
    /// Files beyond this limit will have their contentFile released
    /// ContentFile objects are heavier than strings, but 50 is still reasonable
    private let maxCachedContentFiles = 50

    /// LRU cache tracking: ordered list of node IDs with loaded content (most recent first)
    /// Note: This tracks loaded ContentFile/TextFile objects, separate from edited content in FileCacheManager
    private var contentCacheOrder: [UUID] = []

    /// Stored, not computed from UserDefaults on read - a computed property is invisible
    /// to @Observable, which left the Open Recent submenu stale after Clear Menu.
    var recentSitePaths: [String] =
        UserDefaults.standard.stringArray(forKey: AppConstants.UserDefaultsKeys.recentSitePaths) ?? []

    /// Maximum number of recent sites to track
    private let maxRecentSites = 5

    // MARK: - File Status Tracking

    /// Files with unsaved changes (tracked by node ID)
    var modifiedFileIDs: Set<UUID> = []

    /// Files that were recently saved (node ID -> save timestamp)
    var recentlySavedFileIDs: [UUID: Date] = [:]

    /// Set of folder IDs that have had their children's status metadata loaded
    private var loadedStatusFolderIDs: Set<UUID> = []

    /// Duration to show "saved" indicator before fading
    private let savedIndicatorDuration: TimeInterval = 3.0

    /// File system service (for site loading, content reading). Not `private`
    /// (victor-zw4): EditorTextView's Coordinator reaches this via `siteViewModel.fileSystemService`
    /// so a test-injected instance flows through to the drag-and-drop import path too.
    let fileSystemService: FileSystemService

    /// File operations service (for create, rename, duplicate, trash). Always built from
    /// this instance's `fileSystemService` (victor-zw4) rather than `FileOperationsService.shared`,
    /// so an injected `fileSystemService` isolates file operations too, not just reads.
    private let fileOperationsService: FileOperationsService

    /// Hugo server service (for start/stop/status streams - WP3.5 Cluster 9). Not `private`
    /// (victor-zw4): ServerControlView/LivePreviewPanel/ServerConfigPopover reach this via
    /// `siteViewModel.hugoServerService` instead of `HugoServerService.shared`.
    let hugoServerService: HugoServerService

    /// `renameFile` cancels this node's pending debounced save before touching disk, so an
    /// in-flight save can't land after the move and recreate the file at the old path.
    private let autoSaveService: AutoSaveService

    /// Assigned by `ContentView` from `@Environment(\.undoManager)`. Weak, and every
    /// registration site nil-checks it, so tests constructing this bare still work.
    weak var undoManager: UndoManager?

    /// Specialized file manager (for Hugo config, data files, templates, archetypes)
    let specializedFileManager = SpecializedFileManager()

    /// Set of node IDs that should be auto-expanded during search
    private(set) var autoExpandedNodeIDs: Set<UUID> = []

    // MARK: - Filtered Nodes Cache

    /// Cached result of filteredNodes computation
    private var _cachedFilteredNodes: [FileNode]?

    /// The search query used to compute the cached result
    private var _cachedSearchQuery: String = ""

    /// Version counter for fileNodes - incremented when fileNodes changes
    private var _fileNodesVersion: Int = 0

    /// The fileNodes version when cache was last computed
    private var _cachedFileNodesVersion: Int = -1

    /// Filtered file nodes based on search (recursively searches tree)
    /// Results are cached to avoid recomputation on every SwiftUI render cycle
    var filteredNodes: [FileNode] {
        // Guarded: unconditionally mutating @Observable state from a computed property
        // read inside a live view body can retrigger re-render indefinitely (victor-doc).
        guard !searchQuery.isEmpty else {
            if !autoExpandedNodeIDs.isEmpty {
                autoExpandedNodeIDs.removeAll()
            }
            if _cachedFilteredNodes != nil {
                _cachedFilteredNodes = nil
            }
            return fileNodes
        }

        // Check if cache is valid
        if let cached = _cachedFilteredNodes,
           _cachedSearchQuery == searchQuery,
           _cachedFileNodesVersion == _fileNodesVersion {
            return cached
        }

        // Recompute and cache
        autoExpandedNodeIDs.removeAll()
        let result = filterNodesRecursively(fileNodes, query: searchQuery)

        _cachedFilteredNodes = result
        _cachedSearchQuery = searchQuery
        _cachedFileNodesVersion = _fileNodesVersion

        return result
    }

    /// Invalidate the filtered nodes cache (call when fileNodes changes)
    private func invalidateFilterCache() {
        _fileNodesVersion += 1
        _cachedFilteredNodes = nil
    }

    /// Content file paths for autocomplete (relative to content/ directory)
    var contentPaths: [ContentPathSuggestion] {
        guard let contentURL = site?.contentDirectory else { return [] }
        var paths: [ContentPathSuggestion] = []
        // Find the content directory node and collect paths from it
        for node in fileNodes {
            if node.isDirectory && node.hugoRole == .content {
                collectContentPaths(from: node.children, contentURL: contentURL, into: &paths)
                break
            }
        }
        return paths.sorted { $0.path < $1.path }
    }

    /// Recursively collect markdown content file paths from within the content directory
    private func collectContentPaths(from nodes: [FileNode], contentURL: URL, into paths: inout [ContentPathSuggestion]) {
        for node in nodes {
            if node.isDirectory {
                collectContentPaths(from: node.children, contentURL: contentURL, into: &paths)
            } else if node.fileType == .markdown {
                // Calculate relative path from content directory
                let fullPath = node.url.path
                let contentPath = contentURL.path
                if fullPath.hasPrefix(contentPath) {
                    var relativePath = String(fullPath.dropFirst(contentPath.count))
                    if relativePath.hasPrefix("/") {
                        relativePath = String(relativePath.dropFirst())
                    }
                    paths.append(ContentPathSuggestion(path: relativePath, displayName: node.name))
                }
            }
        }
    }

    /// Total count of markdown files (leaf nodes) in the site
    var totalFileCount: Int {
        countFilesRecursively(fileNodes)
    }

    /// Recursively count markdown files in the tree
    private func countFilesRecursively(_ nodes: [FileNode]) -> Int {
        var count = 0
        for node in nodes {
            if node.isDirectory {
                count += countFilesRecursively(node.children)
            } else if node.isMarkdownFile {
                count += 1
            }
        }
        return count
    }

    /// Check if a node should be auto-expanded during search
    func shouldAutoExpand(_ node: FileNode) -> Bool {
        autoExpandedNodeIDs.contains(node.id)
    }

    /// Recursively filter nodes - minimizes object creation by reusing originals where possible
    /// NOTE: This still creates some FileNode instances for directories with filtered children.
    /// Complete fix would require making FileNode a struct (value type) instead of class.
    private func filterNodesRecursively(_ nodes: [FileNode], query: String) -> [FileNode] {
        var filtered: [FileNode] = []

        for node in nodes {
            if node.isDirectory {
                // Recursively filter children
                let filteredChildren = filterNodesRecursively(node.children, query: query)

                if !filteredChildren.isEmpty {
                    // Directory has matching children
                    // Mark this node for auto-expansion
                    autoExpandedNodeIDs.insert(node.id)

                    // Only create a new instance if children are filtered
                    // This is unavoidable with current architecture (FileNode is a class)
                    if filteredChildren.count < node.children.count {
                        // Need filtered view - create minimal copy with cached isPageBundle
                        let filteredNode = FileNode(url: node.url, isDirectory: true, isPageBundle: node.isPageBundle)
                        filteredNode.children = filteredChildren
                        filtered.append(filteredNode)
                    } else {
                        // All children match - reuse original
                        filtered.append(node)
                    }
                } else if node.name.localizedCaseInsensitiveContains(query) {
                    // Directory name matches - return original
                    filtered.append(node)
                }
            } else {
                // File node - reuse original (no copies needed)
                if node.name.localizedCaseInsensitiveContains(query) {
                    filtered.append(node)
                }
            }
        }

        return filtered
    }

    /// Cold-launch auto-restore. A Dock-drop / Open With request awaits this so it can't
    /// race `loadSite` and leave `filteredNodes`' cache thrashing between versions.
    private(set) var initialSiteRestoreTask: Task<Void, Never>?

    /// Services default to the process-wide singletons; tests pass their own for isolation
    /// (victor-zw4). `fileOperationsService` is derived from `fileSystemService`, not injected.
    init(
        fileSystemService: FileSystemService = .shared,
        hugoServerService: HugoServerService = .shared,
        autoSaveService: AutoSaveService = .shared
    ) {
        self.fileSystemService = fileSystemService
        self.fileOperationsService = FileOperationsService(fileSystemService: fileSystemService)
        self.hugoServerService = hugoServerService
        self.autoSaveService = autoSaveService

        // Try to load previously opened site
        initialSiteRestoreTask = Task { [weak self] in
            await self?.loadSavedSite()
        }
    }

    // MARK: - Site Operations

    /// Open a Hugo site folder
    func openSiteFolder() async {
        guard let url = await fileSystemService.selectHugoSiteFolder() else {
            return
        }

        await loadSite(from: url)
    }

    /// Load a Hugo site from URL
    func loadSite(from url: URL) async {
        // Serialize all load paths (Cmd+O, Open Recent, Dock menu, Dock drop,
        // onOpenURL) at this single choke point: two interleaved loads both
        // reassign fileNodes and bump _fileNodesVersion, thrashing
        // filteredNodes' cache into a busy re-render loop. Dropping the late
        // request is correct for user-initiated opens.
        guard !isLoading else {
            Logger.shared.info("Ignoring site open for \(url.lastPathComponent): another site load is in flight")
            return
        }
        isLoading = true
        errorMessage = nil

        do {
            // Create site asynchronously (file I/O on background thread)
            let site = await HugoSite.create(rootURL: url)

            // Validate it's a Hugo site (async to avoid blocking main thread)
            guard await site.validateAsync() else {
                errorMessage = "Selected folder does not appear to be a Hugo site. Make sure it has a 'content' directory or config file."
                isLoading = false
                return
            }

            // Save security-scoped bookmark
            let bookmarkData = try fileSystemService.saveBookmark(for: url)
            site.bookmarkData = bookmarkData

            // Scan for files
            let nodes = try fileSystemService.scanDirectory(at: url)

            // Update state
            self.site = site
            self.fileNodes = nodes

            // Invalidate filter cache and build lookup table
            invalidateFilterCache()
            buildNodeLookupTable()

            // Track this site in recent sites (our own File > Open Recent submenu)
            addRecentSite(url.path)

            // Also register with the system so the site shows up in the Dock icon's
            // right-click menu and App Exposé, even though we render our own submenu.
            NSDocumentController.shared.noteNewRecentDocumentURL(url)

            // Restore last selected file if it exists in this site
            restoreLastSelectedFile()

            Logger.shared.info("Loaded Hugo site: \(site.displayName)")
            Logger.shared.info("Found \(nodes.count) markdown files")

        } catch {
            errorMessage = "Failed to load site: \(error.localizedDescription)"
            Logger.shared.error("Error loading site", error: error)
        }

        isLoading = false
    }

    /// Add a site to the recent sites list
    private func addRecentSite(_ path: String) {
        recentSitePaths.removeAll { $0 == path }
        recentSitePaths.insert(path, at: 0)

        if recentSitePaths.count > maxRecentSites {
            recentSitePaths = Array(recentSitePaths.prefix(maxRecentSites))
        }

        persistRecentSitePaths()
    }

    /// Open a recent site by path
    func openRecentSite(_ path: String) async {
        let url = URL(fileURLWithPath: path)

        // Check if the path still exists
        guard FileManager.default.fileExists(atPath: path) else {
            // Remove from recent sites if it no longer exists
            recentSitePaths.removeAll { $0 == path }
            persistRecentSitePaths()
            errorMessage = "Site folder no longer exists at: \(path)"
            return
        }

        await loadSite(from: url)
    }

    /// Clear recent sites list
    func clearRecentSites() {
        recentSitePaths = []
        persistRecentSitePaths()
    }

    /// Remove a single site from the recent sites list
    func removeRecentSite(_ path: String) {
        recentSitePaths.removeAll { $0 == path }
        persistRecentSitePaths()
    }

    /// Persist the current `recentSitePaths` to UserDefaults. All mutators
    /// call this after updating the observable property so the two never drift.
    private func persistRecentSitePaths() {
        UserDefaults.standard.set(recentSitePaths, forKey: AppConstants.UserDefaultsKeys.recentSitePaths)
    }

    /// Restore last selected file from UserDefaults
    private func restoreLastSelectedFile() {
        guard let lastPath = UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.lastSelectedFilePath) else {
            return
        }

        let lastURL = URL(fileURLWithPath: lastPath)

        // Search for the node with matching URL
        if let node = findNode(url: lastURL) {
            selectNode(node)
            Logger.shared.info("Restored last selected file: \(node.name)")
        }
    }

    /// Find a node by URL
    func findNode(url: URL) -> FileNode? {
        for rootNode in fileNodes {
            if let found = rootNode.findNode(url: url) {
                return found
            }
        }
        return nil
    }

    /// Load previously saved site
    private func loadSavedSite() async {
        guard let url = fileSystemService.loadBookmark() else {
            return
        }

        await loadSite(from: url)
    }

    /// Close current site
    func closeSite() {
        // Stop Hugo server if running
        Task {
            await hugoServerService.stop()
        }
        hugoServerStatus = .stopped
        hugoBuildErrors = []
        hugoServerURL = nil
        useLivePreview = false

        if let url = site?.rootURL {
            fileSystemService.stopAccessing(url: url)
            // Clear theme CSS cache for this site
            Task {
                await ThemeCSSService.shared.clearCache(for: url)
            }
        }
        site = nil
        fileNodes = []
        nodeByID.removeAll()
        invalidateFilterCache()
        // Single write through the canonical path: this drives applySelectionChange ->
        // performLeadChange(nil), which clears selectedNode/selectedFileID itself.
        selectedFileIDs = []
        fileCacheManager.clearAll()           // Clear all per-file markdown edits
        specializedFileManager.clearAll()     // Clear Hugo config, data files, templates, archetypes
        recentFiles = []
        contentCacheOrder = []           // Clear loaded content tracking
        modifiedFileIDs = []
        recentlySavedFileIDs = [:]
        loadedStatusFolderIDs = []
        navigationHistory = []
        navigationHistoryCursor = -1
    }

    // MARK: - Node Lookup

    /// Build flat lookup table for O(1) node access by ID
    private func buildNodeLookupTable() {
        nodeByID.removeAll()
        indexNodesRecursively(fileNodes)
    }

    /// Recursively index all nodes into the lookup table
    private func indexNodesRecursively(_ nodes: [FileNode]) {
        for node in nodes {
            nodeByID[node.id] = node
            if node.isDirectory {
                indexNodesRecursively(node.children)
            }
        }
    }

    /// Find a node by ID using O(1) lookup, falling back to tree traversal.
    /// The fallback covers nodes added after the lookup table was built
    /// (new files, duplicates) so Save All and status checks never skip them.
    func findNode(id: UUID) -> FileNode? {
        if let node = nodeByID[id] {
            return node
        }
        if let node = FileNode.findNode(id: id, in: fileNodes) {
            nodeByID[id] = node
            return node
        }
        return nil
    }

    /// Register a node created after the initial site scan in the lookup table
    private func registerNode(_ node: FileNode) {
        nodeByID[node.id] = node
    }

    /// Remove a node (and its subtree) from the lookup table
    private func unregisterNode(_ node: FileNode) {
        nodeByID.removeValue(forKey: node.id)
        for child in node.children {
            unregisterNode(child)
        }
    }

    // MARK: - File Row View Models

    /// Generate a cached view model for a file row
    func rowViewModel(for node: FileNode) -> FileRowViewModel {
        return FileRowViewModel(node: node, siteViewModel: self)
    }

    // MARK: - File Selection

    /// Thin pass-through into the canonical `selectedFileIDs` write path - its `didSet`
    /// does lead derivation, page-bundle redirect, no-op detection and side effects.
    func selectNode(_ node: FileNode?) {
        selectedFileIDs = node.map { [$0.id] } ?? []
    }

    /// Expand all parent folders to make a node visible in the sidebar
    func expandToNode(_ node: FileNode) {
        // Walk up the parent chain and expand each folder
        var current = node.parent
        while let parent = current {
            if !parent.isExpanded {
                parent.isExpanded = true
            }
            current = parent.parent
        }
    }

    /// Select a node and expand its parent folders to make it visible
    func selectAndRevealNode(_ node: FileNode) {
        expandToNode(node)
        selectNode(node)
    }

    /// Add a file to the recent files list
    func addRecentFile(_ node: FileNode) {
        // Remove if already in list (to move to front)
        recentFiles.removeAll { $0.id == node.id }

        // Add to front
        recentFiles.insert(node, at: 0)

        // Trim to max size
        if recentFiles.count > maxRecentFiles {
            recentFiles = Array(recentFiles.prefix(maxRecentFiles))
        }
    }

    /// Toggle Inspector panel
    func toggleInspector() {
        AppSettings.shared.isInspectorVisible.toggle()
    }

    /// Toggle Focus Mode
    func toggleFocusMode() {
        // When entering focus mode, ensure content is initialized from the file
        if !isFocusModeActive {
            if let contentFile = selectedNode?.contentFile {
                // Initialize editing content from file if empty
                if currentEditingContent.isEmpty {
                    currentEditingContent = contentFile.markdownContent
                }
            }
        }
        isFocusModeActive.toggle()
    }

    /// Exit Focus Mode
    func exitFocusMode() {
        isFocusModeActive = false
    }

    // MARK: - File Status Management

    /// Transition-guarded: `handleContentChange` calls this per keystroke, and an
    /// unconditional `Set.insert` fires Observation even when already present.
    func markFileModified(_ nodeID: UUID) {
        guard !modifiedFileIDs.contains(nodeID) else { return }
        modifiedFileIDs.insert(nodeID)
    }

    /// Clear the modified state for a file. Transition-guarded - see markFileModified.
    func clearFileModified(_ nodeID: UUID) {
        guard modifiedFileIDs.contains(nodeID) else { return }
        modifiedFileIDs.remove(nodeID)
    }

    /// Mark a file as recently saved (shows green checkmark that fades)
    func markFileSaved(_ nodeID: UUID) {
        // Clear modified state - routed through the guarded path (see markFileModified)
        // rather than a direct Set.remove, so a redundant save (nothing was modified)
        // doesn't fire modifiedFileIDs' Observation either.
        clearFileModified(nodeID)

        // Add to recently saved
        recentlySavedFileIDs[nodeID] = Date()

        // Schedule removal after duration
        Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: .seconds(self.savedIndicatorDuration))
            // Only remove if the timestamp hasn't been updated
            if let savedDate = self.recentlySavedFileIDs[nodeID],
               Date().timeIntervalSince(savedDate) >= self.savedIndicatorDuration {
                self.recentlySavedFileIDs.removeValue(forKey: nodeID)
            }
        }
    }

    /// Check if a file has unsaved changes
    /// Checks modifiedFileIDs for markdown, and model state for config/data files/templates
    func isFileModified(_ nodeID: UUID) -> Bool {
        // Check markdown/text files via modifiedFileIDs
        if modifiedFileIDs.contains(nodeID) {
            return true
        }

        // Check config, data files, templates, and archetypes via SpecializedFileManager
        if let node = findNode(id: nodeID) {
            if specializedFileManager.hasUnsavedChanges(for: node.url) {
                return true
            }
        }

        return false
    }

    /// Check if a file was recently saved
    func isFileRecentlySaved(_ nodeID: UUID) -> Bool {
        guard let savedDate = recentlySavedFileIDs[nodeID] else {
            return false
        }
        return Date().timeIntervalSince(savedDate) < savedIndicatorDuration
    }

    /// Check if any files have unsaved changes
    var hasUnsavedChanges: Bool {
        // Check markdown/text files
        if !modifiedFileIDs.isEmpty {
            return true
        }
        // Check specialized files (Hugo config, data files, templates, archetypes)
        if specializedFileManager.hasUnsavedChanges {
            return true
        }
        return false
    }

    /// Save all files with unsaved changes
    func saveAllModifiedFiles() async {
        // Save markdown and text files tracked in modifiedFileIDs
        let modifiedIDs = modifiedFileIDs
        for nodeID in modifiedIDs {
            guard let node = findNode(id: nodeID) else { continue }

            if node.isMarkdownFile, let contentFile = node.contentFile {
                do {
                    // Unsaved edits live in the per-file cache, not on contentFile
                    // (contentFile.markdownContent only updates on explicit save) -
                    // sync before writing or Save-and-Quit persists stale content
                    if let editedContent = fileCacheManager.getContent(for: nodeID) {
                        contentFile.markdownContent = editedContent
                    }
                    // Extract url/content AFTER the sync above and BEFORE the await -
                    // reading fullContent earlier silently drops the just-synced edit.
                    let url = contentFile.url
                    let content = contentFile.fullContent
                    try await fileSystemService.saveContentFile(url: url, content: content)
                    clearFileModified(nodeID)
                    Logger.shared.info("Saved: \(node.name)")
                } catch {
                    Logger.shared.error("Failed to save \(node.name)", error: error)
                }
            } else if let textFile = node.textFile {
                do {
                    try await fileSystemService.writeFile(to: textFile.url, content: textFile.content)
                    textFile.markAsSaved()
                    clearFileModified(nodeID)
                    Logger.shared.info("Saved: \(node.name)")
                } catch {
                    Logger.shared.error("Failed to save \(node.name)", error: error)
                }
            }
        }

        // Save specialized files (Hugo config, data files, templates, archetypes)
        await specializedFileManager.saveAll()
    }

    // MARK: - Status Metadata Loading (Lazy)

    /// Load status metadata for markdown files in a folder when it's expanded
    /// This enables showing Draft/Scheduled/Expired badges before files are opened
    func onFolderExpanded(_ folder: FileNode) {
        // Skip if already loaded
        guard !loadedStatusFolderIDs.contains(folder.id) else { return }

        // Collect markdown file URLs that don't have status yet
        // Exclude archetype files - they're templates and shouldn't show status badges
        // Also, they may contain unquoted Hugo template syntax that crashes YAML parser
        let markdownChildren = folder.children.filter {
            $0.isMarkdownFile && $0.statusMetadata == nil && $0.contentFile == nil && $0.hugoRole != .archetypes
        }

        guard !markdownChildren.isEmpty else {
            loadedStatusFolderIDs.insert(folder.id)
            return
        }

        let urls = markdownChildren.map { $0.url }

        // Use userInitiated priority for responsive folder expansion
        Task(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            // Load all metadata in parallel (on background threads)
            let metadataMap = await self.fileSystemService.loadStatusMetadata(for: urls)

            // Update all nodes in a batch - since we're on @MainActor,
            // SwiftUI will coalesce these updates into a single render pass
            for child in markdownChildren {
                if let metadata = metadataMap[child.url] {
                    child.statusMetadata = metadata
                }
            }
            self.loadedStatusFolderIDs.insert(folder.id)
        }
    }

    /// Load content for a markdown file node
    private func loadFileContent(for node: FileNode) async {
        do {
            let file = try await fileSystemService.readContentFile(at: node.url)
            node.contentFile = file

            // Sync status metadata from full content (more accurate than lightweight parse)
            node.statusMetadata = FileStatusMetadata(from: file.frontmatter)

            // Track in LRU cache and evict old entries
            updateContentCache(accessedNodeID: node.id)
        } catch {
            errorMessage = "Failed to load file: \(error.localizedDescription)"
            Logger.shared.error("Error loading file content", error: error)
        }
    }

    /// Load content for a text file node (non-markdown)
    private func loadTextFileContent(for node: FileNode) async {
        do {
            // Snapshot the Sendable URL rather than capturing the non-Sendable `node`.
            // `@concurrent` can't go on this method: it stays @MainActor to mutate `node`.
            let url = node.url
            let content = try await readFileContentsOffActor(at: url)

            let attributes = try FileManager.default.attributesOfItem(atPath: node.url.path)
            let modificationDate = attributes[.modificationDate] as? Date ?? Date()

            let textFile = TextFile(
                url: node.url,
                content: content,
                lastModified: modificationDate
            )
            node.textFile = textFile

            // Track in LRU cache and evict old entries
            updateContentCache(accessedNodeID: node.id)
        } catch {
            errorMessage = "Failed to load file: \(error.localizedDescription)"
            Logger.shared.error("Error loading text file content", error: error)
        }
    }

    /// Update LRU cache when a file is accessed, evicting old entries if over limit
    private func updateContentCache(accessedNodeID: UUID) {
        // Move to front of cache order (remove if exists, then insert at front)
        contentCacheOrder.removeAll { $0 == accessedNodeID }
        contentCacheOrder.insert(accessedNodeID, at: 0)

        var overflow = contentCacheOrder.count - maxCachedContentFiles
        guard overflow > 0 else { return }

        // Walk from the least-recently-used end, skipping protected entries.
        // Single pass guarantees termination - re-inserting protected entries and
        // looping would spin forever on the main thread once the tail of the list
        // is a selected/modified file.
        var evicted: [UUID] = []
        for candidate in contentCacheOrder.reversed() {
            guard overflow > 0 else { break }
            if candidate == selectedNode?.id || modifiedFileIDs.contains(candidate) { continue }
            evicted.append(candidate)
            overflow -= 1
        }

        guard !evicted.isEmpty else { return }

        let evictedSet = Set(evicted)
        contentCacheOrder.removeAll { evictedSet.contains($0) }
        for id in evicted {
            if let node = findNode(id: id) {
                node.contentFile = nil
                node.textFile = nil
                Logger.shared.debug("Cache eviction: released content for \(node.name)")
            }
        }
    }

    // MARK: - File Operations

    /// Save edited content to file
    func saveFile(node: FileNode, content: String) async -> Bool {
        guard let contentFile = node.contentFile else {
            errorMessage = "No content file to save"
            return false
        }

        do {
            // Write to disk
            try await fileSystemService.writeFile(to: node.url, content: content)

            // Update the content file model
            contentFile.markdownContent = content
            contentFile.lastModified = Date()

            Logger.shared.info("Saved file: \(node.name)")
            return true
        } catch {
            errorMessage = "Failed to save file: \(error.localizedDescription)"
            Logger.shared.error("Error saving file", error: error)
            return false
        }
    }

    // MARK: - Hugo Config Management

    /// Load Hugo configuration from a config file URL
    func loadHugoConfig(from url: URL) async {
        do {
            try await specializedFileManager.loadHugoConfig(from: url)
        } catch {
            errorMessage = "Failed to load config: \(error.localizedDescription)"
        }
    }

    /// Save the current Hugo configuration (from form fields)
    func saveHugoConfig() async {
        do {
            try await specializedFileManager.saveHugoConfig()
        } catch {
            errorMessage = "Failed to save config: \(error.localizedDescription)"
            Logger.shared.error("Error saving Hugo config", error: error)
        }
    }

    /// Save the current Hugo configuration directly from rawContent (for raw editor mode)
    func saveHugoConfigRaw() async {
        do {
            try await specializedFileManager.saveHugoConfigRaw()
        } catch {
            errorMessage = "Failed to save config: \(error.localizedDescription)"
            Logger.shared.error("Error saving Hugo config", error: error)
        }
    }

    // MARK: - Data File Management

    /// Load a data file from URL (for files in data/ directory)
    func loadDataFile(from url: URL) async {
        do {
            try await specializedFileManager.loadDataFile(from: url)
        } catch {
            errorMessage = "Failed to load data file: \(error.localizedDescription)"
        }
    }

    /// Save the current data file
    func saveDataFile() async {
        guard let dataFile = currentDataFile else {
            errorMessage = "No data file to save"
            return
        }

        do {
            try await specializedFileManager.saveDataFile(dataFile)
        } catch {
            errorMessage = "Failed to save data file: \(error.localizedDescription)"
            Logger.shared.error("Error saving data file", error: error)
        }
    }

    // MARK: - Template Management

    /// Load a template file from URL (for files in layouts/ or themes/ directories)
    func loadTemplate(from url: URL) async {
        do {
            try await specializedFileManager.loadTemplate(from: url)
        } catch {
            errorMessage = "Failed to load template: \(error.localizedDescription)"
        }
    }

    /// Save the current template
    func saveTemplate() async {
        guard let template = currentTemplate else {
            errorMessage = "No template to save"
            return
        }

        do {
            try await specializedFileManager.saveTemplate(template)
        } catch {
            errorMessage = "Failed to save template: \(error.localizedDescription)"
            Logger.shared.error("Error saving template", error: error)
        }
    }

    // MARK: - Archetype Management

    /// Load an archetype file from URL (for files in archetypes/ directory)
    func loadArchetype(from url: URL) async {
        do {
            try await specializedFileManager.loadArchetype(from: url)
        } catch {
            errorMessage = "Failed to load archetype: \(error.localizedDescription)"
        }
    }

    /// Save the current archetype
    func saveArchetype() async {
        guard let archetype = currentArchetype else {
            errorMessage = "No archetype to save"
            return
        }

        do {
            try await specializedFileManager.saveArchetype(archetype)
        } catch {
            errorMessage = "Failed to save archetype: \(error.localizedDescription)"
            Logger.shared.error("Error saving archetype", error: error)
        }
    }

    /// Create a new markdown file inside the given folder node
    func createMarkdownFile(in folder: FileNode) async {
        guard folder.isDirectory else { return }

        do {
            // Ask file operations service to create a new markdown file
            guard let siteRoot = site?.rootURL else { return }
            let newFileURL = try await fileOperationsService.createMarkdownFile(in: folder.url, siteRoot: siteRoot)

            // Build a FileNode for the new file and insert it into the tree
            let newNode = FileNode(url: newFileURL, isDirectory: false, isPageBundle: false)
            folder.addChild(newNode)
            registerNode(newNode)

            // Invalidate filter cache since tree changed
            invalidateFilterCache()

            // Select the newly created file
            selectNode(newNode)
        } catch {
            errorMessage = "Failed to create file: \(error.localizedDescription)"
            Logger.shared.error("Error creating markdown file", error: error)
        }
    }

    /// Dispatches a sidebar drop to a same-site move or a copy/import, based on whether
    /// `sourceURL` is already inside the site root. Resolves `folder` to its canonical
    /// instance once here (it may be an ephemeral filtered-search copy).
    func handleDroppedFile(from sourceURL: URL, into folder: FileNode) async {
        guard let canonicalFolder = findNode(url: folder.url), canonicalFolder.isDirectory else { return }

        if isURL(sourceURL, withinSite: site?.rootURL), let sourceNode = findNode(url: sourceURL) {
            await moveNode(from: sourceNode, to: canonicalFolder)
        } else {
            await importDroppedFile(from: sourceURL, into: canonicalFolder)
        }
    }

    /// True if `url` is inside `siteRoot`. A branch predicate, not a security gate - the
    /// move/import paths each run their own validation once a branch is chosen.
    private func isURL(_ url: URL, withinSite siteRoot: URL?) -> Bool {
        guard let siteRoot else { return false }
        let path = url.standardized.path
        let rootPath = siteRoot.standardized.path
        if path == rootPath { return true }
        let rootWithSeparator = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return path.hasPrefix(rootWithSeparator)
    }

    /// Copies a dropped file in and inserts a node directly, rather than a full `reloadSite()`.
    /// Re-resolves `folder` by URL first: under an active search it may be an ephemeral
    /// copy from `filterNodesRecursively` (fresh UUID) that dies on the next recompute.
    func importDroppedFile(from sourceURL: URL, into folder: FileNode) async {
        guard let siteRoot = site?.rootURL else { return }
        guard let canonicalFolder = findNode(url: folder.url), canonicalFolder.isDirectory else { return }

        do {
            let destURL = try fileSystemService.importFile(from: sourceURL, into: canonicalFolder.url, siteRoot: siteRoot)

            let newNode = FileNode(url: destURL, isDirectory: false, isPageBundle: false)
            canonicalFolder.addChild(newNode)
            registerNode(newNode)

            // Invalidate filter cache since tree changed
            invalidateFilterCache()

            selectNode(newNode)
        } catch {
            errorMessage = "Failed to import \(sourceURL.lastPathComponent): \(error.localizedDescription)"
            Logger.shared.error("Error importing dropped file", error: error)
        }
    }

    /// Reload current site
    func reloadSite() async {
        guard let site = site else { return }
        // Clear status metadata cache so it reloads fresh
        loadedStatusFolderIDs.removeAll()
        // FileNode UUIDs regenerate on every rescan, so every navigation-history
        // entry is about to become unresolvable at once - reset outright rather
        // than letting Back/Forward discover that one dead entry at a time.
        navigationHistory = []
        navigationHistoryCursor = -1
        await loadSite(from: site.rootURL)
    }

    /// Reload a specific file from disk
    func reloadFile(node: FileNode) async {
        do {
            // Read the file from disk
            let freshContent = try await fileSystemService.readContentFile(at: node.url)

            // Update the node's content file
            node.contentFile = freshContent

            // Update the edited content to match fresh disk content
            fileCacheManager.setContent(freshContent.markdownContent, for: node.id)

            // If this is the currently selected node, trigger a UI update
            if selectedNode?.id == node.id {
                selectedNode = node
            }
        } catch {
            errorMessage = "Failed to reload file: \(error.localizedDescription)"
            Logger.shared.error("Error reloading file", error: error)
        }
    }

    // MARK: - Context Menu File Operations

    /// Registers `handler` as the next undo action and names it for the Edit menu. No-ops
    /// when `undoManager` is nil (tests, or no window yet).
    ///
    /// Callers MUST register the opposite action synchronously, inside the handler,
    /// before spawning any async work - `UndoManager` routes to the undo/redo stack by
    /// checking `isUndoing`/`isRedoing` at call time. See Docs/UNDO-REDO-NOTES.md.
    private func registerFileOpUndo(_ actionName: String, _ handler: @escaping (SiteViewModel) -> Void) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self, handler: handler)
        undoManager.setActionName(actionName)
    }

    /// FIFO tail of every inverse-operation Task the undo/redo chains spawn. `UndoManager`
    /// re-enables Cmd-Z the instant a handler returns, so mashing undo would otherwise run
    /// concurrent Tasks over the same tree state. See Docs/UNDO-REDO-NOTES.md.
    private var lastFileOpUndoTask: Task<Void, Never>?

    /// Enqueues `work` behind whatever's currently in flight on
    /// `lastFileOpUndoTask` (see its doc comment). Every `Task` spawned by
    /// the four undo/redo chains below must go through this, not a bare
    /// `Task { }`, or rapid undo/redo re-entrancy can run two inverse
    /// operations concurrently.
    private func enqueueFileOpUndoWork(_ work: @escaping () async -> Void) {
        let previous = lastFileOpUndoTask
        lastFileOpUndoTask = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    /// Registers the Rename undo/redo pair. `oldName`/`newName` are fixed at the first
    /// rename; each firing re-registers the swapped pair before spawning its Task
    /// (see `registerFileOpUndo` for why that ordering is mandatory).
    private func registerRenameUndo(nodeID: UUID, from oldName: String, to newName: String) {
        registerFileOpUndo("Rename") { target in
            target.registerRenameUndo(nodeID: nodeID, from: newName, to: oldName)
            // Enqueued (not a bare Task) - see `enqueueFileOpUndoWork`'s doc
            // comment: rapid undo/redo must not run two renames concurrently.
            // `findNode` is read inside the closure, so it resolves the
            // node's state as of this step's actual turn in the FIFO queue.
            target.enqueueFileOpUndoWork {
                guard let node = target.findNode(id: nodeID) else {
                    target.errorMessage = "Can't undo rename: the file no longer exists."
                    return
                }
                await target.renameFile(node: node, to: oldName, registerUndo: false)
            }
        }
    }

    /// Rename a file node. `registerUndo` is false when this call IS the
    /// inverse of a previous rename (see `registerRenameUndo`) - the inverse
    /// registration already happened synchronously before this async call
    /// was even started, so registering again here would be a duplicate.
    func renameFile(node: FileNode, to newName: String, registerUndo: Bool = true) async {
        do {
            guard let siteRoot = site?.rootURL else { return }

            // Captured before any mutation below - the undo inverse renames
            // back to this (victor-und). `node.name` is `url.lastPathComponent`,
            // exactly the form `renameFile`'s `to:` parameter expects.
            let oldName = node.name

            // Cancel pending debounced saves for this node (and descendants, for a directory)
            // BEFORE touching disk, else an in-flight save recreates the file at the old path.
            // `cancelDebounce` also awaits, so no write can still be mid-flight after this.
            for nodeID in [node.id] + allDescendantNodeIDs(of: node) {
                await autoSaveService.cancelDebounce(nodeID: nodeID)
            }

            let newURL = try await fileOperationsService.renameFile(at: node.url, to: newName, siteRoot: siteRoot)

            // Update the node's URL and every model object that mirrors it.
            node.url = newURL
            node.contentFile?.url = newURL
            node.textFile?.url = newURL

            // `FileManager.moveItem` already relocated the whole subtree on disk
            // for a directory rename, but each descendant FileNode's in-memory
            // `url` still points at the OLD parent path - rebuild them all by
            // prefix replacement.
            if node.isDirectory {
                updateDescendantURLs(of: node, newParentURL: newURL)
            }

            // Keep sibling sort order correct - the name (and therefore sort
            // position) may have changed.
            if let parent = node.parent {
                parent.sortChildren()
            } else {
                fileNodes.sort { lhs, rhs in
                    if lhs.isDirectory != rhs.isDirectory {
                        return lhs.isDirectory
                    }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }
            // Name changed, which affects search matching - invalidate regardless
            // of where the node lived (matches duplicateFile/moveToTrash).
            invalidateFilterCache()

            // No selection force-poke: `node` is the same @Observable instance throughout,
            // so mutating `url` in place already invalidates every view reading it.

            if registerUndo {
                registerRenameUndo(nodeID: node.id, from: oldName, to: newName)
            }
        } catch {
            errorMessage = "Failed to rename file: \(error.localizedDescription)"
            Logger.shared.error("Error renaming file", error: error)
        }
    }

    /// Every descendant node ID under `node`, for cancelling pending auto-saves
    /// before a directory rename/move (see `renameFile`/`moveNode`) - IDs, not
    /// URLs, since `AutoSaveService`'s debounce registry is keyed by FileNode.id
    /// (stable across the very rename/move this is cancelling for).
    private func allDescendantNodeIDs(of node: FileNode) -> [UUID] {
        node.children.flatMap { [$0.id] + allDescendantNodeIDs(of: $0) }
    }

    /// Rebuild every descendant's `url` (and its `contentFile`/`textFile` mirror)
    /// after a directory rename/move, by replacing the parent-path prefix.
    private func updateDescendantURLs(of node: FileNode, newParentURL: URL) {
        for child in node.children {
            // Explicit isDirectory - avoids a per-child filesystem stat and
            // keeps directory URLs slash-consistent (see FileSystemService.renameFile).
            let childNewURL = newParentURL.appendingPathComponent(
                child.url.lastPathComponent, isDirectory: child.isDirectory)
            child.url = childNewURL
            child.contentFile?.url = childNewURL
            child.textFile?.url = childNewURL
            if child.isDirectory {
                updateDescendantURLs(of: child, newParentURL: childNewURL)
            }
        }
    }

    /// Moves a node within the site tree - the drag-to-move counterpart of the copy/import
    /// path. Cancels pending auto-saves, moves on disk, updates the node's (and every
    /// descendant's) URL, reparents in the tree, invalidates the filter cache.
    /// - Parameters:
    ///   - node: must already be the canonical tree instance (resolve via `findNode`)
    ///   - targetFolder: the destination folder node
    ///   - registerUndo: false when this call is itself the inverse of a previous move
    func moveNode(from node: FileNode, to targetFolder: FileNode, registerUndo: Bool = true) async {
        guard targetFolder.isDirectory else { return }
        guard let siteRoot = site?.rootURL else { return }

        // No-op when dropped back onto its own current parent, or onto
        // itself - nothing to do, not an error.
        if node.id == targetFolder.id || node.parent?.id == targetFolder.id {
            return
        }

        // Refuse moving a folder into its own descendant - FileManager.moveItem
        // would either fail outright or (worse) move the directory inside
        // itself, corrupting the in-memory tree on top of it.
        if node.isDirectory, isDescendant(targetFolder, of: node) {
            errorMessage = "Can't move '\(node.name)' into its own subfolder."
            return
        }

        // Cancel any pending debounced auto-save for this node - and, for a
        // directory move, every descendant file - BEFORE touching disk. Same
        // ordering rationale and mechanism as renameFile (see its doc comment):
        // `cancelDebounce(nodeID:)` cancels AND AWAITS the real registered
        // debounce Task, so a save already in flight can't land after the move.
        for nodeID in [node.id] + allDescendantNodeIDs(of: node) {
            await autoSaveService.cancelDebounce(nodeID: nodeID)
        }

        // Captured before reparenting below - the undo inverse moves back
        // here (victor-und). `nil` means `node` was top-level (no parent
        // FileNode to move back into - see the inverse closure below).
        let oldParentID = node.parent?.id

        do {
            let newURL = try await fileOperationsService.moveFile(at: node.url, to: targetFolder.url, siteRoot: siteRoot)

            // Update the node's URL and every model object that mirrors it -
            // same pattern as renameFile.
            node.url = newURL
            node.contentFile?.url = newURL
            node.textFile?.url = newURL

            if node.isDirectory {
                updateDescendantURLs(of: node, newParentURL: newURL)
            }

            // Reparent in the in-memory tree. Remove from the old parent
            // FIRST - addChild only appends to the new parent, it doesn't
            // remove from any prior parent's children array.
            if let oldParent = node.parent {
                oldParent.children.removeAll { $0.id == node.id }
            } else {
                fileNodes.removeAll { $0.id == node.id }
            }
            targetFolder.addChild(node)   // sets node.parent, appends, sortChildren()

            invalidateFilterCache()

            // No selection or cache fixup needed: both are keyed by `id`, which a move
            // doesn't change, and `node` is the same instance throughout.

            // victor-und: `oldParentID` being nil means `node` was top-level
            // (no FileNode represents "the site root" for `moveNode` to
            // target later), so there's nothing to register - that specific
            // move just isn't undoable, rather than registering something
            // that would always fail at undo time.
            if registerUndo, let oldParentID {
                registerMoveUndo(nodeID: node.id, from: oldParentID, to: targetFolder.id)
            }
        } catch {
            errorMessage = "Failed to move \(node.name): \(error.localizedDescription)"
            Logger.shared.error("Error moving file", error: error)
        }
    }

    /// Registers the Move undo/redo pair. Parent IDs are fixed at the first move but
    /// re-resolved at fire time, so a since-deleted folder degrades to `errorMessage`.
    /// Each firing re-registers the swapped pair before spawning its Task.
    private func registerMoveUndo(nodeID: UUID, from oldParentID: UUID, to newParentID: UUID) {
        registerFileOpUndo("Move") { target in
            target.registerMoveUndo(nodeID: nodeID, from: newParentID, to: oldParentID)
            // Enqueued (not a bare Task) - see `enqueueFileOpUndoWork`'s doc
            // comment: rapid undo/redo must not run two moves concurrently.
            // Both `findNode` calls are read inside the closure, so they
            // resolve state as of this step's actual turn in the FIFO queue.
            target.enqueueFileOpUndoWork {
                guard let node = target.findNode(id: nodeID) else {
                    target.errorMessage = "Can't undo move: the file no longer exists."
                    return
                }
                guard let targetFolder = target.findNode(id: oldParentID) else {
                    target.errorMessage = "Can't undo move: the original folder no longer exists."
                    return
                }
                await target.moveNode(from: node, to: targetFolder, registerUndo: false)
            }
        }
    }

    /// True if `candidate` is `ancestor` itself or nested anywhere under it -
    /// used by `moveNode` to refuse moving a folder into its own descendant.
    private func isDescendant(_ candidate: FileNode, of ancestor: FileNode) -> Bool {
        var current: FileNode? = candidate
        while let node = current {
            if node.id == ancestor.id { return true }
            current = node.parent
        }
        return false
    }

    /// Duplicate a file node. `registerUndo: false` exists for signature symmetry with the
    /// other three ops - undoing a duplicate trashes the copy rather than re-duplicating.
    func duplicateFile(node: FileNode, registerUndo: Bool = true) async {
        do {
            let newURL = try await fileOperationsService.duplicateFile(at: node.url)

            // Create a new FileNode for the duplicate
            let newNode = FileNode(url: newURL, isDirectory: node.isDirectory, isPageBundle: node.isPageBundle)
            registerNode(newNode)

            // Add to parent's children
            if let parent = node.parent {
                parent.addChild(newNode)
            } else {
                // Top-level file
                fileNodes.append(newNode)
                fileNodes.sort { lhs, rhs in
                    if lhs.isDirectory != rhs.isDirectory {
                        return lhs.isDirectory
                    }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }

            // Invalidate filter cache since tree changed
            invalidateFilterCache()

            // Select the new file
            selectNode(newNode)

            // Inverse is trashing the duplicate (recoverable), reusing the trash<->restore
            // chain machinery with its own box and its own action name.
            if registerUndo {
                let box = TrashRecordBox(state: .inTree([newNode]))
                registerTrashChainUndo(box: box, actionName: "Duplicate")
            }
        } catch {
            errorMessage = "Failed to duplicate file: \(error.localizedDescription)"
            Logger.shared.error("Error duplicating file", error: error)
        }
    }

    /// Move nodes to the trash in one gesture. Prunes descendants whose ancestor is also
    /// selected (trashing the ancestor already removes them). Sequential, since tree
    /// mutation is shared @Observable state; one failure doesn't abort the batch,
    /// matching Finder. `registerUndo: false` when this is a re-trash step inside a chain.
    /// See Docs/SELECTION-MODEL-MEMO.md §5.
    func moveToTrash(nodes: [FileNode], registerUndo: Bool = true) async {
        let pruned = pruneDescendants(of: nodes)
        guard !pruned.isEmpty else { return }

        let result = await performTrash(nodes: pruned)

        // Selection/editor fixup, generalized from the single-node version -
        // check against the ORIGINAL untrimmed `nodes` list (not just
        // `pruned`), since a descendant pruned away is still gone from disk
        // and must not remain "selected" even though moveToTrash was never
        // called for it directly.
        let trashedIDs = Set(nodes.map(\.id))
        if let selectedID = selectedNode?.id, trashedIDs.contains(selectedID) {
            for id in trashedIDs {
                fileCacheManager.clearContent(for: id)  // Clear edited content for every trashed file
            }
            // Routes through the same assignment as any other Set mutation so
            // the lead-fallback logic (applySelectionChange) runs uniformly -
            // no hand-rolled special case for the batch-trash path.
            selectedFileIDs = selectedFileIDs.subtracting(trashedIDs)
        }

        // victor-und: single "Move to Trash" undo action for the whole batch
        // (no "Move 3 Items to Trash" naming needed per the ticket).
        // `result.records` is the undo-capable subset of `pruned` (a record
        // needs a non-nil `trashedURL` - see `performTrash`'s doc comment).
        if registerUndo, !result.records.isEmpty {
            let box = TrashRecordBox(state: .trashed(result.records))
            registerTrashChainUndo(box: box, actionName: "Move to Trash")
        }

        if let firstError = result.errors.first {
            errorMessage = "Failed to move to trash: \(firstError.localizedDescription)"
        }
    }

    /// Single-node convenience wrapper, kept so the 15+ existing single-target
    /// call sites (SelectionContextMenu, etc.) don't need individual updates.
    func moveToTrash(node: FileNode, registerUndo: Bool = true) async {
        await moveToTrash(nodes: [node], registerUndo: registerUndo)
    }

    /// Snapshot of a trashed node, capturable only once `FileManager.trashItem` has returned
    /// its `trashedURL`. Retains the `FileNode` directly - nothing replaces it between
    /// trash and restore. `originalParentID` is re-resolved on restore, not `node.parent`.
    private struct TrashRecord {
        let node: FileNode
        let originalURL: URL
        let originalParentID: UUID?
        let trashedURL: URL
    }

    /// Which side of a trash<->restore chain a `TrashRecordBox` currently holds: `.inTree`
    /// means the next step trashes, `.trashed` means it restores.
    private enum TrashChainState {
        case inTree([FileNode])
        case trashed([TrashRecord])
    }

    /// Threads state through one trash<->restore chain. A class so every handler in the
    /// chain shares one box: each re-trash produces new trashed URLs, so the next step's
    /// state is only known after the current step's async work finishes - yet the next
    /// step must be *registered* before that work starts.
    ///
    /// `state` must be read inside the closure given to `enqueueFileOpUndoWork`, never
    /// synchronously at handler-fire time. See Docs/UNDO-REDO-NOTES.md.
    private final class TrashRecordBox {
        var state: TrashChainState
        init(state: TrashChainState) { self.state = state }
    }

    /// Trashes `nodes` (already pruned by the caller) and returns records for those that
    /// both succeeded and got a usable `trashedURL` back - the undo-capable subset.
    /// Pure tree/disk mutation: no undo registration, no selection fixup.
    private func performTrash(nodes: [FileNode]) async -> (records: [TrashRecord], successCount: Int, errors: [Error]) {
        var successCount = 0
        var records: [TrashRecord] = []
        var errors: [Error] = []

        for node in nodes {
            do {
                let originalURL = node.url
                let originalParentID = node.parent?.id
                let trashedURL = try await fileOperationsService.moveToTrash(at: node.url)

                unregisterNode(node)
                if let parent = node.parent {
                    parent.children.removeAll { $0.id == node.id }
                } else {
                    fileNodes.removeAll { $0.id == node.id }
                }

                successCount += 1
                if let trashedURL {
                    records.append(TrashRecord(
                        node: node, originalURL: originalURL, originalParentID: originalParentID, trashedURL: trashedURL))
                }
            } catch {
                errors.append(error)
                Logger.shared.error("Error moving to trash", error: error)
            }
        }

        if successCount > 0 {
            invalidateFilterCache()
        }

        return (records, successCount, errors)
    }

    /// Re-registers `node` and every descendant in `nodeByID` - the inverse
    /// of `unregisterNode`'s recursive removal. Needed by `performRestore`
    /// when restoring a trashed folder: trashing it unregistered the whole
    /// subtree (`unregisterNode` recurses into `children`), so restoring it
    /// must re-register the whole subtree too, not just the top node.
    private func registerNodeRecursively(_ node: FileNode) {
        registerNode(node)
        for child in node.children {
            registerNodeRecursively(child)
        }
    }

    /// Moves each record back from the Trash and re-inserts its node under its original
    /// parent, re-resolved by ID (a missing parent skips that record and reports via
    /// `errorMessage`). Deliberately doesn't touch selection, matching Finder.
    private func performRestore(records: [TrashRecord]) async -> (restored: [FileNode], errors: [Error]) {
        var restored: [FileNode] = []
        var errors: [Error] = []

        for record in records {
            do {
                try FileManager.default.moveItem(at: record.trashedURL, to: record.originalURL)

                record.node.url = record.originalURL
                record.node.contentFile?.url = record.originalURL
                record.node.textFile?.url = record.originalURL
                if record.node.isDirectory {
                    updateDescendantURLs(of: record.node, newParentURL: record.originalURL)
                }

                if let parentID = record.originalParentID {
                    guard let parent = findNode(id: parentID) else {
                        errors.append(FileError.fileNotFound)
                        continue
                    }
                    parent.addChild(record.node)   // sets node.parent, appends, sortChildren()
                } else {
                    fileNodes.append(record.node)
                    fileNodes.sort { lhs, rhs in
                        if lhs.isDirectory != rhs.isDirectory {
                            return lhs.isDirectory
                        }
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                }
                registerNodeRecursively(record.node)
                restored.append(record.node)
            } catch {
                errors.append(error)
                Logger.shared.error("Error restoring from trash", error: error)
            }
        }

        if !restored.isEmpty {
            invalidateFilterCache()
        }

        return (restored, errors)
    }

    /// Registers the undo/redo pair for one trash<->restore chain, named `actionName` on
    /// both sides so a chain built for Duplicate keeps reading "Duplicate".
    ///
    /// Self-recursive: `box.state` is the single source of truth for direction. Each
    /// firing re-registers this function against the same box synchronously, before
    /// enqueueing the async work. See Docs/UNDO-REDO-NOTES.md.
    private func registerTrashChainUndo(box: TrashRecordBox, actionName: String) {
        registerFileOpUndo(actionName) { target in
            target.registerTrashChainUndo(box: box, actionName: actionName)
            // Enqueued (not a bare Task, and the `switch` moved INSIDE the
            // closure rather than evaluated synchronously here) - see
            // `TrashRecordBox`'s "Read-time invariant" doc comment for why:
            // a synchronous read here could observe a stale generation
            // under rapid undo/redo.
            target.enqueueFileOpUndoWork {
                switch box.state {
                case .inTree(let nodes):
                    let result = await target.performTrash(nodes: nodes)
                    box.state = .trashed(result.records)
                    if let firstError = result.errors.first {
                        target.errorMessage = "Failed to move to trash: \(firstError.localizedDescription)"
                    }
                case .trashed(let records):
                    let result = await target.performRestore(records: records)
                    box.state = .inTree(result.restored)
                    if let firstError = result.errors.first {
                        target.errorMessage = "Failed to restore from trash: \(firstError.localizedDescription)"
                    }
                }
            }
        }
    }

    /// Drops any node in `nodes` that has an ancestor also present in `nodes` -
    /// trashing the ancestor already removes the descendant from disk
    /// (SELECTION-MODEL-MEMO.md section 5). Non-private: FileListView's
    /// trash-confirmation copy needs the pruned count (not the raw selection
    /// count) before the user confirms.
    func pruneDescendants(of nodes: [FileNode]) -> [FileNode] {
        let ids = Set(nodes.map(\.id))
        return nodes.filter { node in
            var current = node.parent
            while let parent = current {
                if ids.contains(parent.id) {
                    return false
                }
                current = parent.parent
            }
            return true
        }
    }

    /// Reveal multiple files/folders in Finder as a single selection
    /// (victor-sel batch operation).
    func revealInFinder(nodes: [FileNode]) {
        fileOperationsService.revealInFinder(urls: nodes.map(\.url))
    }

    /// Reveal a file in Finder
    func revealInFinder(node: FileNode) {
        fileOperationsService.revealInFinder(url: node.url)
    }

    /// Copy one or more paths to the pasteboard, newline-joined. Routes through the
    /// service layer rather than touching NSPasteboard here.
    func copyPathsToClipboard(urls: [URL]) {
        fileOperationsService.copyPathsToClipboard(urls: urls)
    }

    /// Copy file path to clipboard
    func copyPath(node: FileNode) {
        fileOperationsService.copyPathToClipboard(url: node.url)
    }

    /// Create a new folder inside the given directory
    func createFolder(in parent: FileNode) async {
        guard parent.isDirectory else { return }

        do {
            let newURL = try await fileOperationsService.createFolder(in: parent.url)

            // Create a FileNode for the new folder
            let newNode = FileNode(url: newURL, isDirectory: true, isPageBundle: false)
            parent.addChild(newNode)
            registerNode(newNode)

            // Invalidate filter cache since tree changed
            invalidateFilterCache()
        } catch {
            errorMessage = "Failed to create folder: \(error.localizedDescription)"
            Logger.shared.error("Error creating folder", error: error)
        }
    }

    // MARK: - File Menu Target Resolution
    //
    // Shared folder-resolution logic for File > New Post… and File > New Folder,
    // which both need "the selected folder, or a sensible fallback" per
    // Docs/MAC-POLISH-DESIGN.md W2.1.

    /// The top-level folder node with the given Hugo role (content/, static/,
    /// layouts/, data/, etc.), if the loaded site has one. Used by File menu
    /// target resolution and the Go menu's "Go to <role>/" jump items.
    func topLevelFolder(for role: HugoRole) -> FileNode? {
        fileNodes.first { $0.hugoRole == role }
    }

    /// The top-level content/ folder node, if the loaded site has one.
    var contentRootNode: FileNode? {
        topLevelFolder(for: .content)
    }

    /// Target folder for File > New Post…: the selected folder (or the parent
    /// of a selected file) when it's inside content/, otherwise content/ root.
    var newContentTargetFolder: FileNode? {
        if let selectedNode {
            let candidate = selectedNode.isDirectory ? selectedNode : selectedNode.parent
            if let candidate, isNode(candidate, descendantOfRole: .content) {
                return candidate
            }
        }
        return contentRootNode
    }

    /// Target folder for File > New Folder: the selected folder, or the
    /// parent of a selected file, falling back to content/ root.
    var newFolderTargetFolder: FileNode? {
        if let selectedNode {
            if selectedNode.isDirectory { return selectedNode }
            if let parent = selectedNode.parent { return parent }
        }
        return contentRootNode
    }

    /// Walks up from `node` to check whether it (or an ancestor) has the given Hugo role.
    private func isNode(_ node: FileNode, descendantOfRole role: HugoRole) -> Bool {
        var current: FileNode? = node
        while let n = current {
            if n.hugoRole == role { return true }
            current = n.parent
        }
        return false
    }

    // MARK: - Go Menu Navigation History
    //
    // Ordered history with a cursor, unlike `recentFiles` (an MRU with no position).
    // Stores node IDs, so a dead entry just fails `findNode(id:)`; back/forward prune
    // those and continue rather than consuming the keypress. A reload resets outright,
    // since every FileNode UUID regenerates on rescan.

    /// Ordered navigation history of selected node IDs.
    private var navigationHistory: [UUID] = []

    /// Index into `navigationHistory` representing "here". -1 means empty.
    private var navigationHistoryCursor: Int = -1

    /// Set while `navigateBack()`/`navigateForward()` are driving `selectNode(_:)`,
    /// so that call doesn't itself push a new history entry.
    private var isNavigatingHistory = false

    /// Maximum number of entries retained in the navigation history.
    private let maxNavigationHistory = 50

    /// Whether Go > Back has anywhere to go.
    var canNavigateBack: Bool {
        navigationHistoryCursor > 0
    }

    /// Whether Go > Forward has anywhere to go.
    var canNavigateForward: Bool {
        navigationHistoryCursor >= 0 && navigationHistoryCursor < navigationHistory.count - 1
    }

    /// Record a newly selected node into the navigation history. Called from
    /// `selectNode(_:)`. No-ops while replaying history (back/forward) and
    /// when the node is already the current history entry (avoids duplicate
    /// consecutive entries e.g. from `handleContentChange` re-selecting).
    private func pushNavigationHistory(_ node: FileNode) {
        guard !isNavigatingHistory else { return }
        if navigationHistoryCursor >= 0, navigationHistory[navigationHistoryCursor] == node.id {
            return
        }

        // Selecting a new node while sitting in the middle of history (after
        // going back) branches - discard the stale "forward" entries.
        if navigationHistoryCursor < navigationHistory.count - 1 {
            navigationHistory.removeSubrange((navigationHistoryCursor + 1)...)
        }

        navigationHistory.append(node.id)
        navigationHistoryCursor = navigationHistory.count - 1

        if navigationHistory.count > maxNavigationHistory {
            let overflow = navigationHistory.count - maxNavigationHistory
            navigationHistory.removeFirst(overflow)
            navigationHistoryCursor -= overflow
        }
    }

    /// Moves the cursor one step in `direction` (-1 for Back, +1 for Forward),
    /// pruning any dead entries (nodes no longer resolvable via `findNode(id:)`)
    /// encountered along the way and selecting the first live entry found.
    /// If no live entry exists in that direction, the cursor is left exactly
    /// where it started - no silent no-op step, and no landing on a dead entry.
    private func navigate(direction: Int) {
        while true {
            let candidateCursor = navigationHistoryCursor + direction
            guard candidateCursor >= 0, candidateCursor < navigationHistory.count else {
                return
            }

            guard let node = findNode(id: navigationHistory[candidateCursor]) else {
                // Dead entry - prune it and keep looking in the same direction.
                navigationHistory.remove(at: candidateCursor)
                if candidateCursor <= navigationHistoryCursor {
                    // Removed an entry at-or-before the cursor: everything from
                    // there on shifted left by one, so the cursor must follow.
                    navigationHistoryCursor -= 1
                }
                continue
            }

            navigationHistoryCursor = candidateCursor
            isNavigatingHistory = true
            selectAndRevealNode(node)
            isNavigatingHistory = false
            return
        }
    }

    /// Go menu > Back: select the previously-selected file.
    func navigateBack() {
        guard canNavigateBack else { return }
        navigate(direction: -1)
    }

    /// Go menu > Forward: re-select the file navigated away from by the last Back.
    func navigateForward() {
        guard canNavigateForward else { return }
        navigate(direction: 1)
    }

    // MARK: - Hugo Server Control

    /// Observation tasks for the two `HugoServerService` streams. This view model lives for
    /// the app's lifetime, so they run until termination; stored for testability.
    private var statusObservationTask: Task<Void, Never>?
    private var buildErrorsObservationTask: Task<Void, Never>?

    /// Only a genuine (re)start qualifies. The status stream replays its current value to
    /// every new subscriber, and treating the replay as "started" would force live preview
    /// back on whenever this observer is reinstalled. `previous == nil` means that replay.
    static func shouldAutoEnableLivePreview(previous: HugoServerStatus?, new: HugoServerStatus) -> Bool {
        guard let previous else { return false }
        return !previous.isRunning && new.isRunning
    }

    /// Idempotent: cancels observers from a previous call first. `ContentView`'s `.onAppear`
    /// can fire more than once, which would otherwise stack duplicate stream consumers.
    func setupHugoServerObservers() {
        statusObservationTask?.cancel()
        buildErrorsObservationTask?.cancel()

        statusObservationTask = Task { [weak self] in
            guard let stream = await self?.hugoServerService.statusUpdates() else { return }
            var previousStatus: HugoServerStatus? = nil
            for await status in stream {
                guard let self else { return }
                self.hugoServerStatus = status
                if Self.shouldAutoEnableLivePreview(previous: previousStatus, new: status) {
                    self.useLivePreview = true
                }
                previousStatus = status
            }
        }
        buildErrorsObservationTask = Task { [weak self] in
            guard let stream = await self?.hugoServerService.buildErrorUpdates() else { return }
            for await errors in stream {
                self?.hugoBuildErrors = errors
            }
        }

        // `hugoServerURL` isn't part of either stream above (it's a plain
        // actor-isolated var, not one of Cluster 9's three notify signals) -
        // fetch it once here so re-entering this screen while the server is
        // already running (e.g. the main window re-appearing) still picks up
        // the current URL, matching the old callback-based setup's behavior.
        Task { [weak self] in
            guard let self else { return }
            let initialURL = await self.hugoServerService.serverURL
            self.hugoServerURL = initialURL
        }
    }

    /// Start the Hugo development server
    func startHugoServer() async throws {
        guard let siteURL = site?.rootURL else {
            throw HugoServerError.notRunning
        }
        try await hugoServerService.start(siteURL: siteURL)
        hugoServerURL = await hugoServerService.serverURL
    }

    /// Stop the Hugo development server
    func stopHugoServer() async {
        await hugoServerService.stop()
        hugoServerURL = nil
    }

    /// Toggle the Hugo server state
    func toggleHugoServer() async {
        if isHugoServerRunning {
            await stopHugoServer()
        } else {
            do {
                try await startHugoServer()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Toggle between live preview and markdown preview
    func toggleLivePreview() {
        useLivePreview.toggle()
    }
}
