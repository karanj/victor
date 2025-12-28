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

    /// Currently selected file node
    var selectedNode: FileNode?

    /// Selected file ID for binding
    var selectedFileID: FileNode.ID?

    /// Current editing content (for preview sync across layout modes)
    var currentEditingContent: String = ""

    /// Live preview enabled state (controls real-time updates in split view)
    var isLivePreviewEnabled: Bool = true

    /// Auto-save enabled state (persisted)
    var isAutoSaveEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAutoSaveEnabled, forKey: "isAutoSaveEnabled")
        }
    }

    /// Editor layout mode: editor only, preview only, or split (persisted)
    var layoutMode: EditorLayoutMode {
        didSet {
            UserDefaults.standard.set(layoutMode.rawValue, forKey: "editorLayoutMode")
        }
    }

    /// Highlight current line in editor (persisted)
    var highlightCurrentLine: Bool {
        didSet {
            UserDefaults.standard.set(highlightCurrentLine, forKey: "highlightCurrentLine")
        }
    }

    /// Inspector panel visibility (persisted)
    var isInspectorVisible: Bool {
        didSet {
            UserDefaults.standard.set(isInspectorVisible, forKey: "isInspectorVisible")
        }
    }

    /// Focus mode active state (not persisted - always starts inactive)
    var isFocusModeActive: Bool = false

    /// Loading state
    var isLoading = false

    /// Error message
    var errorMessage: String?

    /// Search query
    var searchQuery = ""

    /// Trigger to focus search field
    var shouldFocusSearch = false

    /// Quick Open dialog visibility
    var isQuickOpenVisible = false

    /// Recently opened files (for Quick Open)
    var recentFiles: [FileNode] = []

    /// Maximum number of recent files to track
    private let maxRecentFiles = 10

    // MARK: - File Status Tracking

    /// Files with unsaved changes (tracked by node ID)
    var modifiedFileIDs: Set<UUID> = []

    /// Files that were recently saved (node ID -> save timestamp)
    var recentlySavedFileIDs: [UUID: Date] = [:]

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
        self.isAutoSaveEnabled = UserDefaults.standard.object(forKey: "isAutoSaveEnabled") as? Bool ?? true

        // Load layout mode preference (default: .split for backwards compatibility)
        if let savedMode = UserDefaults.standard.string(forKey: "editorLayoutMode"),
           let mode = EditorLayoutMode(rawValue: savedMode) {
            self.layoutMode = mode
        } else {
            self.layoutMode = .split
        }

        // Load current line highlighting preference (default: true)
        self.highlightCurrentLine = UserDefaults.standard.object(forKey: "highlightCurrentLine") as? Bool ?? true

        // Load inspector visibility preference (default: false)
        self.isInspectorVisible = UserDefaults.standard.object(forKey: "isInspectorVisible") as? Bool ?? false

        // Try to load previously opened site
        Task {
            await loadSavedSite()
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
            // Create site
            let site = HugoSite(rootURL: url)

            // Validate it's a Hugo site
            guard site.isValid else {
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

            print("Loaded Hugo site: \(site.displayName)")
            print("Found \(nodes.count) markdown files")

        } catch {
            errorMessage = "Failed to load site: \(error.localizedDescription)"
            print("Error loading site: \(error)")
        }

        isLoading = false
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
    }

    // MARK: - File Selection

    /// Select a file node
    func selectNode(_ node: FileNode?) {
        selectedNode = node
        selectedFileID = node?.id

        // Load file content if it's a markdown file
        if let node = node, node.isMarkdownFile {
            Task {
                await loadFileContent(for: node)
            }
        }
    }

    // MARK: - Quick Open

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

    /// Toggle Quick Open dialog
    func toggleQuickOpen() {
        isQuickOpenVisible.toggle()
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
        Task {
            try? await Task.sleep(for: .seconds(savedIndicatorDuration))
            // Only remove if the timestamp hasn't been updated
            if let savedDate = recentlySavedFileIDs[nodeID],
               Date().timeIntervalSince(savedDate) >= savedIndicatorDuration {
                recentlySavedFileIDs.removeValue(forKey: nodeID)
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

    /// Load content for a file node
    private func loadFileContent(for node: FileNode) async {
        do {
            let file = try await fileSystemService.readContentFile(at: node.url)
            node.contentFile = file
        } catch {
            errorMessage = "Failed to load file: \(error.localizedDescription)"
            print("Error loading file content: \(error)")
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

            print("Saved file: \(node.name)")
            return true
        } catch {
            errorMessage = "Failed to save file: \(error.localizedDescription)"
            print("Error saving file: \(error)")
            return false
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
            print("Error creating markdown file: \(error)")
        }
    }

    /// Reload current site
    func reloadSite() async {
        guard let site = site else { return }
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
            print("Error reloading file: \(error)")
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
            print("Error renaming file: \(error)")
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
            print("Error duplicating file: \(error)")
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
            print("Error moving to trash: \(error)")
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
            print("Error creating folder: \(error)")
        }
    }
}
