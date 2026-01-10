import AppKit
import Highlightr

/// Service for syntax highlighting using Highlightr library
/// Supports multiple languages and custom Go template highlighting
@MainActor
class SyntaxHighlighter {
    static let shared = SyntaxHighlighter()

    private let highlightr: Highlightr?

    private init() {
        self.highlightr = Highlightr()

        // Set default theme based on appearance
        updateTheme()

        // Listen for appearance changes
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(appearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - Theme Management

    @objc private func appearanceChanged() {
        updateTheme()
    }

    private func updateTheme() {
        let appearance = NSApp.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        highlightr?.setTheme(to: isDark ? "atom-one-dark" : "atom-one-light")
    }

    /// Manually refresh theme (call after appearance changes)
    func refreshTheme() {
        updateTheme()
    }

    // MARK: - Language Mapping

    /// Map FileType to Highlightr language identifier
    func languageName(for fileType: FileType) -> String? {
        switch fileType {
        case .yaml:
            return "yaml"
        case .toml:
            return "ini" // Closest match for TOML
        case .json:
            return "json"
        case .html:
            return "xml" // HTML/XML highlighting
        case .css:
            return "css"
        case .scss, .sass:
            return "scss"
        case .less:
            return "less"
        case .javascript:
            return "javascript"
        case .typescript:
            return "typescript"
        case .go:
            return "go"
        case .xml:
            return "xml"
        case .markdown:
            return nil // Not highlighting markdown content
        case .plainText, .image, .video, .audio, .pdf, .binary:
            return nil
        }
    }

    // MARK: - Highlighting

    /// Highlight code with the specified language
    /// - Parameters:
    ///   - code: Source code string
    ///   - language: Highlightr language identifier (e.g., "yaml", "json")
    /// - Returns: Attributed string with syntax highlighting, or nil if highlighting fails
    func highlight(code: String, language: String) -> NSAttributedString? {
        guard let highlightr = highlightr else {
            Logger.shared.warning("[SyntaxHighlighter] Highlightr not initialized")
            return nil
        }
        return highlightr.highlight(code, as: language)
    }

    /// Highlight code based on FileType
    /// - Parameters:
    ///   - code: Source code string
    ///   - fileType: The file type to determine language
    /// - Returns: Attributed string with syntax highlighting, or nil if no highlighting for this type
    func highlight(code: String, fileType: FileType) -> NSAttributedString? {
        guard let language = languageName(for: fileType) else {
            return nil
        }
        return highlight(code: code, language: language)
    }

    /// Highlight Go/Hugo template code (HTML with Go template syntax)
    /// Uses Highlightr for HTML base and adds custom Go template patterns
    /// - Parameter code: Template source code
    /// - Returns: Attributed string with combined highlighting
    func highlightGoTemplate(code: String) -> NSAttributedString {
        // Start with Highlightr's HTML/XML highlighting
        let attributedString: NSMutableAttributedString

        if let highlighted = highlight(code: code, language: "xml") {
            attributedString = NSMutableAttributedString(attributedString: highlighted)
        } else {
            // Fallback if highlighting fails
            attributedString = NSMutableAttributedString(string: code)
            attributedString.addAttribute(
                .foregroundColor,
                value: NSColor.textColor,
                range: NSRange(location: 0, length: attributedString.length)
            )
        }

        // Layer Go template highlighting on top
        applyGoTemplateHighlighting(to: attributedString, text: code)

        return attributedString
    }

    // MARK: - Go Template Custom Highlighting

    /// Apply Go template syntax highlighting on top of existing HTML highlighting
    private func applyGoTemplateHighlighting(to attrString: NSMutableAttributedString, text: String) {
        // Colors for Go template syntax
        let delimiterColor = NSColor.systemPurple
        let keywordColor = NSColor.systemBlue
        let variableColor = NSColor.systemTeal
        let commentColor = NSColor.systemGray
        let stringColor = NSColor.systemGreen

        // 1. Go template comments {{/* */}} - highlight entire comment
        if let commentRegex = try? NSRegularExpression(pattern: "\\{\\{/\\*[\\s\\S]*?\\*/\\}\\}", options: []) {
            let matches = commentRegex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
            for match in matches {
                attrString.addAttribute(.foregroundColor, value: commentColor, range: match.range)
            }
        }

        // 2. Template delimiters {{ and }} (including {{- and -}})
        if let delimRegex = try? NSRegularExpression(pattern: "\\{\\{-?|-?\\}\\}", options: []) {
            let matches = delimRegex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
            for match in matches {
                attrString.addAttribute(.foregroundColor, value: delimiterColor, range: match.range)
            }
        }

        // 3. Keywords after {{ or {{-
        let keywords = ["if", "else", "end", "range", "with", "define", "block", "template", "partial", "return", "and", "or", "not", "eq", "ne", "lt", "le", "gt", "ge"]
        for keyword in keywords {
            let pattern = "\\{\\{-?\\s*(\(keyword))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
                for match in matches {
                    if match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound {
                        attrString.addAttribute(.foregroundColor, value: keywordColor, range: match.range(at: 1))
                    }
                }
            }
        }

        // 4. Variables starting with . or $ (e.g., .Title, .Params.author, $myVar)
        if let varRegex = try? NSRegularExpression(pattern: "\\.[A-Z][a-zA-Z0-9_.]*|\\$[a-zA-Z_][a-zA-Z0-9_]*", options: []) {
            let matches = varRegex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
            for match in matches {
                attrString.addAttribute(.foregroundColor, value: variableColor, range: match.range)
            }
        }

        // 5. Strings in double quotes within template blocks
        // Find all template blocks first, then highlight strings within them
        if let templateBlockRegex = try? NSRegularExpression(pattern: "\\{\\{[^}]*\\}\\}", options: []) {
            let blockMatches = templateBlockRegex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))

            for blockMatch in blockMatches {
                // Find strings within this block
                if let stringRange = Range(blockMatch.range, in: text) {
                    let blockText = String(text[stringRange])
                    if let stringRegex = try? NSRegularExpression(pattern: "\"[^\"]*\"", options: []) {
                        let stringMatches = stringRegex.matches(in: blockText, options: [], range: NSRange(location: 0, length: blockText.utf16.count))
                        for stringMatch in stringMatches {
                            let absoluteRange = NSRange(
                                location: blockMatch.range.location + stringMatch.range.location,
                                length: stringMatch.range.length
                            )
                            attrString.addAttribute(.foregroundColor, value: stringColor, range: absoluteRange)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Apply to Text Storage

    /// Apply syntax highlighting to an NSTextStorage
    /// - Parameters:
    ///   - textStorage: The text storage to highlight
    ///   - language: Highlightr language identifier
    ///   - font: Font to use (preserves monospace)
    func applyHighlighting(to textStorage: NSTextStorage, language: String, font: NSFont) {
        let code = textStorage.string

        if let highlighted = highlight(code: code, language: language) {
            // Preserve cursor position by using beginEditing/endEditing
            textStorage.beginEditing()
            textStorage.setAttributedString(highlighted)
            // Ensure font is consistent
            textStorage.addAttribute(.font, value: font, range: NSRange(location: 0, length: textStorage.length))
            textStorage.endEditing()
        }
    }

    /// Apply Go template highlighting to an NSTextStorage
    func applyGoTemplateHighlighting(to textStorage: NSTextStorage, font: NSFont) {
        let code = textStorage.string
        let highlighted = highlightGoTemplate(code: code)

        textStorage.beginEditing()
        textStorage.setAttributedString(highlighted)
        textStorage.addAttribute(.font, value: font, range: NSRange(location: 0, length: textStorage.length))
        textStorage.endEditing()
    }

    /// Check if Highlightr is available
    var isAvailable: Bool {
        return highlightr != nil
    }

    /// Get list of available languages
    var availableLanguages: [String] {
        return highlightr?.supportedLanguages() ?? []
    }

    /// Get list of available themes
    var availableThemes: [String] {
        return highlightr?.availableThemes() ?? []
    }
}
