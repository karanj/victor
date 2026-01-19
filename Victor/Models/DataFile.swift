import Foundation

/// Supported data file formats in Hugo's data/ directory
enum DataFormat: String, CaseIterable {
    case yaml
    case json
    case toml

    /// File extensions for this format
    var extensions: [String] {
        switch self {
        case .yaml: return ["yaml", "yml"]
        case .json: return ["json"]
        case .toml: return ["toml"]
        }
    }

    /// Detect format from file URL
    static func from(url: URL) -> DataFormat? {
        let ext = url.pathExtension.lowercased()
        for format in DataFormat.allCases {
            if format.extensions.contains(ext) {
                return format
            }
        }
        return nil
    }

    /// Display name for the format
    var displayName: String {
        rawValue.uppercased()
    }
}

/// Represents an item in array-based data files
struct DataItem: Identifiable {
    let id: UUID
    var data: [String: Any]

    init(data: [String: Any]) {
        self.id = UUID()
        self.data = data
    }
}

/// Represents a data file (YAML/JSON/TOML) in Hugo's data/ directory
@Observable
class DataFile: EditableFile {
    let id: UUID
    let url: URL
    let format: DataFormat

    /// The parsed data structure (dictionary or array)
    var data: Any

    /// Original raw content for change detection
    private var originalContent: String

    /// Current raw content (serialized from data)
    var rawContent: String

    /// Last modification date of the file
    var lastModified: Date

    /// Whether the root data structure is an array
    var isArrayRoot: Bool {
        data is [Any]
    }

    /// Whether there are unsaved changes
    var hasUnsavedChanges: Bool {
        rawContent != originalContent
    }

    /// File name without path
    var fileName: String {
        url.lastPathComponent
    }

    /// Relative path from the data directory
    var relativePath: String = ""

    // MARK: - Initialization

    init(url: URL, format: DataFormat, data: Any, rawContent: String, lastModified: Date = Date()) {
        self.id = UUID()
        self.url = url
        self.format = format
        self.data = data
        self.rawContent = rawContent
        self.originalContent = rawContent
        self.lastModified = lastModified
    }

    // MARK: - Data Access

    /// Access data as a dictionary (returns nil if array root)
    var dataDictionary: [String: Any]? {
        data as? [String: Any]
    }

    /// Access data as an array (returns nil if dictionary root)
    var dataArray: [Any]? {
        data as? [Any]
    }

    /// Get array items as DataItem objects for editing
    var dataItems: [DataItem] {
        guard let array = dataArray else { return [] }
        return array.compactMap { item -> DataItem? in
            guard let dict = item as? [String: Any] else { return nil }
            return DataItem(data: dict)
        }
    }

    // MARK: - State Management

    /// Mark the file as saved (updates original content)
    func markAsSaved() {
        originalContent = rawContent
    }

    /// Update the raw content and mark original for change tracking
    func updateRawContent(_ content: String) {
        rawContent = content
    }

    // MARK: - Hashable & Equatable
    // Provided by EditableFile protocol
}
