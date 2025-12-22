import Foundation
import SwiftUI

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

    /// Current editing content (for live preview)
    var currentEditingContent: String = ""

    /// Live preview enabled state
    var isLivePreviewEnabled: Bool = false

    /// Auto-save enabled state (persisted)
    var isAutoSaveEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAutoSaveEnabled, forKey: "isAutoSaveEnabled")
        }
    }

    /// Loading state
    var isLoading = false

    /// Error message
    var errorMessage: String?

    /// Search query
    var searchQuery = ""

    /// Trigger to focus search field
    var shouldFocusSearch = false

    /// File system service
    private let fileSystemService = FileSystemService.shared

    /// Filtered file nodes based on search (recursively searches tree)
    var filteredNodes: [FileNode] {
        guard !searchQuery.isEmpty else { return fileNodes }
        return filterNodesRecursively(fileNodes, query: searchQuery)
    }

    /// Recursively filter nodes and include parent folders if children match
    private func filterNodesRecursively(_ nodes: [FileNode], query: String) -> [FileNode] {
        var filtered: [FileNode] = []

        for node in nodes {
            if node.isDirectory {
                // Recursively filter children
                let filteredChildren = filterNodesRecursively(node.children, query: query)

                if !filteredChildren.isEmpty {
                    // Include directory if it has matching children
                    let dirCopy = FileNode(url: node.url, isDirectory: true)
                    dirCopy.children = filteredChildren
                    dirCopy.isExpanded = true // Auto-expand when filtering
                    filtered.append(dirCopy)
                } else if node.name.localizedCaseInsensitiveContains(query) {
                    // Include directory if its name matches
                    filtered.append(node)
                }
            } else {
                // Include file if name matches
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
}
