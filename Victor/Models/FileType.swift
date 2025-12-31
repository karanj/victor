import SwiftUI

/// Represents the type of a file based on its extension
enum FileType: String, CaseIterable, Equatable {
    // MARK: - Content
    case markdown
    case html

    // MARK: - Configuration
    case yaml
    case toml
    case json

    // MARK: - Web Assets
    case css
    case javascript
    case typescript
    case scss
    case sass
    case less

    // MARK: - Media (view-only)
    case image      // jpg, png, gif, svg, webp, ico
    case video      // mp4, webm, mov
    case audio      // mp3, wav, ogg
    case pdf

    // MARK: - Other
    case plainText  // txt, etc.
    case xml
    case go         // Go templates
    case binary     // unknown/unsupported

    // MARK: - Initialization

    /// Initialize from file extension
    init(extension ext: String) {
        let lowercased = ext.lowercased()
        switch lowercased {
        // Content
        case "md", "markdown":
            self = .markdown
        case "html", "htm":
            self = .html

        // Configuration
        case "yaml", "yml":
            self = .yaml
        case "toml":
            self = .toml
        case "json":
            self = .json

        // Web assets
        case "css":
            self = .css
        case "js", "mjs", "cjs":
            self = .javascript
        case "ts", "tsx":
            self = .typescript
        case "scss":
            self = .scss
        case "sass":
            self = .sass
        case "less":
            self = .less

        // Media
        case "jpg", "jpeg", "png", "gif", "svg", "webp", "ico", "bmp", "tiff", "tif":
            self = .image
        case "mp4", "webm", "mov", "avi", "mkv":
            self = .video
        case "mp3", "wav", "ogg", "aac", "flac", "m4a":
            self = .audio
        case "pdf":
            self = .pdf

        // Other text formats
        case "txt", "text", "log":
            self = .plainText
        case "xml", "xsl", "xslt", "rss", "atom":
            self = .xml
        case "go", "tmpl":
            self = .go

        default:
            self = .binary
        }
    }

    /// Initialize from URL
    init(url: URL) {
        self.init(extension: url.pathExtension)
    }

    // MARK: - Properties

    /// Whether this file type can be edited as text
    var isEditable: Bool {
        switch self {
        case .markdown, .html, .yaml, .toml, .json,
             .css, .javascript, .typescript, .scss, .sass, .less,
             .plainText, .xml, .go:
            return true
        case .image, .video, .audio, .pdf, .binary:
            return false
        }
    }

    /// Whether this file type supports live preview
    var isPreviewable: Bool {
        switch self {
        case .markdown:
            return true
        case .image:
            return true
        default:
            return false
        }
    }

    /// Whether this is a text-based file
    var isTextBased: Bool {
        switch self {
        case .image, .video, .audio, .pdf, .binary:
            return false
        default:
            return true
        }
    }

    /// Whether this file type is a Hugo config file format
    var isConfigFormat: Bool {
        switch self {
        case .toml, .yaml, .json:
            return true
        default:
            return false
        }
    }

    /// SF Symbol name for this file type
    var systemImage: String {
        switch self {
        case .markdown:
            return "doc.text"
        case .html:
            return "doc.text.fill"
        case .yaml, .toml, .json:
            return "gearshape"
        case .css, .scss, .sass, .less:
            return "paintbrush"
        case .javascript, .typescript:
            return "curlybraces"
        case .image:
            return "photo"
        case .video:
            return "film"
        case .audio:
            return "waveform"
        case .pdf:
            return "doc.richtext"
        case .plainText:
            return "doc.plaintext"
        case .xml:
            return "chevron.left.forwardslash.chevron.right"
        case .go:
            return "doc.text.magnifyingglass"
        case .binary:
            return "doc"
        }
    }

    /// Default color for this file type
    var defaultColor: Color {
        switch self {
        case .markdown:
            return .primary
        case .html, .go:
            return .orange
        case .yaml, .toml, .json:
            return .purple
        case .css, .scss, .sass, .less:
            return .pink
        case .javascript, .typescript:
            return .yellow
        case .image:
            return .green
        case .video:
            return .red
        case .audio:
            return .cyan
        case .pdf:
            return .red
        case .plainText, .xml:
            return .secondary
        case .binary:
            return .gray
        }
    }

    /// Human-readable description
    var displayName: String {
        switch self {
        case .markdown:
            return "Markdown"
        case .html:
            return "HTML"
        case .yaml:
            return "YAML"
        case .toml:
            return "TOML"
        case .json:
            return "JSON"
        case .css:
            return "CSS"
        case .javascript:
            return "JavaScript"
        case .typescript:
            return "TypeScript"
        case .scss:
            return "SCSS"
        case .sass:
            return "Sass"
        case .less:
            return "Less"
        case .image:
            return "Image"
        case .video:
            return "Video"
        case .audio:
            return "Audio"
        case .pdf:
            return "PDF"
        case .plainText:
            return "Plain Text"
        case .xml:
            return "XML"
        case .go:
            return "Go Template"
        case .binary:
            return "Binary"
        }
    }
}

// MARK: - Hugo Directory Role

/// Represents the role of a directory in a Hugo site structure
enum HugoRole: String, CaseIterable, Equatable {
    case content      // content/ - markdown content
    case layouts      // layouts/ - HTML templates
    case staticFiles  // static/ - static assets copied as-is
    case assets       // assets/ - processed assets (scss, js, etc.)
    case data         // data/ - data files
    case archetypes   // archetypes/ - content templates
    case i18n         // i18n/ - translations
    case themes       // themes/ - theme files
    case config       // config/ - configuration directory
    case root         // Root level files (hugo.toml, etc.)

    /// Initialize from directory name
    init?(directoryName: String) {
        switch directoryName.lowercased() {
        case "content":
            self = .content
        case "layouts":
            self = .layouts
        case "static":
            self = .staticFiles
        case "assets":
            self = .assets
        case "data":
            self = .data
        case "archetypes":
            self = .archetypes
        case "i18n":
            self = .i18n
        case "themes":
            self = .themes
        case "config":
            self = .config
        default:
            return nil
        }
    }

    /// Accent color for this Hugo role in the sidebar
    var accentColor: Color {
        switch self {
        case .content:
            return .blue
        case .layouts:
            return .purple
        case .staticFiles:
            return .gray
        case .assets:
            return .cyan
        case .data:
            return .green
        case .archetypes:
            return .orange
        case .i18n:
            return .yellow
        case .themes:
            return .pink
        case .config:
            return .orange
        case .root:
            return .secondary
        }
    }

    /// SF Symbol for this role
    var systemImage: String {
        switch self {
        case .content:
            return "doc.text"
        case .layouts:
            return "rectangle.3.group"
        case .staticFiles:
            return "folder"
        case .assets:
            return "paintpalette"
        case .data:
            return "tablecells"
        case .archetypes:
            return "doc.badge.plus"
        case .i18n:
            return "globe"
        case .themes:
            return "paintbrush.pointed"
        case .config:
            return "gearshape"
        case .root:
            return "folder"
        }
    }

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .content:
            return "Content"
        case .layouts:
            return "Layouts"
        case .staticFiles:
            return "Static"
        case .assets:
            return "Assets"
        case .data:
            return "Data"
        case .archetypes:
            return "Archetypes"
        case .i18n:
            return "Translations"
        case .themes:
            return "Themes"
        case .config:
            return "Config"
        case .root:
            return "Root"
        }
    }
}
