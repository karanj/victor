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

    /// The type of file (computed from extension)
    var fileType: FileType {
        isDirectory ? .binary : FileType(url: url)
    }

    /// The Hugo role of this node (for top-level directories)
    var hugoRole: HugoRole?

    /// Whether this is a Hugo config file
    var isConfigFile: Bool {
        !isDirectory && HugoSiteStructure.isConfigFile(filename: name)
    }

    /// Associated content file (only for .md files in content directory)
    var contentFile: ContentFile?

    /// Associated text file (for non-markdown editable text files)
    var textFile: TextFile?

    /// Display name
    var name: String {
        url.lastPathComponent
    }

    /// Whether this is a markdown file
    var isMarkdownFile: Bool {
        fileType == .markdown
    }

    /// Whether this file can be edited
    var isEditable: Bool {
        !isDirectory && fileType.isEditable
    }

    /// Whether this file supports preview
    var isPreviewable: Bool {
        fileType.isPreviewable
    }

    init(url: URL, isDirectory: Bool, isPageBundle: Bool = false, hugoRole: HugoRole? = nil) {
        self.id = UUID()
        self.url = url
        self.isDirectory = isDirectory
        self.isPageBundle = isPageBundle
        self.hugoRole = hugoRole
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
