import Foundation

/// Service for parsing Hugo template files and extracting metadata
class TemplateParser {
    static let shared = TemplateParser()

    private init() {}

    // MARK: - Public Methods

    /// Parse a template file and return a Template object with metadata
    func parseTemplate(at url: URL) async throws -> Template {
        let content = try String(contentsOf: url, encoding: .utf8)
        return parseTemplate(content: content, url: url)
    }

    /// Parse template content and extract metadata
    func parseTemplate(content: String, url: URL) -> Template {
        let metadata = extractMetadata(from: content)
        let templateType = Template.detectType(from: url)
        let (isTheme, themeName) = detectThemeInfo(from: url)

        return Template(
            url: url,
            content: content,
            metadata: metadata,
            templateType: templateType,
            isThemeTemplate: isTheme,
            themeName: themeName
        )
    }

    /// Extract metadata from template content
    func extractMetadata(from content: String) -> TemplateMetadata {
        var metadata = TemplateMetadata()

        // Extract blocks (define and block statements)
        metadata.blocks = extractBlocks(from: content)
        metadata.definesBlocks = metadata.blocks.contains { $0.isDefinition }
        metadata.hasBaseTemplate = metadata.blocks.contains { !$0.isDefinition }

        // Extract partial references
        metadata.partials = extractPartials(from: content)

        // Extract function usage
        metadata.functions = extractFunctions(from: content)

        // Extract variable access
        metadata.variables = extractVariables(from: content)

        // Check for shortcode patterns
        metadata.shortcodesUsed = extractShortcodePatterns(from: content)

        return metadata
    }

    /// Save a template to disk
    func save(_ template: Template) async throws {
        try template.content.write(to: template.url, atomically: true, encoding: .utf8)
        await MainActor.run {
            template.markAsSaved()
        }
    }

    // MARK: - Private Extraction Methods

    /// Extract block definitions and usages
    private func extractBlocks(from content: String) -> [TemplateBlock] {
        var blocks: [TemplateBlock] = []
        let lines = content.components(separatedBy: .newlines)

        // Pattern for {{ define "blockname" }}
        let definePattern = #/\{\{\s*define\s+"([^"]+)"\s*\}\}/#
        // Pattern for {{ block "blockname" . }}
        let blockPattern = #/\{\{\s*block\s+"([^"]+)"\s*\.?\s*\}\}/#

        for (lineIndex, line) in lines.enumerated() {
            // Check for define statements
            if let match = line.firstMatch(of: definePattern) {
                blocks.append(TemplateBlock(
                    name: String(match.1),
                    isDefinition: true,
                    lineNumber: lineIndex + 1
                ))
            }

            // Check for block statements
            if let match = line.firstMatch(of: blockPattern) {
                blocks.append(TemplateBlock(
                    name: String(match.1),
                    isDefinition: false,
                    lineNumber: lineIndex + 1
                ))
            }
        }

        return blocks
    }

    /// Extract partial template references
    private func extractPartials(from content: String) -> [PartialReference] {
        var partials: [PartialReference] = []
        let lines = content.components(separatedBy: .newlines)

        // Pattern for {{ partial "name.html" . }} or {{ partial "name.html" $context }}
        let partialPattern = #/\{\{(?:-)?\s*partial(?:Cached)?\s+"([^"]+)"(?:\s+(\S+))?\s*(?:-)?\}\}/#

        for (lineIndex, line) in lines.enumerated() {
            for match in line.matches(of: partialPattern) {
                let name = String(match.1)
                let context = match.2.map { String($0) }
                let hasContext = context != nil && context != "."

                partials.append(PartialReference(
                    name: name,
                    lineNumber: lineIndex + 1,
                    hasContext: hasContext
                ))
            }
        }
        return partials
    }

    /// Extract template function usage with counts
    private func extractFunctions(from content: String) -> [TemplateFunctionUsage] {
        var functionCounts: [String: Int] = [:]

        // Common Go template functions to look for
        let functions = [
            "if", "else", "with", "range", "end", "block", "define", "template",
            "eq", "ne", "lt", "le", "gt", "ge", "and", "or", "not",
            "print", "printf", "println", "len", "index", "slice",
            "lower", "upper", "title", "trim", "replace", "split",
            "partial", "partialCached", "return",
            "safeHTML", "safeCSS", "safeJS", "safeURL",
            "markdownify", "plainify", "htmlUnescape",
            "absURL", "relURL", "ref", "relref",
            "dict", "append", "merge",
            "isset", "default", "cond",
            "now", "dateFormat", "time",
            "readDir", "readFile", "getenv",
            "where", "first", "last", "after", "sort", "uniq",
            "hugo", "site", "resources"
        ]

        for function in functions {
            // Pattern: {{ function or {{ .Method | function or (function
            let patterns = [
                #/\{\{\s*\#(function)\b/#,
                #/\|\s*\#(function)\b/#,
                #/\(\s*\#(function)\b/#
            ]

            // Simple word boundary search
            let escapedFunc = NSRegularExpression.escapedPattern(for: function)
            let pattern = "\\{\\{\\s*\(escapedFunc)\\b|\\|\\s*\(escapedFunc)\\b|\\(\\s*\(escapedFunc)\\b"

            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(content.startIndex..., in: content)
                let count = regex.numberOfMatches(in: content, options: [], range: range)
                if count > 0 {
                    functionCounts[function] = count
                }
            }
        }

        return functionCounts.map { TemplateFunctionUsage(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// Extract variable access patterns
    private func extractVariables(from content: String) -> [TemplateVariable] {
        var variableCounts: [String: Int] = [:]

        // Pattern for .Variable, .Params.something, $var
        // Matches: .Title, .Content, .Params.author, .Site.Title, $myVar
        let variablePattern = #/(\.[A-Z][a-zA-Z0-9_.]*|\$[a-zA-Z_][a-zA-Z0-9_]*)/#

        for match in content.matches(of: variablePattern) {
            let variable = String(match.1)
            variableCounts[variable, default: 0] += 1
        }

        return variableCounts.map { TemplateVariable(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// Extract shortcode-specific patterns (for shortcode templates)
    private func extractShortcodePatterns(from content: String) -> [String] {
        var patterns: [String] = []

        // Check for .Inner (shortcode content)
        if content.contains(".Inner") {
            patterns.append(".Inner")
        }

        // Check for .Get (shortcode parameters)
        if content.contains(".Get") {
            patterns.append(".Get")
        }

        // Check for .Params (shortcode named params)
        if content.contains(".Params") && content.contains("shortcode") {
            patterns.append(".Params")
        }

        // Check for .IsNamedParams
        if content.contains(".IsNamedParams") {
            patterns.append(".IsNamedParams")
        }

        // Check for .Page (parent page reference)
        if content.contains(".Page") {
            patterns.append(".Page")
        }

        return patterns
    }

    /// Detect if template is from a theme and extract theme name
    private func detectThemeInfo(from url: URL) -> (isTheme: Bool, themeName: String?) {
        let path = url.path

        // Check if path contains /themes/
        if let range = path.range(of: "/themes/") {
            let afterThemes = String(path[range.upperBound...])
            // Theme name is the first path component after /themes/
            let components = afterThemes.split(separator: "/")
            if let themeName = components.first {
                return (true, String(themeName))
            }
            return (true, nil)
        }

        return (false, nil)
    }
}

// MARK: - Template Discovery

extension TemplateParser {

    /// Discover all templates in a Hugo site
    func discoverTemplates(in siteURL: URL) async throws -> [Template] {
        var templates: [Template] = []

        // Scan layouts/ directory
        let layoutsURL = siteURL.appendingPathComponent("layouts")
        if FileManager.default.fileExists(atPath: layoutsURL.path) {
            let layoutTemplates = try await scanDirectory(layoutsURL, isTheme: false, themeName: nil)
            templates.append(contentsOf: layoutTemplates)
        }

        // Scan themes/ directory
        let themesURL = siteURL.appendingPathComponent("themes")
        if FileManager.default.fileExists(atPath: themesURL.path) {
            // Get list of themes
            let themeContents = try FileManager.default.contentsOfDirectory(
                at: themesURL,
                includingPropertiesForKeys: [.isDirectoryKey]
            )

            for themeURL in themeContents {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: themeURL.path, isDirectory: &isDir), isDir.boolValue {
                    let themeName = themeURL.lastPathComponent
                    let themeLayoutsURL = themeURL.appendingPathComponent("layouts")

                    if FileManager.default.fileExists(atPath: themeLayoutsURL.path) {
                        let themeTemplates = try await scanDirectory(
                            themeLayoutsURL,
                            isTheme: true,
                            themeName: themeName
                        )
                        templates.append(contentsOf: themeTemplates)
                    }
                }
            }
        }

        return templates
    }

    /// Scan a directory for template files
    private func scanDirectory(_ url: URL, isTheme: Bool, themeName: String?) async throws -> [Template] {
        var templates: [Template] = []

        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            // Only process .html files
            guard fileURL.pathExtension.lowercased() == "html" else { continue }

            do {
                var template = try await parseTemplate(at: fileURL)
                template.isThemeTemplate = isTheme
                template.themeName = themeName
                templates.append(template)
            } catch {
                Logger.shared.error("Failed to parse template: \(fileURL.path) - \(error)")
            }
        }

        return templates
    }
}

// MARK: - Template Analysis

extension TemplateParser {

    /// Analyze template dependencies (which templates use which partials)
    func analyzeDependencies(templates: [Template]) -> [UUID: Set<String>] {
        var dependencies: [UUID: Set<String>] = [:]

        for template in templates {
            let partialNames = Set(template.metadata.partials.map { $0.name })
            if !partialNames.isEmpty {
                dependencies[template.id] = partialNames
            }
        }

        return dependencies
    }

    /// Find templates that extend a base template (use blocks)
    func findExtendingTemplates(templates: [Template]) -> [Template] {
        templates.filter { $0.metadata.hasBaseTemplate }
    }

    /// Find base templates (define blocks)
    func findBaseTemplates(templates: [Template]) -> [Template] {
        templates.filter { $0.templateType == .base || $0.metadata.definesBlocks }
    }

    /// Get all unique partials referenced across templates
    func getAllPartialReferences(templates: [Template]) -> [String: Int] {
        var partialCounts: [String: Int] = [:]

        for template in templates {
            for partial in template.metadata.partials {
                partialCounts[partial.name, default: 0] += 1
            }
        }

        return partialCounts
    }
}
