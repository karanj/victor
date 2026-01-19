import Foundation

/// Protocol for all editable file models in Victor
/// Provides consistent interface for change tracking and file operations
protocol EditableFile: AnyObject, Observable, Identifiable, Hashable {
    var id: UUID { get }
    var url: URL { get }
    var hasUnsavedChanges: Bool { get }

    /// Mark the current state as saved (reset change tracking)
    func markAsSaved()

    /// File name without path
    var fileName: String { get }
}

// Default implementations
extension EditableFile {
    var fileName: String {
        url.lastPathComponent
    }

    // Hashable conformance based on id
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
