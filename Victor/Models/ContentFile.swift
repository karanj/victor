import Foundation

/// Represents a markdown content file in a Hugo site
@Observable
class ContentFile: Identifiable, Hashable {
    let id: UUID
    // `var`, not `let` (victor-rnm): SiteViewModel.renameFile updates this in
    // place so every direct reader (saveAllModifiedFiles, EditorViewModel's
    // auto-save debounce) sees the post-rename path instead of writing back
    // to a path that no longer exists.
    var url: URL
    var frontmatter: Frontmatter?
    var markdownContent: String
    var lastModified: Date

    /// Whether this file is marked as a draft
    var isDraft: Bool {
        frontmatter?.isDraft ?? false
    }

    /// File name
    var fileName: String {
        url.lastPathComponent
    }

    /// Relative path from the content directory
    var relativePath: String = ""

    /// Whether this is an index file (index.md or _index.md)
    var isIndexFile: Bool {
        let name = fileName.lowercased()
        return name == "index.md" || name == "_index.md"
    }

    init(url: URL, frontmatter: Frontmatter? = nil, markdownContent: String = "", lastModified: Date = Date()) {
        self.id = UUID()
        self.url = url
        self.frontmatter = frontmatter
        self.markdownContent = markdownContent
        self.lastModified = lastModified
    }

    // MARK: - Hashable & Equatable

    static func == (lhs: ContentFile, rhs: ContentFile) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Full content including frontmatter and markdown
    var fullContent: String {
        guard let frontmatter = frontmatter else {
            return markdownContent
        }

        return frontmatter.rawContent + "\n" + markdownContent
    }
}
