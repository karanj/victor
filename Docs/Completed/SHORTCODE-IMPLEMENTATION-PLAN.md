# Hugo Shortcode Implementation Plan for Victor

**Created**: 2025-12-24
**Status**: Research & Planning Complete
**Next Step**: Implementation Phase 1

---

## Overview

This document outlines the plan for adding Hugo shortcode support to Victor, making Hugo's powerful shortcode system accessible to novices without requiring them to read Hugo documentation.

---

## Research Summary

### Hugo Built-in Shortcodes (12 total)

| Shortcode | Purpose | Key Parameters |
|-----------|---------|----------------|
| `figure` | Images with captions | src, alt, caption, link, title, attr, class, width, height |
| `highlight` | Syntax-highlighted code | LANG, lineNos, hl_lines, style, hl_inline, tabWidth |
| `youtube` | Embed YouTube videos | id, start, end, autoplay, loop, mute, class |
| `vimeo` | Embed Vimeo videos | id, allowFullScreen, class, loading, title |
| `gist` | Embed GitHub Gists (deprecated v0.143.0) | user, gist-id, filename |
| `details` | Collapsible content | summary, open, class, name, title |
| `qr` | Generate QR codes | text, level, scale, alt, class |
| `x` | Embed X/Twitter posts | user, id |
| `instagram` | Embed Instagram posts | POST_ID |
| `ref` | Internal links (absolute) | path, lang, outputFormat |
| `relref` | Internal links (relative) | path, lang, outputFormat |
| `param` | Render frontmatter params | parameter_name |

### Shortcode Notation Types

- `{{< shortcode >}}` - Standard notation (content NOT processed by Markdown)
- `{{% shortcode %}}` - Markdown notation (content IS processed by Markdown)

### Shortcode Syntax Patterns

**Self-closing:**
```
{{< figure src="/image.jpg" alt="Description" >}}
```

**With closing tag:**
```
{{< highlight go >}}
fmt.Println("Hello")
{{< /highlight >}}
```

**Positional arguments:**
```
{{< youtube 0RKpf3rK57I >}}
```

**Named arguments:**
```
{{< youtube id=0RKpf3rK57I start=30 end=60 >}}
```

---

## Detailed Shortcode Reference

### figure

Insert an HTML figure element with optional caption, link, and attribution.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `src` | string | Yes | Image source URL (page or global resource) |
| `alt` | string | Yes | Alternate text for accessibility |
| `caption` | string | No | Caption text (supports Markdown) |
| `title` | string | No | Heading inside figcaption (h4) |
| `link` | string | No | URL for wrapping anchor element |
| `target` | string | No | Target attribute for anchor (_blank, etc.) |
| `rel` | string | No | Relationship attribute for anchor |
| `attr` | string | No | Attribution text (supports Markdown) |
| `attrlink` | string | No | URL for attribution link |
| `class` | string | No | CSS classes for figure element |
| `width` | int | No | Image width attribute |
| `height` | int | No | Image height attribute |
| `loading` | string | No | Loading behavior (eager/lazy) |

**Example:**
```
{{< figure
  src="/images/photo.jpg"
  alt="A scenic mountain view"
  caption="View from the summit"
  link="https://example.com"
  class="rounded shadow"
>}}
```

---

### highlight

Insert syntax-highlighted code using the Chroma highlighter (~250 languages).

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `LANG` | string | Yes | Programming language (case-insensitive) |
| `lineNos` | any | No | Enable line numbers (true, false, inline, table) |
| `lineNoStart` | int | No | Starting line number (default: 1) |
| `hl_lines` | string | No | Emphasize specific lines (e.g., "2-4 7") |
| `style` | string | No | Highlighting style (default: monokai) |
| `hl_inline` | bool | No | Render without wrapper container |
| `noClasses` | bool | No | Use inline CSS instead of external file |
| `anchorLineNos` | bool | No | Render line numbers as HTML anchors |
| `tabWidth` | int | No | Spaces per tab character (default: 4) |
| `wrapperClass` | string | No | CSS class for outer element |
| `guessSyntax` | bool | No | Auto-detect language if unspecified |

**Example:**
```
{{< highlight swift "linenos=inline, hl_lines=3 5-7" >}}
func greet(name: String) {
    let message = "Hello, \(name)!"
    print(message)
}
{{< /highlight >}}
```

**Inline usage:**
```
Use {{< highlight go "hl_inline=true" >}}fmt.Println(){{< /highlight >}} to print.
```

---

### youtube

Embed a YouTube video with customizable playback options.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string | Yes | Video ID from YouTube URL |
| `start` | int | No | Start time in seconds |
| `end` | int | No | Stop time in seconds |
| `autoplay` | bool | No | Auto-play video (forces mute) |
| `loop` | bool | No | Repeat video indefinitely |
| `mute` | bool | No | Mute audio |
| `controls` | bool | No | Show video controls (default: true) |
| `allowFullScreen` | bool | No | Enable full screen (default: true) |
| `class` | string | No | CSS class for wrapping div |
| `loading` | string | No | Loading method: eager or lazy |
| `title` | string | No | iframe title attribute |

**Example:**
```
{{< youtube 0RKpf3rK57I >}}

{{< youtube id=0RKpf3rK57I start=30 end=120 loading=lazy >}}
```

---

### vimeo

Embed a Vimeo video.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string | Yes | Video identifier |
| `allowFullScreen` | bool | No | Enable full screen (default: true) |
| `class` | string | No | CSS class for wrapping div |
| `loading` | string | No | Loading behavior: eager or lazy |
| `title` | string | No | Title attribute for iframe |

**Example:**
```
{{< vimeo 55073825 >}}

{{< vimeo id=55073825 allowFullScreen=false loading=lazy >}}
```

---

### gist

Embed a GitHub Gist. **Note: Deprecated in Hugo v0.143.0**

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `user` | string | Yes | GitHub username |
| `gist-id` | string | Yes | Unique gist identifier |
| `filename` | string | No | Specific file within the gist |

**Example:**
```
{{< gist spf13 7896402 >}}

{{< gist spf13 7896402 "init-hierarchical.sh" >}}
```

---

### details

Insert a collapsible HTML details element.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `summary` | string | No | Summary text (default: "Details") |
| `open` | bool | No | Initially expanded (default: false) |
| `class` | string | No | CSS class for details element |
| `name` | string | No | Name attribute for grouping |
| `title` | string | No | Title attribute |

**Example:**
```
{{< details summary="Click to expand" >}}
This content is hidden by default.

- Item 1
- Item 2
{{< /details >}}
```

---

### qr

Generate and insert a QR code image.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `text` | string | Yes | Text to encode |
| `level` | string | No | Error correction: low, medium, quartile, high |
| `scale` | int | No | Pixels per module (default: 4, min: 2) |
| `targetDir` | string | No | Subdirectory for generated image |
| `alt` | string | No | Alt text for image |
| `class` | string | No | CSS class for image |
| `id` | string | No | HTML id attribute |
| `loading` | string | No | Loading behavior: eager or lazy |
| `title` | string | No | Title attribute |

**Example:**
```
{{< qr text="https://gohugo.io" level=high scale=6 />}}

{{< qr >}}
https://example.com/long-url-here
{{< /qr >}}
```

---

### x (Twitter/X)

Embed an X (formerly Twitter) post.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `user` | string | Yes | X account username |
| `id` | string | Yes | Numeric post ID |

**Example:**
```
{{< x user="GoHugoIO" id="1453110110599868418" >}}
```

---

### instagram

Embed an Instagram post.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string | Yes | Post ID from Instagram URL |

**Example:**
```
{{< instagram CxOWiQNP2MO >}}
```

---

### ref

Insert an absolute permalink to another page.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `path` | string | Yes | Path to target page |
| `lang` | string | No | Target page's language |
| `outputFormat` | string | No | Target page's output format |

**Example:**
```
[Link text]({{% ref "/blog/my-post" %}})

{{% ref path="/docs/guide" lang="en" %}}
```

---

### relref

Insert a relative permalink to another page.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `path` | string | Yes | Path to target page |
| `lang` | string | No | Target page's language |
| `outputFormat` | string | No | Target page's output format |

**Example:**
```
[Related post]({{% relref "related-post.md" %}})
```

---

### param

Render a parameter from front matter or site configuration.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `name` | string | Yes | Parameter name (supports dot notation) |

**Example:**
```
Author: {{% param author %}}

Theme color: {{% param site.params.theme.color %}}
```

---

## Recommended Implementation Approach

### Hybrid UX Design

For maximum accessibility to novices while supporting power users, implement a **two-pronged approach**:

#### 1. Shortcode Picker Panel (Primary - Novice-Friendly)

A dedicated toolbar button that opens a rich shortcode picker:

**Panel Design:**
- Modal sheet or slide-out panel from the right
- Categories with icons for organization:
  - **Media**: figure, youtube, vimeo, instagram
  - **Code**: highlight, gist
  - **Layout**: details, qr
  - **Links & Data**: ref, relref, param, x

**Each shortcode card shows:**
- Icon + Name
- One-line description
- "Insert" button

**On selection, shows:**
- Full description with example
- Form fields for all parameters (with labels, placeholders, help text)
- Required vs optional clearly marked
- Live preview of generated shortcode
- "Insert" button

**Example UI for `figure`:**
```
┌─────────────────────────────────────────────┐
│  [photo.artframe] Figure                    │
│  Insert an image with caption               │
│─────────────────────────────────────────────│
│  Source URL*     [                    ]     │
│  Alt text*       [                    ]     │
│  Caption         [                    ]     │
│  Link            [                    ]     │
│  CSS Class       [                    ]     │
│  Width           [     ]  Height [     ]    │
│─────────────────────────────────────────────│
│  Preview:                                   │
│  {{< figure src="..." alt="..." >}}         │
│                                             │
│          [Cancel]  [Insert]                 │
└─────────────────────────────────────────────┘
```

#### 2. Inline Autocomplete (Secondary - Power Users)

Triggered when user types `{{<` or `{{% `:

**Behavior:**
1. After typing `{{<` (or `{{%`), show popover below cursor
2. List all shortcodes with icons and one-line descriptions
3. Continue typing to filter (fuzzy match): `{{<fig` shows `figure`
4. Arrow keys to navigate, Enter/Tab to select
5. On selection, insert shortcode with placeholder tab-stops

**Tab-stop example for figure:**
```
{{< figure src="${1:url}" alt="${2:description}" >}}
```
User can Tab through placeholders like VS Code snippets.

---

## Implementation Architecture

### New Files to Create

```
Victor/
├── Models/
│   └── HugoShortcode.swift              # Shortcode definitions & registry
├── Views/
│   └── Editor/
│       ├── ShortcodePickerView.swift    # Main picker panel
│       ├── ShortcodeFormView.swift      # Form for parameters
│       ├── ShortcodeAutocomplete.swift  # Inline autocomplete popover
│       └── ShortcodeCardView.swift      # Individual shortcode card
├── Services/
│   └── ShortcodeService.swift           # Insertion logic, templates
```

### Data Model: `HugoShortcode.swift`

```swift
import Foundation

// MARK: - Parameter Types

enum ShortcodeParameterType {
    case string
    case int
    case bool
    case enumeration([String])
}

struct ShortcodeParameter: Identifiable {
    let id: String  // Same as name
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

struct HugoShortcode: Identifiable {
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
                if value.contains(" ") {
                    return "\(param.name)=\"\(value)\""
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
```

---

## UI Integration Points

### 1. Toolbar Button Addition

In `EditorToolbar`, add a shortcode button:

```swift
// After existing formatting buttons
Divider()
    .frame(height: 20)

Button(action: { showShortcodePicker = true }) {
    Label("Shortcode", systemImage: "curlybraces")
        .labelStyle(.iconOnly)
}
.buttonStyle(.bordered)
.help("Insert Hugo Shortcode (⌘⇧K)")
```

### 2. Shortcode Picker Sheet

In `EditorPanelView`:

```swift
@State private var showShortcodePicker = false

// In body, add:
.sheet(isPresented: $showShortcodePicker) {
    ShortcodePickerView(onInsert: { shortcodeText in
        editorCoordinator?.insertText(shortcodeText)
        showShortcodePicker = false
    })
}
```

### 3. Editor Coordinator Extensions

Add to `EditorTextView.Coordinator`:

```swift
func insertText(_ text: String) {
    guard let textView = textView else { return }
    let selectedRange = textView.selectedRange()

    if textView.shouldChangeText(in: selectedRange, replacementString: text) {
        textView.textStorage?.replaceCharacters(in: selectedRange, with: text)
        textView.didChangeText()

        // Position cursor after inserted text
        let newPosition = selectedRange.location + text.count
        textView.setSelectedRange(NSRange(location: newPosition, length: 0))
    }
}
```

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘⇧K` | Open Shortcode Picker |
| `Esc` | Close autocomplete popover |
| `↑/↓` | Navigate autocomplete list |
| `Enter/Tab` | Insert selected shortcode |
| `Tab` | Jump to next placeholder (future) |
| `⇧Tab` | Jump to previous placeholder (future) |

---

## Phase Plan

### Phase 1: Data Model & Registry
- [ ] Create `HugoShortcode.swift` with all 12 shortcodes
- [ ] Include full parameter metadata and help text
- [ ] Add shortcode generation method
- [ ] Update Xcode project file

### Phase 2: Shortcode Picker Panel
- [ ] Create `ShortcodePickerView` with category sidebar
- [ ] Create `ShortcodeCardView` for list items
- [ ] Create `ShortcodeFormView` for parameter input
- [ ] Add toolbar button with keyboard shortcut
- [ ] Wire up insertion into editor
- [ ] Update Xcode project file

### Phase 3: Inline Autocomplete
- [ ] Modify `EditorTextView.Coordinator` for trigger detection (`{{<`, `{{% `)
- [ ] Create `ShortcodeAutocompleteController` with `NSPopover`
- [ ] Implement keyboard navigation
- [ ] Handle filtering as user types
- [ ] Update Xcode project file

### Phase 4: Tab-Stop Placeholders (Future)
- [ ] Implement placeholder syntax in generated shortcodes
- [ ] Track placeholder positions in editor
- [ ] Handle Tab/Shift+Tab navigation between placeholders

### Phase 5: Polish & Testing
- [ ] Accessibility audit (VoiceOver)
- [ ] Performance testing with large files
- [ ] User testing with Hugo novices

---

## UX Principles for Novices

1. **Progressive Disclosure**: Show essential parameters first, advanced ones in expandable section
2. **Inline Help**: Every parameter has a help tooltip explaining what it does
3. **Live Preview**: Show the generated shortcode as user fills form
4. **Examples**: Each shortcode shows a real-world example
5. **Validation**: Warn if required parameters missing before insert
6. **No Jargon**: Use friendly names ("Image with Caption" not "figure element")
7. **Deprecation Warnings**: Show clear warnings for deprecated shortcodes

---

## Future Considerations

### Custom Shortcodes
- Detect custom shortcodes from site's `layouts/_shortcodes/` directory
- Parse shortcode templates to infer parameters
- Add them to picker with "Custom" category

### Live Preview Integration
- Render shortcodes in the preview panel
- Would require Hugo server integration or custom rendering

### Toolbar Placement Options
- Current plan: In existing formatting toolbar
- Alternative: Separate "Insert" menu
- Alternative: Menu bar item under Edit

---

## Sources

- [Hugo Shortcodes Documentation](https://gohugo.io/content-management/shortcodes/)
- [Hugo Shortcode Templates](https://gohugo.io/templates/shortcode/)
- [Hugo Highlight Shortcode](https://gohugo.io/shortcodes/highlight/)
- [Hugo Figure Shortcode](https://gohugo.io/shortcodes/figure/)
- [Hugo YouTube Shortcode](https://gohugo.io/shortcodes/youtube/)
- [VS Code Snippets Documentation](https://code.visualstudio.com/docs/editing/userdefinedsnippets)
- [VS Code IntelliSense](https://code.visualstudio.com/docs/editing/intellisense)
- [Autocomplete UX Best Practices](https://www.freshconsulting.com/insights/blog/autocomplete-benefits-ux-best-practices/)
- [Popover Pattern UX](https://uxpatterns.dev/patterns/content-management/popover)

---

**Document Version**: 1.0
**Last Updated**: 2025-12-24
