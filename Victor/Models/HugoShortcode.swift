import Foundation

// MARK: - Parameter Types

/// Types of parameters that shortcodes can accept
enum ShortcodeParameterType {
    case string
    case int
    case bool
    case enumeration([String])
}

/// A single parameter for a shortcode
struct ShortcodeParameter: Identifiable {
    let id: String
    let name: String
    let type: ShortcodeParameterType
    let isRequired: Bool
    let defaultValue: String?
    let placeholder: String
    let helpText: String

    init(
        name: String,
        type: ShortcodeParameterType = .string,
        isRequired: Bool = false,
        defaultValue: String? = nil,
        placeholder: String = "",
        helpText: String = ""
    ) {
        self.id = name
        self.name = name
        self.type = type
        self.isRequired = isRequired
        self.defaultValue = defaultValue
        self.placeholder = placeholder
        self.helpText = helpText
    }
}

// MARK: - Categories

/// Categories for organizing shortcodes in the picker
enum ShortcodeCategory: String, CaseIterable {
    case media = "Media"
    case code = "Code"
    case layout = "Layout"
    case links = "Links & Data"

    var icon: String {
        switch self {
        case .media: return "photo.stack"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .layout: return "rectangle.3.group"
        case .links: return "link"
        }
    }

    var shortcodes: [HugoShortcode] {
        HugoShortcode.allShortcodes.filter { $0.category == self }
    }
}

// MARK: - Shortcode Definition

/// Definition of a Hugo shortcode with all its metadata
struct HugoShortcode: Identifiable, Hashable {
    // Hashable conformance - use id as unique identifier
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: HugoShortcode, rhs: HugoShortcode) -> Bool {
        lhs.id == rhs.id
    }

    let id: String
    let name: String
    let icon: String
    let category: ShortcodeCategory
    let description: String
    let detailedHelp: String
    let parameters: [ShortcodeParameter]
    let usesMarkdownNotation: Bool  // {{% vs {{<
    let hasClosingTag: Bool
    let exampleUsage: String
    let isDeprecated: Bool
    let deprecationNote: String?

    init(
        id: String,
        name: String,
        icon: String,
        category: ShortcodeCategory,
        description: String,
        detailedHelp: String = "",
        parameters: [ShortcodeParameter] = [],
        usesMarkdownNotation: Bool = false,
        hasClosingTag: Bool = false,
        exampleUsage: String = "",
        isDeprecated: Bool = false,
        deprecationNote: String? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.category = category
        self.description = description
        self.detailedHelp = detailedHelp
        self.parameters = parameters
        self.usesMarkdownNotation = usesMarkdownNotation
        self.hasClosingTag = hasClosingTag
        self.exampleUsage = exampleUsage
        self.isDeprecated = isDeprecated
        self.deprecationNote = deprecationNote
    }

    /// Generate shortcode string from parameter values
    func generate(with values: [String: String], innerContent: String? = nil) -> String {
        let openBracket = usesMarkdownNotation ? "{{%" : "{{<"
        let closeBracket = usesMarkdownNotation ? "%}}" : ">}}"

        var params = parameters
            .compactMap { param -> String? in
                guard let value = values[param.name], !value.isEmpty else {
                    return nil
                }
                // Quote string values that contain spaces
                if value.contains(" ") || value.contains("\"") {
                    let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
                    return "\(param.name)=\"\(escaped)\""
                }
                return "\(param.name)=\(value)"
            }
            .joined(separator: " ")

        if !params.isEmpty {
            params = " " + params
        }

        if hasClosingTag {
            let content = innerContent ?? "content"
            let closeOpenBracket = usesMarkdownNotation ? "{{%" : "{{<"
            let closeCloseBracket = usesMarkdownNotation ? "%}}" : ">}}"
            return "\(openBracket) \(id)\(params) \(closeBracket)\n\(content)\n\(closeOpenBracket) /\(id) \(closeCloseBracket)"
        } else {
            return "\(openBracket) \(id)\(params) \(closeBracket)"
        }
    }

    /// Required parameters for this shortcode
    var requiredParameters: [ShortcodeParameter] {
        parameters.filter { $0.isRequired }
    }

    /// Optional parameters for this shortcode
    var optionalParameters: [ShortcodeParameter] {
        parameters.filter { !$0.isRequired }
    }
}

// MARK: - Shortcode Registry

extension HugoShortcode {
    static let allShortcodes: [HugoShortcode] = [
        // MARK: Media
        HugoShortcode(
            id: "figure",
            name: "Figure",
            icon: "photo.artframe",
            category: .media,
            description: "Insert an image with caption",
            detailedHelp: "Creates an HTML5 figure element with optional caption, link, and attribution. Perfect for blog post images.",
            parameters: [
                ShortcodeParameter(name: "src", type: .string, isRequired: true, placeholder: "/images/photo.jpg", helpText: "Image source URL"),
                ShortcodeParameter(name: "alt", type: .string, isRequired: true, placeholder: "Description of image", helpText: "Alternate text for accessibility"),
                ShortcodeParameter(name: "caption", type: .string, placeholder: "Image caption", helpText: "Caption text (supports Markdown)"),
                ShortcodeParameter(name: "title", type: .string, placeholder: "Title", helpText: "Heading inside figcaption"),
                ShortcodeParameter(name: "link", type: .string, placeholder: "https://...", helpText: "URL to link the image to"),
                ShortcodeParameter(name: "target", type: .enumeration(["_blank", "_self", "_parent", "_top"]), placeholder: "_blank", helpText: "Link target attribute"),
                ShortcodeParameter(name: "rel", type: .string, placeholder: "noopener", helpText: "Link relationship attribute"),
                ShortcodeParameter(name: "attr", type: .string, placeholder: "Photo by...", helpText: "Attribution text"),
                ShortcodeParameter(name: "attrlink", type: .string, placeholder: "https://...", helpText: "Attribution link URL"),
                ShortcodeParameter(name: "class", type: .string, placeholder: "rounded shadow", helpText: "CSS classes"),
                ShortcodeParameter(name: "width", type: .int, placeholder: "800", helpText: "Image width in pixels"),
                ShortcodeParameter(name: "height", type: .int, placeholder: "600", helpText: "Image height in pixels"),
                ShortcodeParameter(name: "loading", type: .enumeration(["eager", "lazy"]), defaultValue: "eager", helpText: "Loading behavior"),
            ],
            exampleUsage: "{{< figure src=\"/images/photo.jpg\" alt=\"A scenic view\" caption=\"Mountain landscape\" >}}"
        ),

        HugoShortcode(
            id: "youtube",
            name: "YouTube",
            icon: "play.rectangle.fill",
            category: .media,
            description: "Embed a YouTube video",
            detailedHelp: "Embeds a responsive YouTube video player. Just paste the video ID from the URL.",
            parameters: [
                ShortcodeParameter(name: "id", type: .string, isRequired: true, placeholder: "dQw4w9WgXcQ", helpText: "Video ID from YouTube URL"),
                ShortcodeParameter(name: "start", type: .int, placeholder: "30", helpText: "Start time in seconds"),
                ShortcodeParameter(name: "end", type: .int, placeholder: "120", helpText: "End time in seconds"),
                ShortcodeParameter(name: "autoplay", type: .bool, defaultValue: "false", helpText: "Auto-play video (will mute)"),
                ShortcodeParameter(name: "loop", type: .bool, defaultValue: "false", helpText: "Loop video indefinitely"),
                ShortcodeParameter(name: "mute", type: .bool, defaultValue: "false", helpText: "Mute audio"),
                ShortcodeParameter(name: "controls", type: .bool, defaultValue: "true", helpText: "Show video controls"),
                ShortcodeParameter(name: "class", type: .string, placeholder: "video-wrapper", helpText: "CSS class for wrapper"),
                ShortcodeParameter(name: "loading", type: .enumeration(["eager", "lazy"]), defaultValue: "eager", helpText: "Loading behavior"),
                ShortcodeParameter(name: "title", type: .string, placeholder: "Video title", helpText: "Accessibility title"),
            ],
            exampleUsage: "{{< youtube dQw4w9WgXcQ >}}"
        ),

        HugoShortcode(
            id: "vimeo",
            name: "Vimeo",
            icon: "play.rectangle",
            category: .media,
            description: "Embed a Vimeo video",
            detailedHelp: "Embeds a Vimeo video player. Use the video ID from the Vimeo URL.",
            parameters: [
                ShortcodeParameter(name: "id", type: .string, isRequired: true, placeholder: "55073825", helpText: "Video ID from Vimeo URL"),
                ShortcodeParameter(name: "allowFullScreen", type: .bool, defaultValue: "true", helpText: "Allow full screen mode"),
                ShortcodeParameter(name: "class", type: .string, placeholder: "video-wrapper", helpText: "CSS class for wrapper"),
                ShortcodeParameter(name: "loading", type: .enumeration(["eager", "lazy"]), defaultValue: "eager", helpText: "Loading behavior"),
                ShortcodeParameter(name: "title", type: .string, placeholder: "Video title", helpText: "Accessibility title"),
            ],
            exampleUsage: "{{< vimeo 55073825 >}}"
        ),

        HugoShortcode(
            id: "instagram",
            name: "Instagram",
            icon: "camera.fill",
            category: .media,
            description: "Embed an Instagram post",
            detailedHelp: "Embeds an Instagram post. Extract the post ID from the Instagram URL (the part after /p/).",
            parameters: [
                ShortcodeParameter(name: "id", type: .string, isRequired: true, placeholder: "CxOWiQNP2MO", helpText: "Post ID from Instagram URL"),
            ],
            exampleUsage: "{{< instagram CxOWiQNP2MO >}}"
        ),

        // MARK: Code
        HugoShortcode(
            id: "highlight",
            name: "Highlight",
            icon: "chevron.left.forwardslash.chevron.right",
            category: .code,
            description: "Syntax-highlighted code block",
            detailedHelp: "Insert syntax-highlighted code using the Chroma highlighter. Supports 250+ programming languages.",
            parameters: [
                ShortcodeParameter(name: "lang", type: .string, isRequired: true, placeholder: "swift", helpText: "Programming language"),
                ShortcodeParameter(name: "lineNos", type: .enumeration(["true", "false", "inline", "table"]), defaultValue: "false", helpText: "Show line numbers"),
                ShortcodeParameter(name: "lineNoStart", type: .int, defaultValue: "1", placeholder: "1", helpText: "Starting line number"),
                ShortcodeParameter(name: "hl_lines", type: .string, placeholder: "2-4 7", helpText: "Lines to highlight (e.g., \"2-4 7\")"),
                ShortcodeParameter(name: "style", type: .string, defaultValue: "monokai", placeholder: "monokai", helpText: "Color scheme"),
                ShortcodeParameter(name: "tabWidth", type: .int, defaultValue: "4", placeholder: "4", helpText: "Spaces per tab"),
                ShortcodeParameter(name: "wrapperClass", type: .string, placeholder: "code-block", helpText: "CSS class for wrapper"),
            ],
            hasClosingTag: true,
            exampleUsage: "{{< highlight swift \"linenos=inline\" >}}\nfunc greet() {\n    print(\"Hello!\")\n}\n{{< /highlight >}}"
        ),

        HugoShortcode(
            id: "gist",
            name: "Gist",
            icon: "doc.text",
            category: .code,
            description: "Embed a GitHub Gist",
            detailedHelp: "Embeds a GitHub Gist. You'll need the username and gist ID from the URL.",
            parameters: [
                ShortcodeParameter(name: "user", type: .string, isRequired: true, placeholder: "username", helpText: "GitHub username"),
                ShortcodeParameter(name: "gist", type: .string, isRequired: true, placeholder: "abc123def456", helpText: "Gist ID"),
                ShortcodeParameter(name: "file", type: .string, placeholder: "example.py", helpText: "Specific file to show"),
            ],
            exampleUsage: "{{< gist spf13 7896402 >}}",
            isDeprecated: true,
            deprecationNote: "Deprecated in Hugo v0.143.0. Consider creating a custom shortcode."
        ),

        // MARK: Layout
        HugoShortcode(
            id: "details",
            name: "Details",
            icon: "chevron.down.circle",
            category: .layout,
            description: "Collapsible content section",
            detailedHelp: "Creates an expandable/collapsible section. Great for FAQs, spoilers, or optional information.",
            parameters: [
                ShortcodeParameter(name: "summary", type: .string, isRequired: false, defaultValue: "Details", placeholder: "Click to expand", helpText: "Text shown when collapsed"),
                ShortcodeParameter(name: "open", type: .bool, defaultValue: "false", helpText: "Start expanded"),
                ShortcodeParameter(name: "class", type: .string, placeholder: "faq-item", helpText: "CSS class"),
                ShortcodeParameter(name: "name", type: .string, placeholder: "faq-group", helpText: "Group name (for accordion behavior)"),
            ],
            hasClosingTag: true,
            exampleUsage: "{{< details summary=\"Click to see more\" >}}\nHidden content here.\n{{< /details >}}"
        ),

        HugoShortcode(
            id: "qr",
            name: "QR Code",
            icon: "qrcode",
            category: .layout,
            description: "Generate a QR code",
            detailedHelp: "Generates a QR code image from text or URL. Useful for sharing links in print materials.",
            parameters: [
                ShortcodeParameter(name: "text", type: .string, isRequired: true, placeholder: "https://example.com", helpText: "Text or URL to encode"),
                ShortcodeParameter(name: "level", type: .enumeration(["low", "medium", "quartile", "high"]), defaultValue: "medium", helpText: "Error correction level"),
                ShortcodeParameter(name: "scale", type: .int, defaultValue: "4", placeholder: "4", helpText: "Pixels per module (min: 2)"),
                ShortcodeParameter(name: "alt", type: .string, placeholder: "QR code for...", helpText: "Alt text for accessibility"),
                ShortcodeParameter(name: "class", type: .string, placeholder: "qr-code", helpText: "CSS class"),
                ShortcodeParameter(name: "loading", type: .enumeration(["eager", "lazy"]), defaultValue: "eager", helpText: "Loading behavior"),
            ],
            exampleUsage: "{{< qr text=\"https://gohugo.io\" level=high />}}"
        ),

        // MARK: Links & Data
        HugoShortcode(
            id: "ref",
            name: "Reference Link",
            icon: "link",
            category: .links,
            description: "Insert absolute link to another page",
            detailedHelp: "Creates an absolute permalink to another page in your Hugo site. Hugo will error if the page doesn't exist.",
            parameters: [
                ShortcodeParameter(name: "path", type: .string, isRequired: true, placeholder: "/blog/my-post", helpText: "Path to target page"),
                ShortcodeParameter(name: "lang", type: .string, placeholder: "en", helpText: "Target language"),
                ShortcodeParameter(name: "outputFormat", type: .string, placeholder: "html", helpText: "Output format"),
            ],
            usesMarkdownNotation: true,
            exampleUsage: "[Read more]({{% ref \"/blog/my-post\" %}})"
        ),

        HugoShortcode(
            id: "relref",
            name: "Relative Link",
            icon: "link.badge.plus",
            category: .links,
            description: "Insert relative link to another page",
            detailedHelp: "Creates a relative permalink to another page. Useful for sites that may be hosted in subdirectories.",
            parameters: [
                ShortcodeParameter(name: "path", type: .string, isRequired: true, placeholder: "related-post.md", helpText: "Path to target page"),
                ShortcodeParameter(name: "lang", type: .string, placeholder: "en", helpText: "Target language"),
                ShortcodeParameter(name: "outputFormat", type: .string, placeholder: "html", helpText: "Output format"),
            ],
            usesMarkdownNotation: true,
            exampleUsage: "[Related]({{% relref \"related-post.md\" %}})"
        ),

        HugoShortcode(
            id: "param",
            name: "Parameter",
            icon: "slider.horizontal.3",
            category: .links,
            description: "Display a front matter parameter",
            detailedHelp: "Renders a value from the page's front matter or site configuration. Throws an error if not found.",
            parameters: [
                ShortcodeParameter(name: "name", type: .string, isRequired: true, placeholder: "author", helpText: "Parameter name (use dots for nested)"),
            ],
            usesMarkdownNotation: true,
            exampleUsage: "Written by {{% param author %}}"
        ),

        HugoShortcode(
            id: "x",
            name: "X Post",
            icon: "at",
            category: .links,
            description: "Embed an X (Twitter) post",
            detailedHelp: "Embeds a post from X (formerly Twitter). You need the username and post ID.",
            parameters: [
                ShortcodeParameter(name: "user", type: .string, isRequired: true, placeholder: "GoHugoIO", helpText: "X username"),
                ShortcodeParameter(name: "id", type: .string, isRequired: true, placeholder: "1453110110599868418", helpText: "Post ID"),
            ],
            exampleUsage: "{{< x user=\"GoHugoIO\" id=\"1453110110599868418\" >}}"
        ),
    ]

    static func find(by id: String) -> HugoShortcode? {
        allShortcodes.first { $0.id == id }
    }

    static func search(_ query: String) -> [HugoShortcode] {
        guard !query.isEmpty else { return allShortcodes }
        let lowercased = query.lowercased()
        return allShortcodes.filter {
            $0.id.lowercased().contains(lowercased) ||
            $0.name.lowercased().contains(lowercased) ||
            $0.description.lowercased().contains(lowercased)
        }
    }
}
