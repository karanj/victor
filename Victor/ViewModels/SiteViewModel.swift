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

    /// Loading state
    var isLoading = false

    /// Error message
    var errorMessage: String?

    /// Search query
    var searchQuery = ""

    /// File system service
    private let fileSystemService = FileSystemService.shared

    /// Filtered file nodes based on search
    var filteredNodes: [FileNode] {
        guard !searchQuery.isEmpty else { return fileNodes }
        return fileNodes.filter { node in
            node.name.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    init() {
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

    /// Reload current site
    func reloadSite() async {
        guard let site = site else { return }
        await loadSite(from: site.rootURL)
    }
}
