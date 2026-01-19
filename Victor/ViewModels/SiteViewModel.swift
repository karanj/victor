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

    /// Currently selected file node
    var selectedNode: FileNode?

    /// Selected file ID for binding
    var selectedFileID: FileNode.ID? {
        didSet {
            // Avoid redundant processing if selecting the same ID
            guard selectedFileID != oldValue else { return }

            // Find and select the node when selectedFileID changes
            if let id = selectedFileID,
               let node = findNode(id: id) {
                selectNode(node)
            }
        }
    }

    /// Per-file edited content storage - preserves unsaved edits when switching files
    /// Key is file node ID, value is the edited content
    private var editedContentByFile: [UUID: String] = [:]

    /// Current editing content (for preview sync across layout modes)
    /// Computed property that reads/writes from per-file storage based on selected node
    var currentEditingContent: String {
        get {
            guard let nodeID = selectedNode?.id else { return "" }
            return editedContentByFile[nodeID] ?? ""
        }
        set {
            guard let nodeID = selectedNode?.id else { return }
            editedContentByFile[nodeID] = newValue
        }
    }

    /// Get edited content for a specific file by ID (regardless of which file is selected)
    /// Used by EditorViewModel to retrieve content for its specific file
    func getEditedContent(for nodeID: UUID) -> String? {
        return editedContentByFile[nodeID]
    }

    /// Set edited content for a specific file by ID (regardless of which file is selected)
    /// Used by EditorViewModel to update content for its specific file
    func setEditedContent(_ content: String, for nodeID: UUID) {
        editedContentByFile[nodeID] = content
    }

    /// Live preview enabled state (controls real-time updates in split view)
    var isLivePreviewEnabled: Bool = true

    /// Auto-save enabled state (persisted)
    var isAutoSaveEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAutoSaveEnabled, forKey: AppConstants.UserDefaultsKeys.isAutoSaveEnabled)
        }
    }

    /// Editor layout mode: editor only, preview only, or split (persisted)
    var layoutMode: EditorLayoutMode {
        didSet {
            UserDefaults.standard.set(layoutMode.rawValue, forKey: AppConstants.UserDefaultsKeys.editorLayoutMode)
        }
    }

    /// Highlight current line in editor (persisted)
    var highlightCurrentLine: Bool {
        didSet {
            UserDefaults.standard.set(highlightCurrentLine, forKey: AppConstants.UserDefaultsKeys.highlightCurrentLine)
        }
    }

    /// Editor font size (persisted)
    var editorFontSize: Double {
        didSet {
            UserDefaults.standard.set(editorFontSize, forKey: AppConstants.UserDefaultsKeys.editorFontSize)
        }
    }

    /// Auto-save delay in seconds (persisted)
    var autoSaveDelay: Double {
        didSet {
            UserDefaults.standard.set(autoSaveDelay, forKey: AppConstants.UserDefaultsKeys.autoSaveDelay)
        }
    }

    /// Inspector panel visibility (persisted)
    var isInspectorVisible: Bool {
        didSet {
            UserDefaults.standard.set(isInspectorVisible, forKey: AppConstants.UserDefaultsKeys.isInspectorVisible)
        }
    }

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

    /// Whether global search panel is presented
    var isGlobalSearchPresented = false

    /// Recently opened files (for Quick Open)
    var recentFiles: [FileNode] = []

    /// Maximum number of recent files to track
    private let maxRecentFiles = 10

    /// Hugo configuration (loaded when a config file is selected)
    var hugoConfig: HugoConfig?

    /// Whether the Hugo config is currently loading
    var isLoadingConfig = false

    /// Per-file storage for data files - preserves unsaved edits when switching
    private var loadedDataFiles: [URL: DataFile] = [:]

    /// Currently loaded data file (computed from per-file storage based on selected node)
    var currentDataFile: DataFile? {
        get {
            guard let url = selectedNode?.url else { return nil }
            return loadedDataFiles[url]
        }
        set {
            guard let url = selectedNode?.url else { return }
            if let file = newValue {
                loadedDataFiles[url] = file
            } else {
                loadedDataFiles.removeValue(forKey: url)
            }
        }
    }

    /// Whether a data file is currently loading
    var isLoadingDataFile = false

    /// Error from last data file load attempt (to prevent infinite retry)
    var dataFileLoadError: String?

    /// URL of the last failed data file load (to prevent infinite retry)
    var failedDataFileURL: URL?

    /// Per-file storage for templates - preserves unsaved edits when switching
    private var loadedTemplates: [URL: Template] = [:]

    /// Currently loaded template (computed from per-file storage based on selected node)
    var currentTemplate: Template? {
        get {
            guard let url = selectedNode?.url else { return nil }
            return loadedTemplates[url]
        }
        set {
            guard let url = selectedNode?.url else { return }
            if let file = newValue {
                loadedTemplates[url] = file
            } else {
                loadedTemplates.removeValue(forKey: url)
            }
        }
    }

    /// Whether a template is currently loading
    var isLoadingTemplate = false

    /// Error from last template load attempt
    var templateLoadError: String?

    /// URL of the last failed template load
    var failedTemplateURL: URL?

    /// Per-file storage for archetypes - preserves unsaved edits when switching
    private var loadedArchetypes: [URL: Archetype] = [:]

    /// Currently loaded archetype (computed from per-file storage based on selected node)
    var currentArchetype: Archetype? {
        get {
            guard let url = selectedNode?.url else { return nil }
            return loadedArchetypes[url]
        }
        set {
            guard let url = selectedNode?.url else { return }
            if let file = newValue {
                loadedArchetypes[url] = file
            } else {
                loadedArchetypes.removeValue(forKey: url)
            }
        }
    }

    /// Whether an archetype is currently loading
    var isLoadingArchetype = false

    /// Error from last archetype load attempt
    var archetypeLoadError: String?

    /// URL of the last failed archetype load
    var failedArchetypeURL: URL?

    /// Maximum number of ContentFiles to keep cached in memory
    /// Files beyond this limit will have their contentFile released
    private let maxCachedContentFiles = 20

    /// LRU cache tracking: ordered list of node IDs with loaded content (most recent first)
    private var contentCacheOrder: [UUID] = []

    /// Recently opened sites (paths stored in UserDefaults)
    var recentSitePaths: [String] {
        UserDefaults.standard.stringArray(forKey: AppConstants.UserDefaultsKeys.recentSitePaths) ?? []
    }

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

    /// File system service
    private let fileSystemService = FileSystemService.shared

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
        // Empty search - return fileNodes directly (no caching needed)
        guard !searchQuery.isEmpty else {
            autoExpandedNodeIDs.removeAll()
            _cachedFilteredNodes = nil
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

    init() {
        // Load auto-save preference (default: true)
        self.isAutoSaveEnabled = UserDefaults.standard.object(forKey: AppConstants.UserDefaultsKeys.isAutoSaveEnabled) as? Bool ?? true

        // Load layout mode preference (default: .split for backwards compatibility)
        if let savedMode = UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.editorLayoutMode),
           let mode = EditorLayoutMode(rawValue: savedMode) {
            self.layoutMode = mode
        } else {
            self.layoutMode = .split
        }

        // Load current line highlighting preference (default: true)
        self.highlightCurrentLine = UserDefaults.standard.object(forKey: AppConstants.UserDefaultsKeys.highlightCurrentLine) as? Bool ?? true

        // Load editor font size preference (default: 13)
        self.editorFontSize = UserDefaults.standard.object(forKey: AppConstants.UserDefaultsKeys.editorFontSize) as? Double ?? 13.0

        // Load auto-save delay preference (default: 2 seconds)
        self.autoSaveDelay = UserDefaults.standard.object(forKey: AppConstants.UserDefaultsKeys.autoSaveDelay) as? Double ?? 2.0

        // Load inspector visibility preference (default: false)
        self.isInspectorVisible = UserDefaults.standard.object(forKey: AppConstants.UserDefaultsKeys.isInspectorVisible) as? Bool ?? false

        // Try to load previously opened site
        Task { [weak self] in
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

            // Track this site in recent sites
            addRecentSite(url.path)

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
        var paths = recentSitePaths

        // Remove if already exists (to move to front)
        paths.removeAll { $0 == path }

        // Add to front
        paths.insert(path, at: 0)

        // Trim to max size
        if paths.count > maxRecentSites {
            paths = Array(paths.prefix(maxRecentSites))
        }

        UserDefaults.standard.set(paths, forKey: AppConstants.UserDefaultsKeys.recentSitePaths)
    }

    /// Open a recent site by path
    func openRecentSite(_ path: String) async {
        let url = URL(fileURLWithPath: path)

        // Check if the path still exists
        guard FileManager.default.fileExists(atPath: path) else {
            // Remove from recent sites if it no longer exists
            var paths = recentSitePaths
            paths.removeAll { $0 == path }
            UserDefaults.standard.set(paths, forKey: AppConstants.UserDefaultsKeys.recentSitePaths)
            errorMessage = "Site folder no longer exists at: \(path)"
            return
        }

        await loadSite(from: url)
    }

    /// Clear recent sites list
    func clearRecentSites() {
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.recentSitePaths)
    }

    /// Remove a single site from the recent sites list
    func removeRecentSite(_ path: String) {
        var paths = recentSitePaths
        paths.removeAll { $0 == path }
        UserDefaults.standard.set(paths, forKey: AppConstants.UserDefaultsKeys.recentSitePaths)
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
            await HugoServerService.shared.stop()
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
        invalidateFilterCache()
        selectedNode = nil
        selectedFileID = nil
        editedContentByFile.removeAll()  // Clear all per-file markdown edits
        loadedDataFiles.removeAll()      // Clear all loaded data files
        loadedTemplates.removeAll()      // Clear all loaded templates
        loadedArchetypes.removeAll()     // Clear all loaded archetypes
        hugoConfig = nil                 // Clear loaded Hugo config
        recentFiles = []
        contentCacheOrder = []
        modifiedFileIDs = []
        recentlySavedFileIDs = [:]
        loadedStatusFolderIDs = []
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

    /// Find a node by ID using O(1) lookup instead of O(n) tree traversal
    func findNode(id: UUID) -> FileNode? {
        return nodeByID[id]
    }

    // MARK: - File Row View Models

    /// Generate a cached view model for a file row
    func rowViewModel(for node: FileNode) -> FileRowViewModel {
        return FileRowViewModel(node: node, siteViewModel: self)
    }

    // MARK: - File Selection

    /// Select a file node
    func selectNode(_ node: FileNode?) {
        // Handle page bundle folders: select the index file instead
        let actualNode: FileNode?
        if let node = node, node.isPageBundle, let indexFile = node.indexFile {
            actualNode = indexFile
        } else {
            actualNode = node
        }

        // If selecting the same node, do nothing
        if actualNode?.id == selectedNode?.id {
            return
        }

        // OPTIMISTIC UPDATE: Update UI immediately, before any loading
        selectedNode = actualNode

        // Auto-hide inspector when switching to a non-markdown file
        // (The inspector toolbar button is only shown for markdown files,
        // so we need to auto-dismiss to prevent the user being stuck)
        if isInspectorVisible && (actualNode == nil || !actualNode!.isMarkdownFile) {
            isInspectorVisible = false
        }

        // Only set selectedFileID if it's different to avoid triggering didSet again
        if selectedFileID != actualNode?.id {
            selectedFileID = actualNode?.id
        }

        // Persist selected file path for restoration on next launch
        if let path = actualNode?.url.path {
            UserDefaults.standard.set(path, forKey: AppConstants.UserDefaultsKeys.lastSelectedFilePath)
        } else {
            UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.lastSelectedFilePath)
        }

        // Load content based on file type
        // Only initialize content if there's no existing edited content for this file
        // (preserves unsaved edits when switching between files)
        if let node = actualNode, node.isMarkdownFile {
            if let contentFile = node.contentFile {
                // Content already loaded - only set if no existing edits
                if editedContentByFile[node.id] == nil {
                    editedContentByFile[node.id] = contentFile.markdownContent
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
                       self.editedContentByFile[node.id] == nil {
                        self.editedContentByFile[node.id] = node.contentFile?.markdownContent ?? ""
                    }
                    if node.id == self.selectedNode?.id {
                        self.addRecentFile(node)
                        self.updateContentCache(accessedNodeID: node.id)
                    }
                    self.isLoadingFile = false
                }
            }
        } else if let node = actualNode, node.isEditable && node.fileType.isTextBased {
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
        isInspectorVisible.toggle()
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

    /// Mark a file as having unsaved changes
    func markFileModified(_ nodeID: UUID) {
        modifiedFileIDs.insert(nodeID)
    }

    /// Clear the modified state for a file
    func clearFileModified(_ nodeID: UUID) {
        modifiedFileIDs.remove(nodeID)
    }

    /// Mark a file as recently saved (shows green checkmark that fades)
    func markFileSaved(_ nodeID: UUID) {
        // Clear modified state
        modifiedFileIDs.remove(nodeID)

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

        // Check config, data files, and templates via their model state
        if let node = findNode(id: nodeID) {
            // Check Hugo config
            if let config = hugoConfig, config.sourceURL == node.url, config.hasUnsavedChanges {
                return true
            }
            if let dataFile = loadedDataFiles[node.url], dataFile.hasUnsavedChanges {
                return true
            }
            if let template = loadedTemplates[node.url], template.hasUnsavedChanges {
                return true
            }
            if let archetype = loadedArchetypes[node.url], archetype.hasUnsavedChanges {
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
        // Check Hugo config
        if hugoConfig?.hasUnsavedChanges == true {
            return true
        }
        // Check data files
        if loadedDataFiles.values.contains(where: { $0.hasUnsavedChanges }) {
            return true
        }
        // Check templates
        if loadedTemplates.values.contains(where: { $0.hasUnsavedChanges }) {
            return true
        }
        // Check archetypes
        if loadedArchetypes.values.contains(where: { $0.hasUnsavedChanges }) {
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
                    try await fileSystemService.saveContentFile(contentFile)
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

        // Save Hugo config if modified
        if hugoConfig?.hasUnsavedChanges == true {
            await saveHugoConfig()
        }

        // Save data files with unsaved changes
        for (_, dataFile) in loadedDataFiles where dataFile.hasUnsavedChanges {
            do {
                try await DataFileParser.shared.save(dataFile)
                Logger.shared.info("Saved data file: \(dataFile.fileName)")
            } catch {
                Logger.shared.error("Failed to save data file \(dataFile.fileName)", error: error)
            }
        }

        // Save templates with unsaved changes
        for (_, template) in loadedTemplates where template.hasUnsavedChanges {
            do {
                try await TemplateParser.shared.save(template)
                Logger.shared.info("Saved template: \(template.fileName)")
            } catch {
                Logger.shared.error("Failed to save template \(template.fileName)", error: error)
            }
        }

        // Save archetypes with unsaved changes
        for (_, archetype) in loadedArchetypes where archetype.hasUnsavedChanges {
            do {
                try archetype.rawContent.write(to: archetype.url, atomically: true, encoding: .utf8)
                archetype.markAsSaved()
                Logger.shared.info("Saved archetype: \(archetype.fileName)")
            } catch {
                Logger.shared.error("Failed to save archetype \(archetype.fileName)", error: error)
            }
        }
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
            let metadataMap = await FileSystemService.shared.loadStatusMetadata(for: urls)

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
            let content = try await Task.detached {
                try String(contentsOf: node.url, encoding: .utf8)
            }.value

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

        // Evict old entries if over limit
        while contentCacheOrder.count > maxCachedContentFiles {
            let oldestID = contentCacheOrder.removeLast()

            // Don't evict the currently selected file
            guard oldestID != selectedNode?.id else {
                // Put it back and try the next oldest
                contentCacheOrder.insert(oldestID, at: contentCacheOrder.count)
                continue
            }

            // Don't evict files with unsaved changes
            guard !modifiedFileIDs.contains(oldestID) else {
                contentCacheOrder.insert(oldestID, at: contentCacheOrder.count)
                continue
            }

            // Find the node and release its content
            if let node = FileNode.findNode(id: oldestID, in: fileNodes) {
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
        isLoadingConfig = true
        do {
            let config = try await HugoConfigParser.shared.parseConfig(at: url)
            hugoConfig = config
            Logger.shared.info("Loaded Hugo config: \(url.lastPathComponent)")
        } catch {
            errorMessage = "Failed to load config: \(error.localizedDescription)"
            Logger.shared.error("Error loading Hugo config", error: error)
        }
        isLoadingConfig = false
    }

    /// Save the current Hugo configuration (from form fields)
    func saveHugoConfig() async {
        guard let config = hugoConfig, let url = config.sourceURL else {
            errorMessage = "No configuration to save"
            return
        }

        do {
            let content = try HugoConfigParser.shared.serialize(config)
            try await fileSystemService.writeFile(to: url, content: content)
            // Keep rawContent in sync with what we saved
            config.rawContent = content
            config.markAsSaved()
            Logger.shared.info("Saved Hugo config: \(url.lastPathComponent)")
        } catch {
            errorMessage = "Failed to save config: \(error.localizedDescription)"
            Logger.shared.error("Error saving Hugo config", error: error)
        }
    }

    /// Save the current Hugo configuration directly from rawContent (for raw editor mode)
    func saveHugoConfigRaw() async {
        guard let config = hugoConfig, let url = config.sourceURL else {
            errorMessage = "No configuration to save"
            return
        }

        do {
            // Save rawContent directly without serialization
            try await fileSystemService.writeFile(to: url, content: config.rawContent)
            config.markAsSaved()
            Logger.shared.info("Saved Hugo config (raw): \(url.lastPathComponent)")
        } catch {
            errorMessage = "Failed to save config: \(error.localizedDescription)"
            Logger.shared.error("Error saving Hugo config", error: error)
        }
    }

    // MARK: - Data File Management

    /// Load a data file from URL (for files in data/ directory)
    /// Only loads from disk if not already in memory (preserves unsaved edits)
    func loadDataFile(from url: URL) async {
        // If already loaded, don't reload (preserves unsaved edits)
        if loadedDataFiles[url] != nil {
            isLoadingDataFile = false
            return
        }

        // Clear previous error state
        dataFileLoadError = nil
        failedDataFileURL = nil
        isLoadingDataFile = true

        do {
            let dataFile = try await DataFileParser.shared.parseDataFile(at: url)
            loadedDataFiles[url] = dataFile
            Logger.shared.info("Loaded data file: \(url.lastPathComponent)")
        } catch {
            dataFileLoadError = error.localizedDescription
            failedDataFileURL = url
            errorMessage = "Failed to load data file: \(error.localizedDescription)"
            Logger.shared.error("Error loading data file", error: error)
        }
        isLoadingDataFile = false
    }

    /// Save the current data file
    func saveDataFile() async {
        guard let dataFile = currentDataFile else {
            errorMessage = "No data file to save"
            return
        }

        do {
            try await DataFileParser.shared.save(dataFile)
            Logger.shared.info("Saved data file: \(dataFile.fileName)")
        } catch {
            errorMessage = "Failed to save data file: \(error.localizedDescription)"
            Logger.shared.error("Error saving data file", error: error)
        }
    }

    // MARK: - Template Management

    /// Load a template file from URL (for files in layouts/ or themes/ directories)
    /// Only loads from disk if not already in memory (preserves unsaved edits)
    func loadTemplate(from url: URL) async {
        // If already loaded, don't reload (preserves unsaved edits)
        if loadedTemplates[url] != nil {
            isLoadingTemplate = false
            return
        }

        // Clear previous error state
        templateLoadError = nil
        failedTemplateURL = nil
        isLoadingTemplate = true

        do {
            let template = try await TemplateParser.shared.parseTemplate(at: url)
            loadedTemplates[url] = template
            Logger.shared.info("Loaded template: \(url.lastPathComponent)")
        } catch {
            templateLoadError = error.localizedDescription
            failedTemplateURL = url
            errorMessage = "Failed to load template: \(error.localizedDescription)"
            Logger.shared.error("Error loading template", error: error)
        }
        isLoadingTemplate = false
    }

    /// Save the current template
    func saveTemplate() async {
        guard let template = currentTemplate else {
            errorMessage = "No template to save"
            return
        }

        do {
            try await TemplateParser.shared.save(template)
            Logger.shared.info("Saved template: \(template.fileName)")
        } catch {
            errorMessage = "Failed to save template: \(error.localizedDescription)"
            Logger.shared.error("Error saving template", error: error)
        }
    }

    // MARK: - Archetype Management

    /// Load an archetype file from URL (for files in archetypes/ directory)
    /// Only loads from disk if not already in memory (preserves unsaved edits)
    func loadArchetype(from url: URL) async {
        // If already loaded, don't reload (preserves unsaved edits)
        if loadedArchetypes[url] != nil {
            isLoadingArchetype = false
            return
        }

        // Clear previous error state
        archetypeLoadError = nil
        failedArchetypeURL = nil
        isLoadingArchetype = true

        do {
            let archetype = try await parseArchetype(at: url)
            loadedArchetypes[url] = archetype
            Logger.shared.info("Loaded archetype: \(url.lastPathComponent)")
        } catch {
            archetypeLoadError = error.localizedDescription
            failedArchetypeURL = url
            errorMessage = "Failed to load archetype: \(error.localizedDescription)"
            Logger.shared.error("Error loading archetype", error: error)
        }
        isLoadingArchetype = false
    }

    /// Parse an archetype file from disk
    private func parseArchetype(at url: URL) async throws -> Archetype {
        let content = try await Task.detached {
            try String(contentsOf: url, encoding: .utf8)
        }.value

        // Parse frontmatter and body from the content
        let lines = content.components(separatedBy: "\n")
        guard !lines.isEmpty else {
            return Archetype(url: url, frontmatterContent: "", bodyTemplate: content, frontmatterFormat: .yaml)
        }

        // Detect frontmatter format from first line
        let firstLine = lines[0].trimmingCharacters(in: .whitespaces)
        var format: FrontmatterFormat
        var delimiter: String

        if firstLine == "---" {
            format = .yaml
            delimiter = "---"
        } else if firstLine == "+++" {
            format = .toml
            delimiter = "+++"
        } else if firstLine.hasPrefix("{") {
            // JSON frontmatter - parse differently
            format = .json
            return try parseJSONArchetype(url: url, content: content, lines: lines)
        } else {
            // No frontmatter detected - treat entire file as body
            return Archetype(url: url, frontmatterContent: "", bodyTemplate: content, frontmatterFormat: .yaml)
        }

        // Find closing delimiter for YAML/TOML
        var frontmatterLines: [String] = []
        var bodyLines: [String] = []
        var foundClosing = false

        for (index, line) in lines.enumerated() {
            if index == 0 { continue } // Skip opening delimiter

            if line.trimmingCharacters(in: .whitespaces) == delimiter && !foundClosing {
                foundClosing = true
                continue
            }

            if foundClosing {
                bodyLines.append(line)
            } else {
                frontmatterLines.append(line)
            }
        }

        let frontmatter = frontmatterLines.joined(separator: "\n")
        let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .newlines)

        return Archetype(url: url, frontmatterContent: frontmatter, bodyTemplate: body, frontmatterFormat: format)
    }

    /// Parse JSON frontmatter archetype
    private func parseJSONArchetype(url: URL, content: String, lines: [String]) throws -> Archetype {
        var braceCount = 0
        var endIndex = 0

        for (index, line) in lines.enumerated() {
            for char in line {
                if char == "{" { braceCount += 1 }
                if char == "}" { braceCount -= 1 }
            }
            if braceCount == 0 {
                endIndex = index
                break
            }
        }

        let frontmatter = lines[0...endIndex].joined(separator: "\n")
        let body = lines.dropFirst(endIndex + 1).joined(separator: "\n").trimmingCharacters(in: .newlines)

        return Archetype(url: url, frontmatterContent: frontmatter, bodyTemplate: body, frontmatterFormat: .json)
    }

    /// Save the current archetype
    func saveArchetype() async {
        guard let archetype = currentArchetype else {
            errorMessage = "No archetype to save"
            return
        }

        do {
            try archetype.rawContent.write(to: archetype.url, atomically: true, encoding: .utf8)
            archetype.markAsSaved()
            Logger.shared.info("Saved archetype: \(archetype.fileName)")
        } catch {
            errorMessage = "Failed to save archetype: \(error.localizedDescription)"
            Logger.shared.error("Error saving archetype", error: error)
        }
    }

    /// Create a new markdown file inside the given folder node
    func createMarkdownFile(in folder: FileNode) async {
        guard folder.isDirectory else { return }

        do {
            // Ask filesystem service to create a new markdown file
            let newFileURL = try await fileSystemService.createMarkdownFile(in: folder.url)

            // Build a FileNode for the new file and insert it into the tree
            let newNode = FileNode(url: newFileURL, isDirectory: false, isPageBundle: false)
            folder.addChild(newNode)

            // Invalidate filter cache since tree changed
            invalidateFilterCache()

            // Select the newly created file
            selectNode(newNode)
        } catch {
            errorMessage = "Failed to create file: \(error.localizedDescription)"
            Logger.shared.error("Error creating markdown file", error: error)
        }
    }

    /// Reload current site
    func reloadSite() async {
        guard let site = site else { return }
        // Clear status metadata cache so it reloads fresh
        loadedStatusFolderIDs.removeAll()
        await loadSite(from: site.rootURL)
    }

    /// Reload a specific file from disk
    func reloadFile(node: FileNode) async {
        do {
            // Read the file from disk
            let freshContent = try await FileSystemService.shared.readContentFile(at: node.url)

            // Update the node's content file
            node.contentFile = freshContent

            // Update the edited content to match fresh disk content
            editedContentByFile[node.id] = freshContent.markdownContent

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

    /// Rename a file node
    func renameFile(node: FileNode, to newName: String) async {
        do {
            let newURL = try await fileSystemService.renameFile(at: node.url, to: newName)

            // Update the node's URL
            node.url = newURL

            // Clear selection if this was selected (will need to re-select)
            if selectedNode?.id == node.id {
                // Force UI update
                selectedNode = nil
                selectedNode = node
            }
        } catch {
            errorMessage = "Failed to rename file: \(error.localizedDescription)"
            Logger.shared.error("Error renaming file", error: error)
        }
    }

    /// Duplicate a file node
    func duplicateFile(node: FileNode) async {
        do {
            let newURL = try await fileSystemService.duplicateFile(at: node.url)

            // Create a new FileNode for the duplicate
            let newNode = FileNode(url: newURL, isDirectory: node.isDirectory, isPageBundle: node.isPageBundle)

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
        } catch {
            errorMessage = "Failed to duplicate file: \(error.localizedDescription)"
            Logger.shared.error("Error duplicating file", error: error)
        }
    }

    /// Move a file node to trash
    func moveToTrash(node: FileNode) async {
        do {
            try await fileSystemService.moveToTrash(at: node.url)

            // Remove from parent's children
            if let parent = node.parent {
                parent.children.removeAll { $0.id == node.id }
            } else {
                // Top-level file
                fileNodes.removeAll { $0.id == node.id }
            }

            // Invalidate filter cache since tree changed
            invalidateFilterCache()

            // Clear selection if this was selected
            if selectedNode?.id == node.id {
                editedContentByFile.removeValue(forKey: node.id)  // Clear edited content for this file
                selectedNode = nil
                selectedFileID = nil
            }
        } catch {
            errorMessage = "Failed to move to trash: \(error.localizedDescription)"
            Logger.shared.error("Error moving to trash", error: error)
        }
    }

    /// Reveal a file in Finder
    func revealInFinder(node: FileNode) {
        fileSystemService.revealInFinder(url: node.url)
    }

    /// Copy file path to clipboard
    func copyPath(node: FileNode) {
        fileSystemService.copyPathToClipboard(url: node.url)
    }

    /// Create a new folder inside the given directory
    func createFolder(in parent: FileNode) async {
        guard parent.isDirectory else { return }

        do {
            let newURL = try await fileSystemService.createFolder(in: parent.url)

            // Create a FileNode for the new folder
            let newNode = FileNode(url: newURL, isDirectory: true, isPageBundle: false)
            parent.addChild(newNode)

            // Invalidate filter cache since tree changed
            invalidateFilterCache()
        } catch {
            errorMessage = "Failed to create folder: \(error.localizedDescription)"
            Logger.shared.error("Error creating folder", error: error)
        }
    }

    // MARK: - Hugo Server Control

    /// Set up observers for Hugo server state changes
    func setupHugoServerObservers() {
        Task {
            await HugoServerService.shared.setOnStatusChange { @MainActor [weak self] newStatus in
                self?.hugoServerStatus = newStatus
                // Auto-enable live preview when server starts running
                if newStatus.isRunning {
                    self?.useLivePreview = true
                }
            }

            await HugoServerService.shared.setOnBuildErrorsChange { @MainActor [weak self] errors in
                self?.hugoBuildErrors = errors
            }

            // Get initial state
            let initialStatus = await HugoServerService.shared.status
            let initialErrors = await HugoServerService.shared.buildErrors
            let initialURL = await HugoServerService.shared.serverURL

            hugoServerStatus = initialStatus
            hugoBuildErrors = initialErrors
            hugoServerURL = initialURL
            if initialStatus.isRunning {
                useLivePreview = true
            }
        }
    }

    /// Start the Hugo development server
    func startHugoServer() async throws {
        guard let siteURL = site?.rootURL else {
            throw HugoServerError.notRunning
        }
        try await HugoServerService.shared.start(siteURL: siteURL)
        hugoServerURL = await HugoServerService.shared.serverURL
    }

    /// Stop the Hugo development server
    func stopHugoServer() async {
        await HugoServerService.shared.stop()
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
