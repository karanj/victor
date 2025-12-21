import Foundation

/// Represents a node in the file tree (file or directory)
@Observable
class FileNode: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let isDirectory: Bool
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

    /// Whether this is a Hugo page bundle (directory with index.md)
    var isPageBundle: Bool {
        guard isDirectory else { return false }
        let indexMD = url.appendingPathComponent("index.md")
        let underscoreIndexMD = url.appendingPathComponent("_index.md")
        return FileManager.default.fileExists(atPath: indexMD.path) ||
               FileManager.default.fileExists(atPath: underscoreIndexMD.path)
    }

    init(url: URL, isDirectory: Bool) {
        self.id = UUID()
        self.url = url
        self.isDirectory = isDirectory
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
}
