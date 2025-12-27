import Foundation
import Down

/// Service for rendering markdown content to HTML
@MainActor
class MarkdownRenderer {
    static let shared = MarkdownRenderer()

    private init() {}

    // MARK: - Rendering

    /// Convert markdown string to styled HTML (strips frontmatter first)
    /// - Parameters:
    ///   - markdown: The markdown content (may include frontmatter)
    ///   - title: Optional title from frontmatter to render as h1 heading
    func render(markdown: String, title: String? = nil) -> Result<String, RenderError> {
        do {
            // Strip frontmatter before rendering
            let markdownWithoutFrontmatter = stripFrontmatter(from: markdown)

            // Convert markdown to HTML using Down
            let down = Down(markdownString: markdownWithoutFrontmatter)
            let htmlBody = try down.toHTML()

            // Wrap in full HTML document with CSS, including title if provided
            let fullHTML = wrapInHTMLTemplate(htmlBody: htmlBody, title: title)

            return .success(fullHTML)
        } catch {
            return .failure(.conversionFailed(error.localizedDescription))
        }
    }

    // MARK: - Frontmatter Handling

    /// Strip frontmatter delimiters and content from markdown using FrontmatterParser
    /// Supports YAML (---), TOML (+++), and JSON ({})
    private func stripFrontmatter(from content: String) -> String {
        // Use FrontmatterParser to extract just the markdown (no code duplication)
        let (_, markdown) = FrontmatterParser.shared.parseContent(content)
        return markdown
    }

    /// Convert markdown to HTML and handle errors by returning error HTML
    /// - Parameters:
    ///   - markdown: The markdown content (may include frontmatter)
    ///   - title: Optional title from frontmatter to render as h1 heading
    func renderOrError(markdown: String, title: String? = nil) -> String {
        switch render(markdown: markdown, title: title) {
        case .success(let html):
            return html
        case .failure(let error):
            return errorHTML(message: error.localizedDescription)
        }
    }

    // MARK: - HTML Templates

    /// Wrap HTML body in full document with CSS
    /// TODO: investigate if we can load the CSS from the Hugo theme so that the preview is closer to realistic?
    private func wrapInHTMLTemplate(htmlBody: String, title: String? = nil) -> String {
        // Build title heading if provided
        let titleHTML: String
        if let title = title, !title.isEmpty {
            // Escape HTML entities in title for safety
            let escapedTitle = title
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            titleHTML = "<h1>\(escapedTitle)</h1>\n"
        } else {
            titleHTML = ""
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(title ?? "Preview")</title>
            <style>
                \(githubStyleCSS)
            </style>
        </head>
        <body>
            <div class="markdown-body">
                \(titleHTML)\(htmlBody)
            </div>
        </body>
        </html>
        """
    }

    /// Generate error HTML when rendering fails
    private func errorHTML(message: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Error</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
                    padding: 20px;
                    color: #d73a49;
                    background-color: #ffeef0;
                }
                .error-container {
                    border: 1px solid #d73a49;
                    border-radius: 6px;
                    padding: 16px;
                }
                h2 { margin-top: 0; }
            </style>
        </head>
        <body>
            <div class="error-container">
                <h2>Preview Error</h2>
                <p>\(message)</p>
            </div>
        </body>
        </html>
        """
    }

    // MARK: - CSS Styling

    /// GitHub-flavored markdown CSS loaded from external file
    /// Cached on first access to avoid repeated file I/O
    private lazy var githubStyleCSS: String = {
        loadCSSFromBundle() ?? fallbackCSS
    }()

    /// Load CSS from bundle resources
    private func loadCSSFromBundle() -> String? {
        // Try without subdirectory first (resources are typically copied flat)
        if let cssURL = Bundle.main.url(forResource: "preview-styles", withExtension: "css"),
           let cssContent = try? String(contentsOf: cssURL, encoding: .utf8) {
            return cssContent
        }

        // Fallback: try with subdirectory
        if let cssURL = Bundle.main.url(forResource: "preview-styles", withExtension: "css", subdirectory: "Resources"),
           let cssContent = try? String(contentsOf: cssURL, encoding: .utf8) {
            return cssContent
        }

        print("⚠️ Could not load preview-styles.css from bundle, using fallback")
        return nil
    }

    /// Fallback CSS in case file cannot be loaded
    private let fallbackCSS = """
    body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
        font-size: 16px;
        line-height: 1.6;
        color: #24292e;
        background-color: #ffffff;
        margin: 0;
        padding: 20px;
    }
    .markdown-body {
        max-width: 980px;
        margin: 0 auto;
    }
    """
}

// MARK: - Errors

enum RenderError: LocalizedError {
    case conversionFailed(String)
    case templateNotFound
    case cssNotFound

    var errorDescription: String? {
        switch self {
        case .conversionFailed(let message):
            return "Failed to convert markdown: \(message)"
        case .templateNotFound:
            return "HTML template not found"
        case .cssNotFound:
            return "CSS stylesheet not found"
        }
    }
}
