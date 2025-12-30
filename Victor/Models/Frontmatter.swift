import Foundation

/// Format of the frontmatter
enum FrontmatterFormat: String, CaseIterable {
    case yaml
    case toml
    case json

    var delimiter: String {
        switch self {
        case .yaml: return "---"
        case .toml: return "+++"
        case .json: return ""
        }
    }

}

/// Represents Hugo frontmatter metadata - Enhanced version
/// Supports the full range of Hugo's predefined fields plus custom fields
@Observable
class Frontmatter {
    /// Raw frontmatter content including delimiters
    var rawContent: String

    /// Detected format
    var format: FrontmatterFormat

    // MARK: - Essential Fields

    /// Page title
    var title: String?

    /// Creation/publication date
    var date: Date?

    /// Mark as draft (won't publish)
    var isDraft: Bool?

    /// Meta description for SEO
    var description: String?

    /// Taxonomy tags
    var tags: [String]?

    /// Taxonomy categories
    var categories: [String]?

    // MARK: - Publishing Fields

    /// Future publish date (content won't appear until this date)
    var publishDate: Date?

    /// Expiration date (content hidden after this date)
    var expiryDate: Date?

    /// Last modification date
    var lastmod: Date?

    /// Ordering weight (lower = first)
    var weight: Int?

    // MARK: - URL Fields

    /// Override URL slug (last part of URL)
    var slug: String?

    /// Override entire URL path
    var url: String?

    /// Redirect URLs to this page
    var aliases: [String]?

    // MARK: - SEO Fields

    /// SEO keywords
    var keywords: [String]?

    /// Custom summary/teaser text
    var summary: String?

    /// Short title for links/menus
    var linkTitle: String?

    // MARK: - Layout Fields

    /// Content type override
    var type: String?

    /// Custom layout template
    var layout: String?

    // MARK: - Flags

    /// Create headless bundle (no page generated)
    var headless: Bool?

    /// CJK content flag (affects word count)
    var isCJKLanguage: Bool?

    /// Content format override (markdown, html, etc.)
    var markup: String?

    /// Link translations across languages
    var translationKey: String?

    // MARK: - Complex Fields

    /// Menu entries for this page
    var menus: [MenuEntry] = []

    /// Build options
    var build: BuildOptions?

    /// Sitemap configuration
    var sitemap: SitemapConfig?

    /// Output formats to generate
    var outputs: [String]?

    /// Page resource configurations
    var resources: [ResourceConfig] = []

    /// Cascade configurations for value inheritance
    var cascade: [CascadeEntry] = []

    // MARK: - Custom Parameters

    /// Custom fields in the params section
    var params: [String: Any] = [:]

    /// Other custom fields at root level (legacy support)
    var customFields: [String: Any] = [:]

    // MARK: - Initialization

    init(rawContent: String, format: FrontmatterFormat = .yaml) {
        self.rawContent = rawContent
        self.format = format
    }

    /// Detect frontmatter format from delimiters
    static func detectFormat(from content: String) -> FrontmatterFormat? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("---") {
            return .yaml
        } else if trimmed.hasPrefix("+++") {
            return .toml
        } else if trimmed.hasPrefix("{") {
            return .json
        }
        return nil
    }

    /// Create a snapshot of the current frontmatter state for change detection
    func snapshot() -> FrontmatterSnapshot {
        FrontmatterSnapshot(
            // Essential
            title: title,
            date: date,
            isDraft: isDraft,
            description: description,
            tags: tags,
            categories: categories,
            // Publishing
            publishDate: publishDate,
            expiryDate: expiryDate,
            lastmod: lastmod,
            weight: weight,
            // URL
            slug: slug,
            url: url,
            aliases: aliases,
            // SEO
            keywords: keywords,
            summary: summary,
            linkTitle: linkTitle,
            // Layout
            type: type,
            layout: layout,
            // Flags
            headless: headless,
            isCJKLanguage: isCJKLanguage,
            markup: markup,
            translationKey: translationKey,
            // Complex
            menus: menus,
            build: build,
            sitemap: sitemap,
            outputs: outputs,
            resources: resources,
            // Custom
            params: params,
            customFields: customFields
        )
    }

    // MARK: - Convenience Methods

    /// Check if the page has any menu entries
    var hasMenus: Bool { !menus.isEmpty }

    /// Check if the page has any resources configured
    var hasResources: Bool { !resources.isEmpty }

    /// Check if the page has custom params
    var hasParams: Bool { !params.isEmpty }

    /// Check if the page has any custom fields
    var hasCustomFields: Bool { !customFields.isEmpty }

    /// Check if sitemap is configured
    var hasSitemap: Bool { sitemap != nil && !(sitemap?.isEmpty ?? true) }

    /// Check if build options are configured
    var hasBuildOptions: Bool { build != nil && !(build?.isDefault ?? true) }

    /// Get all menu names this page belongs to
    var menuNames: [String] {
        menus.map { $0.menuName }
    }
}

// MARK: - Frontmatter Snapshot

/// Immutable snapshot of frontmatter state for change detection
struct FrontmatterSnapshot: Equatable {
    // Essential
    let title: String?
    let date: Date?
    let isDraft: Bool?
    let description: String?
    let tags: [String]?
    let categories: [String]?
    // Publishing
    let publishDate: Date?
    let expiryDate: Date?
    let lastmod: Date?
    let weight: Int?
    // URL
    let slug: String?
    let url: String?
    let aliases: [String]?
    // SEO
    let keywords: String?
    let summary: String?
    let linkTitle: String?
    // Layout
    let type: String?
    let layout: String?
    // Flags
    let headless: Bool?
    let isCJKLanguage: Bool?
    let markup: String?
    let translationKey: String?
    // Complex
    let menus: [MenuEntry]
    let build: BuildOptions?
    let sitemap: SitemapConfig?
    let outputs: [String]?
    let resources: [ResourceConfig]
    // Custom
    let params: [String: Any]
    let customFields: [String: Any]

    // Custom initializer to handle keywords as array
    init(
        title: String?,
        date: Date?,
        isDraft: Bool?,
        description: String?,
        tags: [String]?,
        categories: [String]?,
        publishDate: Date?,
        expiryDate: Date?,
        lastmod: Date?,
        weight: Int?,
        slug: String?,
        url: String?,
        aliases: [String]?,
        keywords: [String]?,
        summary: String?,
        linkTitle: String?,
        type: String?,
        layout: String?,
        headless: Bool?,
        isCJKLanguage: Bool?,
        markup: String?,
        translationKey: String?,
        menus: [MenuEntry],
        build: BuildOptions?,
        sitemap: SitemapConfig?,
        outputs: [String]?,
        resources: [ResourceConfig],
        params: [String: Any],
        customFields: [String: Any]
    ) {
        self.title = title
        self.date = date
        self.isDraft = isDraft
        self.description = description
        self.tags = tags
        self.categories = categories
        self.publishDate = publishDate
        self.expiryDate = expiryDate
        self.lastmod = lastmod
        self.weight = weight
        self.slug = slug
        self.url = url
        self.aliases = aliases
        self.keywords = keywords?.joined(separator: ",")
        self.summary = summary
        self.linkTitle = linkTitle
        self.type = type
        self.layout = layout
        self.headless = headless
        self.isCJKLanguage = isCJKLanguage
        self.markup = markup
        self.translationKey = translationKey
        self.menus = menus
        self.build = build
        self.sitemap = sitemap
        self.outputs = outputs
        self.resources = resources
        self.params = params
        self.customFields = customFields
    }

    static func == (lhs: FrontmatterSnapshot, rhs: FrontmatterSnapshot) -> Bool {
        // Essential
        lhs.title == rhs.title &&
        lhs.date == rhs.date &&
        lhs.isDraft == rhs.isDraft &&
        lhs.description == rhs.description &&
        lhs.tags == rhs.tags &&
        lhs.categories == rhs.categories &&
        // Publishing
        lhs.publishDate == rhs.publishDate &&
        lhs.expiryDate == rhs.expiryDate &&
        lhs.lastmod == rhs.lastmod &&
        lhs.weight == rhs.weight &&
        // URL
        lhs.slug == rhs.slug &&
        lhs.url == rhs.url &&
        lhs.aliases == rhs.aliases &&
        // SEO
        lhs.keywords == rhs.keywords &&
        lhs.summary == rhs.summary &&
        lhs.linkTitle == rhs.linkTitle &&
        // Layout
        lhs.type == rhs.type &&
        lhs.layout == rhs.layout &&
        // Flags
        lhs.headless == rhs.headless &&
        lhs.isCJKLanguage == rhs.isCJKLanguage &&
        lhs.markup == rhs.markup &&
        lhs.translationKey == rhs.translationKey &&
        // Complex
        lhs.menus == rhs.menus &&
        lhs.build == rhs.build &&
        lhs.sitemap == rhs.sitemap &&
        lhs.outputs == rhs.outputs &&
        lhs.resources == rhs.resources &&
        // Custom
        NSDictionary(dictionary: lhs.params).isEqual(to: rhs.params) &&
        NSDictionary(dictionary: lhs.customFields).isEqual(to: rhs.customFields)
    }
}
