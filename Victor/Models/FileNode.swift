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

    /// Whether this is an asset directory (static/ or assets/)
    var isAssetDirectory: Bool {
        isDirectory && (hugoRole == .staticFiles || hugoRole == .assets)
    }

    /// Whether this is a data file (YAML/JSON/TOML in data/ directory)
    var isDataFile: Bool {
        guard !isDirectory else { return false }
        // Check if file type is a data format
        let isDataFormat = fileType == .yaml || fileType == .json || fileType == .toml
        guard isDataFormat else { return false }
        // Check if in data/ directory (walk up to find parent with data role)
        return isInDataDirectory
    }

    /// Check if this node is within the data/ directory
    private var isInDataDirectory: Bool {
        var current: FileNode? = parent
        while let node = current {
            if node.hugoRole == .data {
                return true
            }
            current = node.parent
        }
        return false
    }

    /// Whether this is a translation file (YAML/JSON/TOML in i18n/ directory)
    var isTranslationFile: Bool {
        guard !isDirectory else { return false }
        let isDataFormat = fileType == .yaml || fileType == .json || fileType == .toml
        guard isDataFormat else { return false }
        return isInI18nDirectory
    }

    /// Check if this node is within the i18n/ directory
    private var isInI18nDirectory: Bool {
        var current: FileNode? = parent
        while let node = current {
            if node.hugoRole == .i18n {
                return true
            }
            current = node.parent
        }
        return false
    }

    /// Whether this is a template file (HTML in layouts/ or themes/ directory)
    var isTemplateFile: Bool {
        guard !isDirectory else { return false }
        guard fileType == .html else { return false }
        return isInLayoutsDirectory || isInThemesDirectory
    }

    /// Check if this node is within the layouts/ directory
    private var isInLayoutsDirectory: Bool {
        if hugoRole == .layouts { return true }
        var current: FileNode? = parent
        while let node = current {
            if node.hugoRole == .layouts {
                return true
            }
            current = node.parent
        }
        return false
    }

    /// Check if this node is within the themes/ directory
    private var isInThemesDirectory: Bool {
        if hugoRole == .themes { return true }
        var current: FileNode? = parent
        while let node = current {
            if node.hugoRole == .themes {
                return true
            }
            current = node.parent
        }
        return false
    }

    /// Whether this is an archetype file (markdown in archetypes/ directory)
    var isArchetypeFile: Bool {
        guard !isDirectory else { return false }
        guard fileType == .markdown else { return false }
        return isInArchetypesDirectory
    }

    /// Check if this node is within the archetypes/ directory
    private var isInArchetypesDirectory: Bool {
        var current: FileNode? = parent
        while let node = current {
            if node.hugoRole == .archetypes {
                return true
            }
            current = node.parent
        }
        return false
    }

    /// Associated content file (only for .md files in content directory)
    var contentFile: ContentFile?

    /// Associated text file (for non-markdown editable text files)
    var textFile: TextFile?

    /// Lightweight status metadata (loaded when folder is expanded)
    /// This is separate from contentFile to allow status display without full file loading
    var statusMetadata: FileStatusMetadata?

    /// Computed status for display in sidebar (single status for backwards compatibility)
    /// Prefers full contentFile data if loaded, otherwise uses lightweight statusMetadata
    var contentStatus: ContentStatus? {
        // If full contentFile is loaded, derive from it (more accurate)
        if let contentFile = contentFile {
            return FileStatusMetadata(from: contentFile.frontmatter).status
        }
        // Otherwise use lightweight metadata
        return statusMetadata?.status
    }

    /// All applicable statuses for display in sidebar (e.g., draft AND scheduled)
    /// Prefers full contentFile data if loaded, otherwise uses lightweight statusMetadata
    var contentStatuses: [ContentStatus] {
        // If full contentFile is loaded, derive from it (more accurate)
        if let contentFile = contentFile {
            return FileStatusMetadata(from: contentFile.frontmatter).statuses
        }
        // Otherwise use lightweight metadata
        return statusMetadata?.statuses ?? []
    }

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
