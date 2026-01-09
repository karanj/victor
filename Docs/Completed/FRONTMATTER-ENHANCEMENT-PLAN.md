# Front Matter Editor Enhancement Plan for Victor

**Created**: 2025-12-24
**Status**: Research & Planning Complete
**Next Step**: Implementation Phase 1

---

## Overview

This document outlines the plan for enhancing Victor's Front Matter editor to support the full range of Hugo's front matter capabilities, making it accessible to novices while providing power users with comprehensive control.

---

## Current Implementation Analysis

### Current Model (`Frontmatter.swift`)

The current implementation supports only 6 basic fields:
- `title: String?`
- `date: Date?`
- `draft: Bool?`
- `tags: [String]?`
- `categories: [String]?`
- `description: String?`
- `customFields: [String: Any]` (catch-all for unknown fields)

### Current UI (`FrontmatterEditorView.swift`)

The current UI provides:
- Title text field
- Date picker with optional toggle
- Draft toggle
- Description text area
- Tags chip input
- Categories chip input
- Read-only display of custom fields

### Limitations

1. **Missing Hugo predefined fields**: No support for `aliases`, `slug`, `url`, `weight`, `layout`, `type`, `keywords`, `expiryDate`, `publishDate`, `lastmod`, etc.
2. **No menu configuration**: Hugo's powerful menu system isn't exposed
3. **No build options**: Can't configure `list`, `render`, `publishResources`
4. **No cascade support**: Can't set up value inheritance
5. **No page resources**: Can't configure image/file metadata
6. **No sitemap config**: Can't set `changefreq`, `priority`
7. **No output formats**: Can't specify which formats to render
8. **Custom fields are read-only**: Users can't add/edit/delete custom fields

---

## Hugo Front Matter Complete Reference

### Predefined Fields

| Field | Type | Description | Priority |
|-------|------|-------------|----------|
| **title** | string | Page title | Essential |
| **date** | date | Creation/publication date | Essential |
| **draft** | bool | Mark as draft (won't publish) | Essential |
| **description** | string | Meta description for SEO | Essential |
| **tags** | string[] | Taxonomy tags | Essential |
| **categories** | string[] | Taxonomy categories | Essential |
| **weight** | int | Ordering weight (lower = first) | High |
| **slug** | string | Override URL slug | High |
| **url** | string | Override entire URL path | High |
| **aliases** | string[] | Redirect URLs to this page | High |
| **keywords** | string[] | SEO keywords | High |
| **lastmod** | date | Last modification date | High |
| **publishDate** | date | Future publish date | Medium |
| **expiryDate** | date | Expiration date | Medium |
| **layout** | string | Custom layout template | Medium |
| **type** | string | Content type override | Medium |
| **linkTitle** | string | Short title for links/menus | Medium |
| **summary** | string | Custom summary/teaser | Medium |
| **headless** | bool | Create headless bundle | Low |
| **isCJKLanguage** | bool | CJK content flag | Low |
| **markup** | string | Content format override | Low |
| **translationKey** | string | Link translations | Low |

### Complex Fields

#### menus (map/string/array)
```yaml
menus:
  main:
    name: "My Page"
    weight: 10
    parent: "products"
    identifier: "my-page"
    pre: "<i class='icon'></i>"
    post: ""
    title: "Tooltip text"
    params:
      class: "highlight"
```

#### build (map)
```yaml
build:
  list: always    # always, local, never
  render: always  # always, link, never
  publishResources: true
```

#### sitemap (map)
```yaml
sitemap:
  changefreq: monthly  # always, hourly, daily, weekly, monthly, yearly, never
  priority: 0.8        # 0.0 to 1.0
  disable: false
```

#### outputs (string[])
```yaml
outputs:
  - html
  - amp
  - json
  - rss
```

#### resources (map[])
```yaml
resources:
  - src: "images/hero.jpg"
    name: "hero"
    title: "Hero Image"
    params:
      credits: "Photo by John"
      alt: "A beautiful sunset"
  - src: "*.pdf"
    title: "Document #:counter"
```

#### cascade (map/map[])
```yaml
cascade:
  - banner: "/images/default.jpg"
    target:
      path: "/blog/**"
      kind: page
```

#### params (map)
```yaml
params:
  author: "Jane Doe"
  featured: true
  customField: "any value"
```

---

## Proposed UI Architecture

### Design Philosophy

1. **Progressive Disclosure**: Show common fields by default, advanced fields on demand
2. **Contextual Help**: Every field has inline help explaining what it does
3. **Smart Defaults**: Pre-populate sensible values where appropriate
4. **Validation**: Warn about invalid values before save
5. **Discoverability**: Users can explore all Hugo capabilities

### Proposed Layout

```
┌─────────────────────────────────────────────────────────────┐
│  [doc.text.fill] Frontmatter  YAML  [Form] [Raw]  [▼]      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  [Essential]  [Publishing]  [SEO]  [Menus]  [Advanced]      │
│  ──────────────────────────────────────────────────────────│
│                                                             │
│  ## Essential Tab (default)                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Title*        [                                   ] │   │
│  │ Date          [✓] [2025-01-15 10:00]              │   │
│  │ Draft         [✓] Mark as draft                   │   │
│  │ Description   [                                   ] │   │
│  │               [                                   ] │   │
│  │ Tags          [swift] [macos] [+]                 │   │
│  │ Categories    [development] [+]                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ## Publishing Tab                                          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Publish Date  [ ] [                    ]           │   │
│  │ Expiry Date   [ ] [                    ]           │   │
│  │ Last Modified [ ] [                    ]           │   │
│  │                                                     │   │
│  │ Weight        [     ] (lower = appears first)      │   │
│  │                                                     │   │
│  │ ── URL Settings ──                                 │   │
│  │ Slug          [                    ]               │   │
│  │ URL           [                    ]               │   │
│  │ Aliases       [/old-path] [/another] [+]          │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ## SEO Tab                                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Keywords      [hugo] [cms] [static] [+]            │   │
│  │ Summary       [                                   ] │   │
│  │               [                                   ] │   │
│  │ Link Title    [                    ]               │   │
│  │                                                     │   │
│  │ ── Sitemap ──                                      │   │
│  │ Change Freq   [monthly ▼]                          │   │
│  │ Priority      [0.5] ────●──────                    │   │
│  │ Exclude       [ ] Exclude from sitemap             │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ## Menus Tab                                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Add this page to menus:                            │   │
│  │                                                     │   │
│  │ [+] Add to Menu                                    │   │
│  │                                                     │   │
│  │ ┌─ main ─────────────────────────────────────────┐ │   │
│  │ │ Name        [My Page            ]              │ │   │
│  │ │ Weight      [10    ]                           │ │   │
│  │ │ Parent      [      ▼] (none)                   │ │   │
│  │ │ Identifier  [my-page            ]              │ │   │
│  │ │ [Advanced ▼]                                   │ │   │
│  │ │   Pre HTML  [                   ]              │ │   │
│  │ │   Post HTML [                   ]              │ │   │
│  │ │   Title     [                   ]              │ │   │
│  │ │                             [Remove from Menu] │ │   │
│  │ └────────────────────────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ## Advanced Tab                                            │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ ── Layout ──                                       │   │
│  │ Type          [                    ]               │   │
│  │ Layout        [                    ]               │   │
│  │                                                     │   │
│  │ ── Build Options ──                                │   │
│  │ List          [always ▼]                           │   │
│  │ Render        [always ▼]                           │   │
│  │ Publish Res   [✓]                                  │   │
│  │                                                     │   │
│  │ ── Output Formats ──                               │   │
│  │ [✓] HTML  [✓] RSS  [ ] AMP  [ ] JSON              │   │
│  │                                                     │   │
│  │ ── Page Resources ──                               │   │
│  │ [List of configured resources...]                  │   │
│  │ [+ Add Resource Configuration]                     │   │
│  │                                                     │   │
│  │ ── Custom Parameters ──                            │   │
│  │ author     = Jane Doe      [Edit] [Delete]        │   │
│  │ featured   = true          [Edit] [Delete]        │   │
│  │ [+ Add Custom Field]                               │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Implementation Architecture

### Enhanced Data Model

#### `Frontmatter.swift` - Expanded Model

```swift
import Foundation

/// Format of the frontmatter
enum FrontmatterFormat: String, CaseIterable {
    case yaml
    case toml
    case json
}

/// Build options for page rendering
struct BuildOptions {
    enum ListOption: String, CaseIterable {
        case always
        case local
        case never
    }

    enum RenderOption: String, CaseIterable {
        case always
        case link
        case never
    }

    var list: ListOption = .always
    var render: RenderOption = .always
    var publishResources: Bool = true
}

/// Sitemap configuration
struct SitemapConfig {
    enum ChangeFreq: String, CaseIterable {
        case always
        case hourly
        case daily
        case weekly
        case monthly
        case yearly
        case never
    }

    var changefreq: ChangeFreq?
    var priority: Double?  // 0.0 to 1.0
    var disable: Bool = false
}

/// Menu entry configuration
struct MenuEntry: Identifiable {
    let id = UUID()
    var menuName: String  // e.g., "main", "footer"
    var name: String?
    var weight: Int?
    var parent: String?
    var identifier: String?
    var pre: String?
    var post: String?
    var title: String?
    var params: [String: String] = [:]
}

/// Page resource configuration
struct ResourceConfig: Identifiable {
    let id = UUID()
    var src: String  // glob pattern
    var name: String?
    var title: String?
    var params: [String: String] = [:]
}

/// Cascade target configuration
struct CascadeTarget {
    var path: String?   // glob pattern
    var kind: String?   // page, section, home, etc.
    var lang: String?
    var environment: String?
}

/// Cascade entry
struct CascadeEntry: Identifiable {
    let id = UUID()
    var values: [String: Any] = [:]
    var target: CascadeTarget?
}

/// Represents Hugo frontmatter metadata - Enhanced version
@Observable
class Frontmatter {
    /// Raw frontmatter content including delimiters
    var rawContent: String

    /// Detected format
    var format: FrontmatterFormat

    // MARK: - Essential Fields
    var title: String?
    var date: Date?
    var draft: Bool?
    var description: String?
    var tags: [String]?
    var categories: [String]?

    // MARK: - Publishing Fields
    var publishDate: Date?
    var expiryDate: Date?
    var lastmod: Date?
    var weight: Int?

    // MARK: - URL Fields
    var slug: String?
    var url: String?
    var aliases: [String]?

    // MARK: - SEO Fields
    var keywords: [String]?
    var summary: String?
    var linkTitle: String?

    // MARK: - Layout Fields
    var type: String?
    var layout: String?

    // MARK: - Flags
    var headless: Bool?
    var isCJKLanguage: Bool?
    var markup: String?
    var translationKey: String?

    // MARK: - Complex Fields
    var menus: [MenuEntry] = []
    var build: BuildOptions?
    var sitemap: SitemapConfig?
    var outputs: [String]?
    var resources: [ResourceConfig] = []
    var cascade: [CascadeEntry] = []

    // MARK: - Custom Parameters
    /// Custom fields in the params section
    var params: [String: Any] = [:]

    /// Other custom fields at root level (legacy support)
    var customFields: [String: Any] = [:]

    // ... existing init and methods ...
}
```

### New View Components

#### File Structure

```
Victor/
├── Models/
│   ├── Frontmatter.swift           # Enhanced model
│   ├── FrontmatterTypes.swift      # BuildOptions, SitemapConfig, etc.
│   └── MenuEntry.swift             # Menu configuration
├── Views/
│   └── Editor/
│       ├── FrontmatterEditorView.swift      # Main editor (refactored)
│       ├── FrontmatterTabView.swift         # Tab container
│       ├── Tabs/
│       │   ├── EssentialFieldsTab.swift     # Title, date, draft, etc.
│       │   ├── PublishingTab.swift          # Dates, weight, URLs
│       │   ├── SEOTab.swift                 # Keywords, summary, sitemap
│       │   ├── MenusTab.swift               # Menu configuration
│       │   └── AdvancedTab.swift            # Build, outputs, resources
│       ├── Components/
│       │   ├── TagInputView.swift           # Existing chip input
│       │   ├── DateFieldView.swift          # Optional date field
│       │   ├── MenuEntryEditor.swift        # Single menu entry
│       │   ├── ResourceConfigEditor.swift   # Resource configuration
│       │   ├── CustomFieldEditor.swift      # Add/edit custom fields
│       │   └── HelpTooltip.swift            # Inline help
│       └── FlowLayout.swift                 # Existing layout
├── Services/
│   └── FrontmatterParser.swift     # Enhanced parser
```

---

## Detailed Field Specifications

### Essential Tab

| Field | UI Component | Validation | Help Text |
|-------|--------------|------------|-----------|
| Title | TextField | None | "The main title of your page" |
| Date | DatePicker + Toggle | Valid date | "The date associated with this content" |
| Draft | Toggle | None | "Draft pages aren't published to your site" |
| Description | TextEditor | Max 160 chars warning | "Meta description for search engines (aim for 150-160 characters)" |
| Tags | TagInputView | No duplicates | "Tags help categorize and discover your content" |
| Categories | TagInputView | No duplicates | "Broader classification than tags" |

### Publishing Tab

| Field | UI Component | Validation | Help Text |
|-------|--------------|------------|-----------|
| Publish Date | DatePicker + Toggle | Future date | "Content won't appear until this date" |
| Expiry Date | DatePicker + Toggle | After publish date | "Content will be hidden after this date" |
| Last Modified | DatePicker + Toggle | None | "When this content was last updated" |
| Weight | NumberField | Integer | "Lower numbers appear first in lists (default: 0)" |
| Slug | TextField | URL-safe chars | "The last part of the URL (e.g., /blog/[slug])" |
| URL | TextField | Valid path | "Override the entire URL path" |
| Aliases | TagInputView | Valid paths | "Old URLs that redirect to this page" |

### SEO Tab

| Field | UI Component | Validation | Help Text |
|-------|--------------|------------|-----------|
| Keywords | TagInputView | None | "Keywords for search engines" |
| Summary | TextEditor | None | "Custom summary or teaser text" |
| Link Title | TextField | None | "Short title used in menus and links" |
| Sitemap Change Freq | Picker | Enum | "How often this page typically changes" |
| Sitemap Priority | Slider (0-1) | 0.0-1.0 | "Relative importance (0.5 is default)" |
| Exclude from Sitemap | Toggle | None | "Hide this page from sitemap.xml" |

### Menus Tab

| Field | UI Component | Validation | Help Text |
|-------|--------------|------------|-----------|
| Menu Name | TextField/Picker | Required | "Which menu to add this page to (e.g., main, footer)" |
| Display Name | TextField | None | "Text shown in the menu (defaults to title)" |
| Weight | NumberField | Integer | "Position in menu (lower = earlier)" |
| Parent | Picker/TextField | Valid identifier | "Parent menu item for nested menus" |
| Identifier | TextField | Unique, alphanumeric | "Unique ID for this menu entry" |
| Pre HTML | TextField | None | "HTML inserted before the menu text" |
| Post HTML | TextField | None | "HTML inserted after the menu text" |
| Title Attribute | TextField | None | "Tooltip text on hover" |

### Advanced Tab

| Field | UI Component | Validation | Help Text |
|-------|--------------|------------|-----------|
| Type | TextField | None | "Content type (defaults to section name)" |
| Layout | TextField | None | "Specific template to use for this page" |
| Build: List | Picker | Enum | "When to include in page lists" |
| Build: Render | Picker | Enum | "When to render this page to disk" |
| Build: Publish Resources | Toggle | None | "Whether to publish page resources" |
| Outputs | Checkboxes | None | "Which formats to generate (HTML, RSS, JSON, etc.)" |
| Headless | Toggle | None | "Create headless bundle (no page generated)" |
| Translation Key | TextField | None | "Link this page to translations" |

---

## Parser Enhancements

### Fields to Parse

The `FrontmatterParser` needs to be extended to parse these additional fields:

```swift
extension FrontmatterParser {
    private func extractAllFields(from dict: [String: Any], into frontmatter: Frontmatter) {
        // Essential (existing)
        extractCommonFields(from: dict, into: frontmatter)

        // Publishing
        frontmatter.publishDate = parseDate(dict["publishDate"])
        frontmatter.expiryDate = parseDate(dict["expiryDate"])
        frontmatter.lastmod = parseDate(dict["lastmod"])
        frontmatter.weight = dict["weight"] as? Int

        // URL
        frontmatter.slug = dict["slug"] as? String
        frontmatter.url = dict["url"] as? String
        frontmatter.aliases = dict["aliases"] as? [String]

        // SEO
        frontmatter.keywords = dict["keywords"] as? [String]
        frontmatter.summary = dict["summary"] as? String
        frontmatter.linkTitle = dict["linkTitle"] as? String

        // Layout
        frontmatter.type = dict["type"] as? String
        frontmatter.layout = dict["layout"] as? String

        // Flags
        frontmatter.headless = dict["headless"] as? Bool
        frontmatter.isCJKLanguage = dict["isCJKLanguage"] as? Bool
        frontmatter.markup = dict["markup"] as? String
        frontmatter.translationKey = dict["translationKey"] as? String

        // Complex fields
        parseMenus(from: dict, into: frontmatter)
        parseBuildOptions(from: dict, into: frontmatter)
        parseSitemap(from: dict, into: frontmatter)
        parseOutputs(from: dict, into: frontmatter)
        parseResources(from: dict, into: frontmatter)
        parseCascade(from: dict, into: frontmatter)
        parseParams(from: dict, into: frontmatter)
    }
}
```

### Serialization

All new fields need corresponding serialization logic to write back to YAML/TOML/JSON.

---

## Phase Plan

### Phase 1: Data Model Foundation
- [ ] Create `FrontmatterTypes.swift` with new types (BuildOptions, SitemapConfig, etc.)
- [ ] Expand `Frontmatter.swift` with all new fields
- [ ] Update `FrontmatterSnapshot` for change detection
- [ ] Update Xcode project file

### Phase 2: Parser Enhancement
- [ ] Add parsing for all predefined fields
- [ ] Add parsing for menu configuration
- [ ] Add parsing for build options
- [ ] Add parsing for sitemap config
- [ ] Add parsing for outputs
- [ ] Add parsing for resources
- [ ] Add serialization for all new fields
- [ ] Add unit tests for parser

### Phase 3: Essential Tab Enhancement
- [ ] Improve existing fields with help tooltips
- [ ] Add character count to description
- [ ] Improve TagInputView with suggestions
- [ ] Add validation feedback

### Phase 4: Publishing Tab
- [ ] Create `PublishingTab.swift`
- [ ] Add publish date field
- [ ] Add expiry date field
- [ ] Add last modified field
- [ ] Add weight field
- [ ] Add slug field
- [ ] Add URL field
- [ ] Add aliases input

### Phase 5: SEO Tab
- [ ] Create `SEOTab.swift`
- [ ] Add keywords input
- [ ] Add summary field
- [ ] Add link title field
- [ ] Add sitemap configuration UI
- [ ] Add character count hints

### Phase 6: Menus Tab
- [ ] Create `MenusTab.swift`
- [ ] Create `MenuEntryEditor.swift`
- [ ] Add menu picker (from site config or common defaults)
- [ ] Support multiple menu entries
- [ ] Support nested menus (parent field)
- [ ] Add advanced options (pre, post, params)

### Phase 7: Advanced Tab
- [ ] Create `AdvancedTab.swift`
- [ ] Add type/layout fields
- [ ] Add build options UI
- [ ] Add outputs checkboxes
- [ ] Create `ResourceConfigEditor.swift`
- [ ] Add cascade configuration (stretch goal)

### Phase 8: Custom Fields Editor
- [ ] Create `CustomFieldEditor.swift`
- [ ] Support add/edit/delete custom fields
- [ ] Auto-detect field types (string, number, boolean, array)
- [ ] Support nested params object

### Phase 9: Polish & Testing
- [ ] Accessibility audit (VoiceOver)
- [ ] Keyboard navigation
- [ ] Performance testing
- [ ] User testing with Hugo novices

---

## UX Principles

### 1. Progressive Disclosure
- Essential tab shown by default
- Advanced features hidden until needed
- Expandable sections within tabs

### 2. Inline Help
- Every field has a help icon with tooltip
- Tooltips explain what the field does in plain English
- Link to Hugo documentation for complex fields

### 3. Smart Defaults
- Draft defaults to true for new files
- Date defaults to now
- Slug auto-generates from title
- Common menus suggested (main, footer)

### 4. Validation & Feedback
- Real-time validation for URL fields
- Character count for SEO fields
- Warning for duplicate aliases
- Error states for invalid values

### 5. Discoverability
- Tab labels clearly describe content
- "Add" buttons for optional complex fields
- Empty states explain what each section does

---

## Accessibility Considerations

- All form fields have proper labels
- Tab navigation works correctly
- VoiceOver announces field names and help text
- Color not used as only indicator
- Sufficient contrast for all text
- Focus indicators visible

---

## Future Considerations

### Site-Aware Features
- **Menu suggestions**: Read site config to suggest existing menus
- **Layout autocomplete**: Scan layouts directory for valid layouts
- **Type suggestions**: Based on existing content types in site
- **Archetype awareness**: Pre-populate from archetypes

### Templates
- Save/load frontmatter templates
- Per-section defaults
- Quick presets (blog post, documentation page, etc.)

### Validation
- Warn about missing required fields (title)
- Check for duplicate aliases across site
- Validate URLs and paths

### Integration
- Hugo server integration to preview changes
- Git integration to track frontmatter changes

---

## Sources

- [Hugo Front Matter Documentation](https://gohugo.io/content-management/front-matter/)
- [Hugo Configure Front Matter](https://gohugo.io/configuration/front-matter/)
- [Hugo Menus Documentation](https://gohugo.io/content-management/menus/)
- [Hugo Build Options](https://gohugo.io/content-management/build-options/)
- [Hugo Page Resources](https://gohugo.io/content-management/page-resources/)
- [Hugo Configure Cascade](https://gohugo.io/configuration/cascade/)

---

**Document Version**: 1.0
**Last Updated**: 2025-12-24
