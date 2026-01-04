import Foundation
import AppKit

/// Represents a static asset file in a Hugo site
@Observable
class Asset: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let fileType: FileType
    let relativePath: String  // Path relative to static/ or assets/
    let isInAssetsDir: Bool   // true = assets/, false = static/

    // Lazy-loaded properties
    var thumbnail: NSImage?
    var fileSize: Int64?
    var dimensions: CGSize?   // For images
    var modificationDate: Date?

    /// Whether metadata has been loaded
    var isMetadataLoaded: Bool = false

    /// Generate markdown image syntax
    var markdownSyntax: String {
        let path = isInAssetsDir ? relativePath : "/\(relativePath)"
        let altText = url.deletingPathExtension().lastPathComponent
        return "![\(altText)](\(path))"
    }

    /// Generate Hugo figure shortcode
    var figureShortcode: String {
        let path = isInAssetsDir ? relativePath : "/\(relativePath)"
        return "{{< figure src=\"\(path)\" alt=\"\" caption=\"\" >}}"
    }

    /// Human-readable file size
    var formattedFileSize: String {
        guard let size = fileSize else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// Human-readable dimensions
    var formattedDimensions: String? {
        guard let dims = dimensions else { return nil }
        return "\(Int(dims.width)) × \(Int(dims.height))"
    }

    /// Location description
    var locationDescription: String {
        isInAssetsDir ? "assets/ (Hugo Pipes)" : "static/ (copied as-is)"
    }

    init(url: URL, relativePath: String, isInAssetsDir: Bool) {
        self.id = UUID()
        self.url = url
        self.fileType = FileType(url: url)
        self.relativePath = relativePath
        self.isInAssetsDir = isInAssetsDir
    }

    // MARK: - Hashable & Equatable

    static func == (lhs: Asset, rhs: Asset) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Asset Filter Types

enum AssetFilterType: String, CaseIterable, Identifiable {
    case all = "All"
    case images = "Images"
    case documents = "Documents"
    case other = "Other"

    var id: String { rawValue }

    func matches(_ asset: Asset) -> Bool {
        switch self {
        case .all:
            return true
        case .images:
            return asset.fileType == .image
        case .documents:
            return [.pdf, .plainText, .markdown].contains(asset.fileType)
        case .other:
            return asset.fileType != .image && asset.fileType != .pdf && asset.fileType != .plainText
        }
    }
}

// MARK: - Asset Sort Order

enum AssetSortOrder: String, CaseIterable, Identifiable {
    case name = "Name"
    case date = "Date"
    case size = "Size"
    case type = "Type"

    var id: String { rawValue }

    func compare(_ lhs: Asset, _ rhs: Asset) -> Bool {
        switch self {
        case .name:
            return lhs.url.lastPathComponent.localizedCaseInsensitiveCompare(rhs.url.lastPathComponent) == .orderedAscending
        case .date:
            return (lhs.modificationDate ?? .distantPast) > (rhs.modificationDate ?? .distantPast)
        case .size:
            return (lhs.fileSize ?? 0) > (rhs.fileSize ?? 0)
        case .type:
            return lhs.fileType.rawValue < rhs.fileType.rawValue
        }
    }
}

// MARK: - Asset View Mode

enum AssetViewMode: String, CaseIterable, Identifiable {
    case grid = "Grid"
    case list = "List"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}
