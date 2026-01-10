import Foundation

// MARK: - Template Type

/// Represents the type of Hugo template
enum TemplateType: String, CaseIterable, Identifiable {
    case base       // baseof.html - base template with blocks
    case single     // single.html - single page template
    case list       // list.html - list/section template
    case partial    // partials/*.html - reusable template fragments
    case shortcode  // shortcodes/*.html - content shortcodes
    case taxonomy   // taxonomy.html, terms.html
    case home       // index.html - homepage template
    case section    // section.html - section list template
    case other      // Other template types

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .base: return "Base Template"
        case .single: return "Single Page"
        case .list: return "List Template"
        case .partial: return "Partial"
        case .shortcode: return "Shortcode"
        case .taxonomy: return "Taxonomy"
        case .home: return "Homepage"
        case .section: return "Section"
        case .other: return "Template"
        }
    }

    var systemImage: String {
        switch self {
        case .base: return "square.stack.3d.up"
        case .single: return "doc.text"
        case .list: return "list.bullet.rectangle"
        case .partial: return "puzzlepiece"
        case .shortcode: return "curlybraces"
        case .taxonomy: return "tag"
        case .home: return "house"
        case .section: return "folder"
        case .other: return "doc"
        }
    }

    var description: String {
        switch self {
        case .base: return "Base template that defines the overall page structure with blocks"
        case .single: return "Template for rendering single content pages"
        case .list: return "Template for rendering lists of content"
        case .partial: return "Reusable template fragment that can be included in other templates"
        case .shortcode: return "Custom shortcode that can be used in content files"
        case .taxonomy: return "Template for taxonomy term pages"
        case .home: return "Template for the site homepage"
        case .section: return "Template for section list pages"
        case .other: return "Other Hugo template file"
        }
    }
}

// MARK: - Template Block

/// Represents a block definition or usage in a template
struct TemplateBlock: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let isDefinition: Bool  // true if {{ define "name" }}, false if {{ block "name" }}
    let lineNumber: Int

    var displayType: String {
        isDefinition ? "defines" : "uses"
    }
}

// MARK: - Template Partial Reference

/// Represents a partial template reference
struct PartialReference: Identifiable, Hashable {
    let id = UUID()
    let name: String           // e.g., "header.html" or "meta/og.html"
    let lineNumber: Int
    let hasContext: Bool       // Whether context is passed (. or custom)

    var shortName: String {
        // Remove .html extension for display
        name.replacingOccurrences(of: ".html", with: "")
    }
}

// MARK: - Template Function Usage

/// Represents a Go template function used in the template
struct TemplateFunctionUsage: Identifiable, Hashable {
    let id = UUID()
    let name: String           // e.g., "range", "if", "with", "partial"
    let count: Int             // Number of times used

    var isControlFlow: Bool {
        ["if", "else", "with", "range", "end"].contains(name)
    }

    var isBuiltin: Bool {
        Self.builtinFunctions.contains(name)
    }

    static let builtinFunctions: Set<String> = [
        // Control flow
        "if", "else", "with", "range", "end", "block", "define", "template",
        // Comparison
        "eq", "ne", "lt", "le", "gt", "ge", "and", "or", "not",
        // String functions
        "print", "printf", "println", "len", "index", "slice",
        "lower", "upper", "title", "trim", "replace", "split",
        // Hugo-specific
        "partial", "partialCached", "return",
        "safeHTML", "safeCSS", "safeJS", "safeURL",
        "markdownify", "plainify", "htmlUnescape",
        "absURL", "relURL", "ref", "relref",
        "dict", "slice", "append", "merge",
        "isset", "default", "cond",
        "now", "dateFormat", "time",
        "readDir", "readFile", "getenv",
        "resources", "assets"
    ]
}

// MARK: - Template Variable

/// Represents a variable accessed in the template
struct TemplateVariable: Identifiable, Hashable {
    let id = UUID()
    let name: String           // e.g., ".Title", ".Content", ".Params.author"
    let count: Int             // Number of times accessed

    var isPageVariable: Bool {
        name.hasPrefix(".") && !name.hasPrefix(".$")
    }

    var category: VariableCategory {
        if name.hasPrefix(".Params") { return .params }
        if name.hasPrefix(".Site") { return .site }
        if name.hasPrefix(".Page") || isCommonPageVar { return .page }
        if name.hasPrefix("$") { return .local }
        return .other
    }

    private var isCommonPageVar: Bool {
        let common = [".Title", ".Content", ".Summary", ".Date", ".Draft",
                      ".Permalink", ".RelPermalink", ".Type", ".Kind",
                      ".Section", ".Weight", ".Description", ".Keywords"]
        return common.contains(name) || name.hasPrefix(".") && !name.contains(".")
    }

    enum VariableCategory: String {
        case page = "Page"
        case site = "Site"
        case params = "Params"
        case local = "Local"
        case other = "Other"
    }
}

// MARK: - Template Metadata

/// Extracted metadata from a Hugo template
struct TemplateMetadata {
    var blocks: [TemplateBlock] = []
    var partials: [PartialReference] = []
    var functions: [TemplateFunctionUsage] = []
    var variables: [TemplateVariable] = []
    var hasBaseTemplate: Bool = false      // Uses {{ block }} (extends baseof)
    var definesBlocks: Bool = false        // Uses {{ define }} (can be extended)
    var shortcodesUsed: [String] = []      // {{ .Inner }}, shortcode patterns

    var isEmpty: Bool {
        blocks.isEmpty && partials.isEmpty && functions.isEmpty && variables.isEmpty
    }

    var blocksDefinedCount: Int {
        blocks.filter { $0.isDefinition }.count
    }

    var blocksUsedCount: Int {
        blocks.filter { !$0.isDefinition }.count
    }
}

// MARK: - Template Model

/// Represents a Hugo template file with parsed metadata
@Observable
class Template: Identifiable, Hashable {
    let id: UUID
    let url: URL
    var content: String
    var originalContent: String
    var metadata: TemplateMetadata

    /// The detected template type
    var templateType: TemplateType

    /// Whether this template is from a theme (vs layouts/)
    var isThemeTemplate: Bool

    /// The theme name if this is a theme template
    var themeName: String?

    init(
        url: URL,
        content: String,
        metadata: TemplateMetadata = TemplateMetadata(),
        templateType: TemplateType = .other,
        isThemeTemplate: Bool = false,
        themeName: String? = nil
    ) {
        self.id = UUID()
        self.url = url
        self.content = content
        self.originalContent = content
        self.metadata = metadata
        self.templateType = templateType
        self.isThemeTemplate = isThemeTemplate
        self.themeName = themeName
    }

    // MARK: - Computed Properties

    /// File name without extension
    var name: String {
        url.deletingPathExtension().lastPathComponent
    }

    /// Full file name with extension
    var fileName: String {
        url.lastPathComponent
    }

    /// Display name for the template
    var displayName: String {
        // For partials and shortcodes, show the path relative to their directory
        if templateType == .partial || templateType == .shortcode {
            return name
        }
        return fileName
    }

    /// Whether the template has unsaved changes
    var hasUnsavedChanges: Bool {
        content != originalContent
    }

    /// The relative path within layouts/ or themes/
    var relativePath: String {
        // Extract path relative to layouts/ or themes/
        let path = url.path
        // Check themes/ first - theme templates have /themes/ in their path
        // and we need to preserve the full path including theme name
        if let range = path.range(of: "/themes/") {
            // Include theme name in path: mytheme/layouts/partials/file.html
            return String(path[range.upperBound...])
        }
        // For site templates, extract path after /layouts/
        if let range = path.range(of: "/layouts/") {
            return String(path[range.upperBound...])
        }
        return fileName
    }

    /// Directory path relative to layouts/ (without prefix)
    var directoryPath: String {
        let components = relativePath.split(separator: "/").dropLast()
        return components.joined(separator: "/")
    }

    /// Full display path from site root for clear context
    /// e.g., "layouts/_default/single.html" or "themes/mytheme/layouts/partials/header.html"
    var fullDisplayPath: String {
        if isThemeTemplate {
            // Theme templates: themes/themename/layouts/...
            return "themes/\(relativePath)"
        } else {
            // Site templates: layouts/...
            return "layouts/\(relativePath)"
        }
    }

    /// Full directory path from site root (without filename)
    /// e.g., "layouts/_default" or "themes/mytheme/layouts/partials"
    var fullDirectoryPath: String {
        let components = fullDisplayPath.split(separator: "/").dropLast()
        return components.joined(separator: "/")
    }

    // MARK: - Hashable & Equatable

    static func == (lhs: Template, rhs: Template) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Methods

    /// Mark the template as saved (update original content)
    func markAsSaved() {
        originalContent = content
    }

    /// Revert to the original content
    func revertChanges() {
        content = originalContent
    }

    /// Detect template type from URL
    static func detectType(from url: URL) -> TemplateType {
        let fileName = url.deletingPathExtension().lastPathComponent.lowercased()
        let path = url.path.lowercased()

        // Check directory-based types first
        if path.contains("/partials/") {
            return .partial
        }
        if path.contains("/shortcodes/") {
            return .shortcode
        }

        // Check file name patterns
        switch fileName {
        case "baseof":
            return .base
        case "single":
            return .single
        case "list":
            return .list
        case "index":
            // Could be homepage or section index
            if path.contains("/_default/") || path.hasSuffix("/layouts/index.html") {
                return .home
            }
            return .section
        case "section":
            return .section
        case "taxonomy", "term", "terms":
            return .taxonomy
        case "home":
            return .home
        default:
            // Check for _default directory patterns
            if path.contains("/_default/") {
                if fileName.contains("single") { return .single }
                if fileName.contains("list") { return .list }
            }
            return .other
        }
    }
}

// MARK: - Template Collection Helpers

extension Array where Element == Template {
    /// Group templates by type
    var groupedByType: [TemplateType: [Template]] {
        Dictionary(grouping: self) { $0.templateType }
    }

    /// Group templates by directory
    var groupedByDirectory: [String: [Template]] {
        Dictionary(grouping: self) { $0.directoryPath }
    }

    /// Filter to only partials
    var partials: [Template] {
        filter { $0.templateType == .partial }
    }

    /// Filter to only shortcodes
    var shortcodes: [Template] {
        filter { $0.templateType == .shortcode }
    }

    /// Filter to only theme templates
    var themeTemplates: [Template] {
        filter { $0.isThemeTemplate }
    }

    /// Filter to only site templates (non-theme)
    var siteTemplates: [Template] {
        filter { !$0.isThemeTemplate }
    }
}
