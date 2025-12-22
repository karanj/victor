import Foundation
import Down

/// Service for rendering markdown content to HTML
@MainActor
class MarkdownRenderer {
    static let shared = MarkdownRenderer()

    private init() {}

    // MARK: - Rendering

    /// Convert markdown string to styled HTML (strips frontmatter first)
    func render(markdown: String) -> Result<String, RenderError> {
        do {
            // Strip frontmatter before rendering
            let markdownWithoutFrontmatter = stripFrontmatter(from: markdown)

            // Convert markdown to HTML using Down
            let down = Down(markdownString: markdownWithoutFrontmatter)
            let htmlBody = try down.toHTML()

            // Wrap in full HTML document with CSS
            let fullHTML = wrapInHTMLTemplate(htmlBody: htmlBody)

            return .success(fullHTML)
        } catch {
            return .failure(.conversionFailed(error.localizedDescription))
        }
    }

    // MARK: - Frontmatter Handling

    /// Strip frontmatter delimiters and content from markdown
    /// TODO: this should use the Frontmatter model and handle it in a common way. This shouldn't be being reimplemented here.
    /// TODO: this needs to return the title and stick that at the top of the preview HTML
    /// Supports YAML (---), TOML (+++), and JSON ({})
    private func stripFrontmatter(from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)

        guard !lines.isEmpty else { return content }

        let firstLine = lines[0].trimmingCharacters(in: .whitespaces)

        // Check for YAML frontmatter (---)
        if firstLine == "---" {
            return stripDelimitedFrontmatter(from: lines, delimiter: "---", startIndex: 1)
        }

        // Check for TOML frontmatter (+++)
        if firstLine == "+++" {
            return stripDelimitedFrontmatter(from: lines, delimiter: "+++", startIndex: 1)
        }

        // Check for JSON frontmatter ({)
        if firstLine.hasPrefix("{") {
            return stripJSONFrontmatter(from: lines)
        }

        // No frontmatter found
        return content
    }

    /// Strip frontmatter with delimiters (YAML or TOML)
    private func stripDelimitedFrontmatter(from lines: [String], delimiter: String, startIndex: Int) -> String {
        // Find closing delimiter
        for i in startIndex..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line == delimiter {
                // Found closing delimiter, return content after it
                let remainingLines = Array(lines[(i + 1)...])
                return remainingLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // No closing delimiter found, return original
        return lines.joined(separator: "\n")
    }

    /// Strip JSON frontmatter (less common, but supported by some Hugo themes)
    private func stripJSONFrontmatter(from lines: [String]) -> String {
        var braceCount = 0

        for (index, line) in lines.enumerated() {
            for char in line {
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                    if braceCount == 0 {
                        // Found end of JSON frontmatter
                        let remainingLines = Array(lines[(index + 1)...])
                        return remainingLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }

        // No complete JSON found, return original
        return lines.joined(separator: "\n")
    }

    /// Convert markdown to HTML and handle errors by returning error HTML
    func renderOrError(markdown: String) -> String {
        switch render(markdown: markdown) {
        case .success(let html):
            return html
        case .failure(let error):
            return errorHTML(message: error.localizedDescription)
        }
    }

    // MARK: - HTML Templates

    /// Wrap HTML body in full document with CSS
    /// TODO: investigate if we can load the CSS from the Hugo theme so that the preview is closer to realistic?
    private func wrapInHTMLTemplate(htmlBody: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Preview</title>
            <style>
                \(githubStyleCSS)
            </style>
        </head>
        <body>
            <div class="markdown-body">
                \(htmlBody)
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

    /// GitHub-flavored markdown CSS
    /// TODO: can we refactor this to be a separate static resource? this is content, it should be outside the code logic of the render
    private var githubStyleCSS: String {
        return """
        /* GitHub-inspired markdown styling */
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
            font-size: 16px;
            line-height: 1.6;
            color: #24292e;
            background-color: #ffffff;
            margin: 0;
            padding: 0;
        }

        .markdown-body {
            box-sizing: border-box;
            min-width: 200px;
            max-width: 980px;
            margin: 0 auto;
            padding: 45px;
        }

        /* Dark mode support */
        @media (prefers-color-scheme: dark) {
            body {
                color: #c9d1d9;
                background-color: #0d1117;
            }
            .markdown-body {
                color: #c9d1d9;
            }
            .markdown-body code {
                background-color: rgba(110,118,129,0.4);
            }
            .markdown-body pre {
                background-color: rgba(110,118,129,0.1);
            }
        }

        /* Headings */
        .markdown-body h1,
        .markdown-body h2,
        .markdown-body h3,
        .markdown-body h4,
        .markdown-body h5,
        .markdown-body h6 {
            margin-top: 24px;
            margin-bottom: 16px;
            font-weight: 600;
            line-height: 1.25;
        }

        .markdown-body h1 {
            font-size: 2em;
            border-bottom: 1px solid #e1e4e8;
            padding-bottom: 0.3em;
        }

        .markdown-body h2 {
            font-size: 1.5em;
            border-bottom: 1px solid #e1e4e8;
            padding-bottom: 0.3em;
        }

        .markdown-body h3 { font-size: 1.25em; }
        .markdown-body h4 { font-size: 1em; }
        .markdown-body h5 { font-size: 0.875em; }
        .markdown-body h6 {
            font-size: 0.85em;
            color: #6a737d;
        }

        /* Paragraphs */
        .markdown-body p {
            margin-top: 0;
            margin-bottom: 16px;
        }

        /* Links */
        .markdown-body a {
            color: #0366d6;
            text-decoration: none;
        }

        .markdown-body a:hover {
            text-decoration: underline;
        }

        /* Lists */
        .markdown-body ul,
        .markdown-body ol {
            padding-left: 2em;
            margin-top: 0;
            margin-bottom: 16px;
        }

        .markdown-body li {
            margin-top: 0.25em;
        }

        /* Code */
        .markdown-body code {
            padding: 0.2em 0.4em;
            margin: 0;
            font-size: 85%;
            background-color: rgba(27,31,35,0.05);
            border-radius: 3px;
            font-family: "SF Mono", Monaco, "Cascadia Code", "Courier New", monospace;
        }

        .markdown-body pre {
            padding: 16px;
            overflow: auto;
            font-size: 85%;
            line-height: 1.45;
            background-color: #f6f8fa;
            border-radius: 6px;
            margin-bottom: 16px;
        }

        .markdown-body pre code {
            display: block;
            padding: 0;
            margin: 0;
            overflow: visible;
            line-height: inherit;
            word-wrap: normal;
            background-color: transparent;
            border: 0;
        }

        /* Blockquotes */
        .markdown-body blockquote {
            padding: 0 1em;
            color: #6a737d;
            border-left: 0.25em solid #dfe2e5;
            margin: 0 0 16px 0;
        }

        /* Horizontal rule */
        .markdown-body hr {
            height: 0.25em;
            padding: 0;
            margin: 24px 0;
            background-color: #e1e4e8;
            border: 0;
        }

        /* Tables */
        .markdown-body table {
            border-spacing: 0;
            border-collapse: collapse;
            margin-bottom: 16px;
        }

        .markdown-body table th,
        .markdown-body table td {
            padding: 6px 13px;
            border: 1px solid #dfe2e5;
        }

        .markdown-body table th {
            font-weight: 600;
            background-color: #f6f8fa;
        }

        .markdown-body table tr {
            background-color: #ffffff;
            border-top: 1px solid #c6cbd1;
        }

        .markdown-body table tr:nth-child(2n) {
            background-color: #f6f8fa;
        }

        /* Images */
        .markdown-body img {
            max-width: 100%;
            box-sizing: content-box;
            background-color: #ffffff;
        }

        /* Task lists */
        .markdown-body input[type="checkbox"] {
            margin-right: 0.5em;
        }
        """
    }
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
