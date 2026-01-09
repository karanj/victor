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

    /// Current editing content (for preview sync across layout modes)
    var currentEditingContent: String = ""

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

    /// Recently opened files (for Quick Open)
    var recentFiles: [FileNode] = []

    /// Maximum number of recent files to track
    private let maxRecentFiles = 10

    /// Hugo configuration (loaded when a config file is selected)
    var hugoConfig: HugoConfig?

    /// Whether the Hugo config is currently loading
    var isLoadingConfig = false

    /// Currently loaded data file (for data/ directory files)
    var currentDataFile: DataFile?

    /// Whether a data file is currently loading
    var isLoadingDataFile = false

    /// Error from last data file load attempt (to prevent infinite retry)
    var dataFileLoadError: String?

    /// URL of the last failed data file load (to prevent infinite retry)
    var failedDataFileURL: URL?

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


    /// Filtered file nodes based on search (recursively searches tree)
    var filteredNodes: [FileNode] {
        guard !searchQuery.isEmpty else {
            autoExpandedNodeIDs.removeAll()
            return fileNodes
        }
        autoExpandedNodeIDs.removeAll()
        return filterNodesRecursively(fileNodes, query: searchQuery)
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

            // Build lookup table for fast node access
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
    private func findNode(url: URL) -> FileNode? {
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
        if let url = site?.rootURL {
            fileSystemService.stopAccessing(url: url)
        }
        site = nil
        fileNodes = []
        selectedNode = nil
        selectedFileID = nil
        currentEditingContent = ""
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

        // Clear editing content to prevent stale data flash
        currentEditingContent = ""

        // Load content in background if needed
        if let node = actualNode, node.isMarkdownFile {
            if let contentFile = node.contentFile {
                // Content already loaded - initialize immediately
                currentEditingContent = contentFile.markdownContent
                addRecentFile(node)
                updateContentCache(accessedNodeID: node.id)
            } else {
                // Content not loaded - load in background
                isLoadingFile = true
                Task { [weak self] in
                    guard let self = self else { return }
                    await self.loadFileContent(for: node)
                    // Only update content if this node is still selected
                    if node.id == self.selectedNode?.id {
                        self.currentEditingContent = node.contentFile?.markdownContent ?? ""
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
    func isFileModified(_ nodeID: UUID) -> Bool {
        modifiedFileIDs.contains(nodeID)
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
        !modifiedFileIDs.isEmpty
    }

    /// Save all files with unsaved changes
    func saveAllModifiedFiles() async {
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
    }

    // MARK: - Status Metadata Loading (Lazy)

    /// Load status metadata for markdown files in a folder when it's expanded
    /// This enables showing Draft/Scheduled/Expired badges before files are opened
    func onFolderExpanded(_ folder: FileNode) {
        // Skip if already loaded
        guard !loadedStatusFolderIDs.contains(folder.id) else { return }

        // Collect markdown file URLs that don't have status yet
        let markdownChildren = folder.children.filter {
            $0.isMarkdownFile && $0.statusMetadata == nil && $0.contentFile == nil
        }

        guard !markdownChildren.isEmpty else {
            loadedStatusFolderIDs.insert(folder.id)
            return
        }

        let urls = markdownChildren.map { $0.url }

        Task { [weak self] in
            guard let self = self else { return }

            let metadataMap = await FileSystemService.shared.loadStatusMetadata(for: urls)

            // Update nodes with loaded metadata
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
            config.hasUnsavedChanges = false
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
            config.hasUnsavedChanges = false
            Logger.shared.info("Saved Hugo config (raw): \(url.lastPathComponent)")
        } catch {
            errorMessage = "Failed to save config: \(error.localizedDescription)"
            Logger.shared.error("Error saving Hugo config", error: error)
        }
    }

    // MARK: - Data File Management

    /// Load a data file from URL (for files in data/ directory)
    func loadDataFile(from url: URL) async {
        // Clear previous error state
        dataFileLoadError = nil
        failedDataFileURL = nil
        isLoadingDataFile = true

        do {
            let dataFile = try await DataFileParser.shared.parseDataFile(at: url)
            currentDataFile = dataFile
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

    /// Create a new markdown file inside the given folder node
    func createMarkdownFile(in folder: FileNode) async {
        guard folder.isDirectory else { return }

        do {
            // Ask filesystem service to create a new markdown file
            let newFileURL = try await fileSystemService.createMarkdownFile(in: folder.url)

            // Build a FileNode for the new file and insert it into the tree
            let newNode = FileNode(url: newFileURL, isDirectory: false, isPageBundle: false)
            folder.addChild(newNode)

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

            // Clear selection if this was selected
            if selectedNode?.id == node.id {
                selectedNode = nil
                selectedFileID = nil
                currentEditingContent = ""
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
        } catch {
            errorMessage = "Failed to create folder: \(error.localizedDescription)"
            Logger.shared.error("Error creating folder", error: error)
        }
    }
}
