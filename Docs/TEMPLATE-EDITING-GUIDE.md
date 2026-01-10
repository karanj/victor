# Template Editing Guide

This guide covers Victor's template editing capabilities for Hugo's `layouts/` and `themes/` directories.

## Overview

Victor provides specialized editing support for Hugo template files with:
- **Syntax highlighting** for Go template syntax
- **Metadata extraction** showing blocks, partials, functions, and variables
- **Template browser** for navigating the template hierarchy
- **Type detection** identifying template purposes (base, single, list, partial, shortcode, etc.)

## Template Types

Victor automatically detects template types based on filename and directory:

| Type | Description | Examples |
|------|-------------|----------|
| **Base** | Base template with block definitions | `baseof.html` |
| **Single** | Single content page template | `single.html` |
| **List** | List/section template | `list.html` |
| **Partial** | Reusable template fragment | `partials/*.html` |
| **Shortcode** | Content shortcode | `shortcodes/*.html` |
| **Taxonomy** | Taxonomy term pages | `taxonomy.html`, `terms.html` |
| **Home** | Homepage template | `index.html` (in root) |
| **Section** | Section list pages | `section.html` |

## Template Browser

When you click on the `layouts/` or `themes/` directory in the sidebar, Victor displays the **Template Browser** instead of a regular folder view.

### View Modes

The browser offers three view modes:

1. **By Type**: Groups templates by their detected type (Base, Single, List, Partial, etc.)
2. **By Directory**: Groups templates by their directory path within layouts/
3. **Inheritance**: Shows base templates and which templates extend them

### Features

- **Search**: Filter templates by name, path, or type
- **Theme Toggle**: Show/hide theme templates
- **Statistics Panel**: Shows template counts and most-used partials
- **Quick Navigation**: Click any template to open it in the editor

### Template Row Information

Each template row shows:
- Template type icon (color-coded)
- Filename
- Full directory path (e.g., `layouts/_default` or `themes/mytheme/layouts/partials`)
- "theme" badge for theme templates
- Block icon if the template defines blocks
- Partial count showing how many partials are used

### Navigation Integration

When you click a template in the browser:
- The template opens in the editor
- All parent folders expand in the sidebar file tree
- The file is selected/highlighted in the sidebar
- This provides clear context of where the file lives in the hierarchy

## Template Editor

Clicking on any `.html` file in `layouts/` or `themes/` opens the Template Editor.

### Syntax Highlighting

The editor provides syntax highlighting for:

| Element | Color | Example |
|---------|-------|---------|
| Template delimiters | Purple | `{{` `}}` |
| Keywords | Blue | `if`, `else`, `range`, `with`, `define`, `block`, `partial` |
| Variables | Teal | `.Title`, `.Content`, `.Params.author`, `$myVar` |
| Strings | Green | `"header.html"` |
| HTML tags | Orange | `<div>`, `</section>` |
| Comments | Gray | `<!-- -->`, `{{/* */}}` |

### Toolbar

The editor toolbar provides:
- Template type badge (color-coded)
- Theme name badge (for theme templates)
- Unsaved changes indicator
- Info panel toggle
- Save button (Cmd+S)
- Reload from disk
- Open in external editor
- Reveal in Finder

### Metadata Panel

Toggle the metadata panel to see extracted information:

#### Template Info
- Template type and description
- Relative path within layouts/
- Theme name (if applicable)
- Whether it extends a base template
- Number of blocks defined

#### Blocks Section
Shows `{{ define "blockname" }}` and `{{ block "blockname" . }}` usage:
- Blue icon: Block definition (defines)
- Orange icon: Block usage (uses)
- Line numbers for quick navigation

#### Partials Section
Lists all `{{ partial "name.html" . }}` calls:
- Partial name (without .html extension)
- Line number where it's used

#### Functions Section
Shows Go template functions used:
- Function name
- Usage count
- Control flow functions highlighted in blue

#### Variables Section
Lists variables accessed in the template:
- Variable name (`.Title`, `.Params.author`, etc.)
- Usage count
- Color-coded by category (Page, Site, Params, Local)

## Template Metadata Extraction

Victor extracts the following metadata from templates:

### Blocks
- **Definitions**: `{{ define "main" }}...{{ end }}`
- **Usages**: `{{ block "main" . }}{{ end }}`

### Partials
- Standard: `{{ partial "header.html" . }}`
- Cached: `{{ partialCached "header.html" . }}`
- With context: `{{ partial "meta.html" $customContext }}`

### Functions
Detects usage of common Go template functions:
- Control flow: `if`, `else`, `with`, `range`, `end`
- Comparison: `eq`, `ne`, `lt`, `gt`, `and`, `or`, `not`
- String: `print`, `printf`, `len`, `lower`, `upper`, `trim`
- Hugo-specific: `partial`, `safeHTML`, `markdownify`, `absURL`, `relURL`
- Data: `dict`, `slice`, `append`, `merge`, `where`, `first`, `sort`

### Variables
Categorizes variables by type:
- **Page**: `.Title`, `.Content`, `.Summary`, `.Date`, `.Permalink`
- **Site**: `.Site.Title`, `.Site.Params`, `.Site.BaseURL`
- **Params**: `.Params.author`, `.Params.tags`
- **Local**: `$myVar`, `$index`

## Workflow Examples

### Finding Templates That Use a Partial

1. Open the Template Browser (click `layouts/`)
2. Look at the Statistics Panel under "Popular Partials"
3. See which partials are used most frequently
4. Use search to find templates using a specific partial

### Understanding Template Inheritance

1. Open the Template Browser
2. Switch to "Inheritance" view mode
3. See base templates at the top with their extending templates listed below
4. Click any template to open and edit it

### Editing a Shortcode

1. Navigate to `layouts/shortcodes/` in the sidebar
2. Click on the shortcode file (e.g., `figure.html`)
3. The editor opens with syntax highlighting
4. The metadata panel shows shortcode-specific patterns like `.Inner`, `.Get`, `.Params`

### Creating a New Template

Currently, Victor doesn't have a "New Template" dialog. To create a new template:

1. Right-click on a folder in the sidebar
2. Select "Reveal in Finder"
3. Create the new `.html` file in Finder
4. Return to Victor and refresh (the file tree auto-updates)
5. Click on the new file to edit it

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+S | Save template |
| Standard text editing shortcuts | Cut, Copy, Paste, Undo, Redo |

## File Support

### Supported Files
- All `.html` files in `layouts/` directory
- All `.html` files in `themes/*/layouts/` directories

### Not Yet Supported
- Template syntax validation/linting
- Autocomplete for Hugo functions
- Go to definition for partials
- Template preview

## Troubleshooting

### Template Not Detected Correctly

Template type detection is based on filename and path. If a template is misclassified:
- Check the filename matches Hugo conventions
- Ensure the file is in the correct directory (partials/, shortcodes/, etc.)
- The "other" type is used as a fallback for non-standard names

### Syntax Highlighting Issues

The syntax highlighter uses regex patterns that may not cover all edge cases:
- Complex nested templates may not highlight perfectly
- Very long lines may have performance impact
- Highlighting updates with a 300ms debounce for smooth typing

### Missing Partials in Metadata

The partial detection looks for standard `{{ partial "name" }}` syntax:
- Dynamic partial names (using variables) won't be detected
- Partials called via `template` action aren't listed under partials

## Technical Details

### Files Created

| File | Purpose |
|------|---------|
| `Victor/Models/Template.swift` | Template model and type definitions |
| `Victor/Services/TemplateParser.swift` | Metadata extraction and template discovery |
| `Victor/Views/TemplateEditor/TemplateEditorView.swift` | Editor with syntax highlighting |
| `Victor/Views/TemplateEditor/TemplateBrowserView.swift` | Template hierarchy browser |

### Template Model Properties

```swift
class Template {
    let url: URL                    // File location
    var content: String             // Current content
    var metadata: TemplateMetadata  // Extracted metadata
    var templateType: TemplateType  // Detected type
    var isThemeTemplate: Bool       // From themes/ directory
    var themeName: String?          // Theme name if applicable
    var hasUnsavedChanges: Bool     // Content modified
}
```

### TemplateMetadata Structure

```swift
struct TemplateMetadata {
    var blocks: [TemplateBlock]           // define/block statements
    var partials: [PartialReference]      // partial calls
    var functions: [TemplateFunctionUsage] // function usage counts
    var variables: [TemplateVariable]     // variable access
    var hasBaseTemplate: Bool             // uses {{ block }}
    var definesBlocks: Bool               // uses {{ define }}
}
```

## Future Enhancements

Planned improvements for template editing:
- Template syntax validation with error reporting
- Autocomplete for Hugo functions and variables
- Go to definition for partials (Cmd+Click)
- Template preview with sample data
- New template creation dialogs
- Template snippets and boilerplate
