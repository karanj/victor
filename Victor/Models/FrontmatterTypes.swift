import Foundation

// MARK: - Build Options

/// Build options for page rendering
struct BuildOptions: Equatable {
    enum ListOption: String, CaseIterable, Codable {
        case always
        case local
        case never

        var description: String {
            switch self {
            case .always: return "Include in all page lists"
            case .local: return "Include only in local lists"
            case .never: return "Never include in lists"
            }
        }
    }

    enum RenderOption: String, CaseIterable, Codable {
        case always
        case link
        case never

        var description: String {
            switch self {
            case .always: return "Always render to disk"
            case .link: return "Create link only, don't render"
            case .never: return "Never render"
            }
        }
    }

    var list: ListOption = .always
    var render: RenderOption = .always
    var publishResources: Bool = true

    /// Check if this represents the default values
    var isDefault: Bool {
        list == .always && render == .always && publishResources == true
    }
}

// MARK: - Sitemap Config

/// Sitemap configuration for a page
struct SitemapConfig: Equatable {
    enum ChangeFreq: String, CaseIterable, Codable {
        case always
        case hourly
        case daily
        case weekly
        case monthly
        case yearly
        case never

        var description: String {
            switch self {
            case .always: return "Always (changes constantly)"
            case .hourly: return "Hourly"
            case .daily: return "Daily"
            case .weekly: return "Weekly"
            case .monthly: return "Monthly"
            case .yearly: return "Yearly"
            case .never: return "Never (archived content)"
            }
        }
    }

    var changefreq: ChangeFreq?
    var priority: Double?  // 0.0 to 1.0
    var disable: Bool = false

    /// Check if this represents the default/empty values
    var isEmpty: Bool {
        changefreq == nil && priority == nil && !disable
    }
}

// MARK: - Menu Entry

/// Menu entry configuration for adding page to Hugo menus
struct MenuEntry: Identifiable, Equatable {
    let id: UUID
    var menuName: String  // e.g., "main", "footer"
    var name: String?     // Display name (defaults to page title)
    var weight: Int?      // Position in menu
    var parent: String?   // Parent menu item identifier
    var identifier: String? // Unique identifier for this entry
    var pre: String?      // HTML before menu text
    var post: String?     // HTML after menu text
    var title: String?    // Tooltip text
    var params: [String: String] = [:]  // Additional parameters

    init(
        id: UUID = UUID(),
        menuName: String,
        name: String? = nil,
        weight: Int? = nil,
        parent: String? = nil,
        identifier: String? = nil,
        pre: String? = nil,
        post: String? = nil,
        title: String? = nil,
        params: [String: String] = [:]
    ) {
        self.id = id
        self.menuName = menuName
        self.name = name
        self.weight = weight
        self.parent = parent
        self.identifier = identifier
        self.pre = pre
        self.post = post
        self.title = title
        self.params = params
    }
}

// MARK: - Resource Config

/// Page resource configuration (for images, PDFs, etc.)
struct ResourceConfig: Identifiable, Equatable {
    let id: UUID
    var src: String       // Glob pattern for matching files
    var name: String?     // Resource name
    var title: String?    // Resource title
    var params: [String: String] = [:]  // Additional parameters (alt, credits, etc.)

    init(
        id: UUID = UUID(),
        src: String,
        name: String? = nil,
        title: String? = nil,
        params: [String: String] = [:]
    ) {
        self.id = id
        self.src = src
        self.name = name
        self.title = title
        self.params = params
    }
}

// MARK: - Cascade Target

/// Target configuration for cascade values
struct CascadeTarget: Equatable {
    var path: String?        // Glob pattern for path matching
    var kind: String?        // Page kind: page, section, home, taxonomy, term
    var lang: String?        // Language code
    var environment: String? // Hugo environment

    /// Check if this represents an empty target
    var isEmpty: Bool {
        path == nil && kind == nil && lang == nil && environment == nil
    }
}

// MARK: - Cascade Entry

/// Cascade entry for value inheritance
struct CascadeEntry: Identifiable, Equatable {
    let id: UUID
    var values: [String: Any]
    var target: CascadeTarget?

    init(
        id: UUID = UUID(),
        values: [String: Any] = [:],
        target: CascadeTarget? = nil
    ) {
        self.id = id
        self.values = values
        self.target = target
    }

    static func == (lhs: CascadeEntry, rhs: CascadeEntry) -> Bool {
        lhs.id == rhs.id &&
        NSDictionary(dictionary: lhs.values).isEqual(to: rhs.values) &&
        lhs.target == rhs.target
    }
}

// MARK: - Custom Field

/// Represents a custom frontmatter field with type information
struct CustomField: Identifiable, Equatable {
    let id: UUID
    var key: String
    var value: CustomFieldValue

    init(id: UUID = UUID(), key: String, value: CustomFieldValue) {
        self.id = id
        self.key = key
        self.value = value
    }
}

/// Supported types for custom frontmatter fields
enum CustomFieldValue: Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case stringArray([String])
    case dictionary([String: Any])

    var displayValue: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        case .stringArray(let arr): return arr.joined(separator: ", ")
        case .dictionary: return "[Dictionary]"
        }
    }

    var typeLabel: String {
        switch self {
        case .string: return "String"
        case .int: return "Integer"
        case .double: return "Number"
        case .bool: return "Boolean"
        case .stringArray: return "List"
        case .dictionary: return "Object"
        }
    }

    /// Convert to Any for serialization
    var anyValue: Any {
        switch self {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .stringArray(let arr): return arr
        case .dictionary(let dict): return dict
        }
    }

    /// Create from Any value
    static func from(_ value: Any) -> CustomFieldValue {
        if let s = value as? String {
            return .string(s)
        } else if let i = value as? Int {
            return .int(i)
        } else if let d = value as? Double {
            return .double(d)
        } else if let b = value as? Bool {
            return .bool(b)
        } else if let arr = value as? [String] {
            return .stringArray(arr)
        } else if let dict = value as? [String: Any] {
            return .dictionary(dict)
        } else {
            // Fallback: convert to string
            return .string(String(describing: value))
        }
    }

    static func == (lhs: CustomFieldValue, rhs: CustomFieldValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let l), .string(let r)): return l == r
        case (.int(let l), .int(let r)): return l == r
        case (.double(let l), .double(let r)): return l == r
        case (.bool(let l), .bool(let r)): return l == r
        case (.stringArray(let l), .stringArray(let r)): return l == r
        case (.dictionary(let l), .dictionary(let r)):
            return NSDictionary(dictionary: l).isEqual(to: r)
        default: return false
        }
    }
}

// MARK: - Common Output Formats

/// Common Hugo output formats
enum OutputFormat: String, CaseIterable {
    case html = "html"
    case amp = "amp"
    case json = "json"
    case rss = "rss"
    case calendar = "calendar"
    case robots = "robots"

    var displayName: String {
        switch self {
        case .html: return "HTML"
        case .amp: return "AMP"
        case .json: return "JSON"
        case .rss: return "RSS"
        case .calendar: return "Calendar"
        case .robots: return "Robots"
        }
    }
}

// MARK: - Common Menus

/// Common Hugo menu names
enum CommonMenu: String, CaseIterable {
    case main = "main"
    case footer = "footer"
    case sidebar = "sidebar"
    case social = "social"

    var displayName: String {
        rawValue.capitalized
    }
}
