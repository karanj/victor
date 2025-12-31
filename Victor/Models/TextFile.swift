import Foundation

/// Represents a plain text file (non-markdown)
@Observable
class TextFile: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let fileType: FileType
    var content: String
    var originalContent: String  // For change detection
    var lastModified: Date

    /// Whether there are unsaved changes
    var hasUnsavedChanges: Bool {
        content != originalContent
    }

    init(url: URL, content: String, lastModified: Date) {
        self.id = UUID()
        self.url = url
        self.fileType = FileType(url: url)
        self.content = content
        self.originalContent = content
        self.lastModified = lastModified
    }

    /// Mark the file as saved (updates original content)
    func markAsSaved() {
        originalContent = content
    }

    // MARK: - Hashable & Equatable

    static func == (lhs: TextFile, rhs: TextFile) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
