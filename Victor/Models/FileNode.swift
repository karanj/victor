import Foundation

/// Represents a node in the file tree (file or directory)
@Observable
class FileNode: Identifiable, Hashable {
    let id: UUID
    var url: URL
    let isDirectory: Bool
    /// Whether this is a Hugo page bundle (directory with index.md/_index.md)
    /// Cached at creation time to avoid file I/O on main thread
    let isPageBundle: Bool
    var isExpanded: Bool = false
    var children: [FileNode] = []
    weak var parent: FileNode?

    /// Associated content file (only for .md files)
    var contentFile: ContentFile?

    /// Display name
    var name: String {
        url.lastPathComponent
    }

    /// Whether this is a markdown file
    var isMarkdownFile: Bool {
        !isDirectory && url.pathExtension.lowercased() == "md"
    }

    init(url: URL, isDirectory: Bool, isPageBundle: Bool = false) {
        self.id = UUID()
        self.url = url
        self.isDirectory = isDirectory
        self.isPageBundle = isPageBundle
    }

    // MARK: - Hashable & Equatable

    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Recursively find a node by URL
    func findNode(url: URL) -> FileNode? {
        if self.url == url {
            return self
        }

        for child in children {
            if let found = child.findNode(url: url) {
                return found
            }
        }

        return nil
    }

    /// Recursively find a node by ID
    func findNode(id: UUID) -> FileNode? {
        if self.id == id {
            return self
        }

        for child in children {
            if let found = child.findNode(id: id) {
                return found
            }
        }

        return nil
    }

    /// Recursively find a node by ID in a collection of root nodes
    static func findNode(id: UUID, in nodes: [FileNode]) -> FileNode? {
        for node in nodes {
            if let found = node.findNode(id: id) {
                return found
            }
        }
        return nil
    }

    /// Add a child node
    func addChild(_ child: FileNode) {
        child.parent = self
        children.append(child)
        sortChildren()
    }

    /// Sort children: directories first, then alphabetically
    func sortChildren() {
        children.sort { lhs, rhs in
            // Directories come before files
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            // Alphabetically within same type
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Get the index file for a page bundle (index.md or _index.md)
    var indexFile: FileNode? {
        guard isPageBundle else { return nil }
        return children.first { child in
            let name = child.name.lowercased()
            return name == "index.md" || name == "_index.md"
        }
    }
}
