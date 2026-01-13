import Foundation

/// Service for parsing Hugo build output and extracting structured errors
enum BuildErrorParser {

    // MARK: - Error Patterns

    /// Regex pattern for Hugo error lines with file location
    /// Examples:
    /// - ERROR 2024/01/15 10:30:00 Error building site: ...
    /// - Error: error building site: "/path/to/file.html:42:13": ...
    /// - Error building site: parse failed: template: shortcodes/gallery.html:10: ...
    private static let errorPatterns: [(pattern: String, level: HugoBuildError.Level)] = [
        // Standard Hugo ERROR log format
        (#"^ERROR\s+\d{4}/\d{2}/\d{2}\s+\d{2}:\d{2}:\d{2}\s+(.+)"#, .error),
        // Error building site with file reference
        (#"^Error.*building site.*\"([^\"]+):(\d+)(?::\d+)?\".*:\s*(.+)"#, .error),
        // Template parse error
        (#"^.*template:\s*([^:]+):(\d+):\s*(.+)"#, .error),
        // Generic error line
        (#"^[Ee]rror:?\s+(.+)"#, .error),
        // WARN log format
        (#"^WARN\s+\d{4}/\d{2}/\d{2}\s+\d{2}:\d{2}:\d{2}\s+(.+)"#, .warning),
        // Warning with file
        (#"^[Ww]arning:?\s+(.+)"#, .warning)
    ]

    /// Parse a single line of Hugo output
    /// - Parameter line: A line of Hugo server output
    /// - Returns: A HugoBuildError if the line contains an error/warning, nil otherwise
    static func parseLine(_ line: String) -> HugoBuildError? {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)

        // Skip empty lines
        guard !trimmedLine.isEmpty else { return nil }

        // Check for error/warning indicators
        let hasError = trimmedLine.contains("ERROR") ||
                       trimmedLine.lowercased().contains("error") ||
                       trimmedLine.lowercased().contains("failed")
        let hasWarning = trimmedLine.contains("WARN") ||
                        trimmedLine.lowercased().contains("warning")

        guard hasError || hasWarning else { return nil }

        // Try to extract file location
        let (file, lineNum) = extractFileLocation(from: trimmedLine)

        // Determine severity
        let level: HugoBuildError.Level
        if hasError && !hasWarning {
            level = .error
        } else if hasWarning && !hasError {
            level = .warning
        } else {
            // Both present - prefer error
            level = trimmedLine.range(of: "error", options: .caseInsensitive)?.lowerBound ?? trimmedLine.endIndex <
                    (trimmedLine.range(of: "warn", options: .caseInsensitive)?.lowerBound ?? trimmedLine.endIndex)
                    ? .error : .warning
        }

        // Clean up message
        let message = cleanMessage(trimmedLine)

        return HugoBuildError(
            level: level,
            message: message,
            file: file,
            line: lineNum,
            timestamp: Date()
        )
    }

    /// Extract file path and line number from an error message
    /// - Parameter text: The error message text
    /// - Returns: Tuple of optional file path and line number
    static func extractFileLocation(from text: String) -> (file: String?, line: Int?) {
        // Pattern 1: "path/to/file.ext:123" or "path/to/file.ext:123:45"
        let fileLinePattern = #"([\/\w\-\.]+\.[a-zA-Z0-9]+):(\d+)(?::\d+)?"#
        if let regex = try? NSRegularExpression(pattern: fileLinePattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            var file: String?
            var line: Int?

            if let fileRange = Range(match.range(at: 1), in: text) {
                file = String(text[fileRange])
            }
            if let lineRange = Range(match.range(at: 2), in: text) {
                line = Int(text[lineRange])
            }

            return (file, line)
        }

        // Pattern 2: template: filename.html:123
        let templatePattern = #"template:\s*([^:]+):(\d+)"#
        if let regex = try? NSRegularExpression(pattern: templatePattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            var file: String?
            var line: Int?

            if let fileRange = Range(match.range(at: 1), in: text) {
                file = String(text[fileRange]).trimmingCharacters(in: .whitespaces)
            }
            if let lineRange = Range(match.range(at: 2), in: text) {
                line = Int(text[lineRange])
            }

            return (file, line)
        }

        return (nil, nil)
    }

    /// Clean up an error message by removing timestamps and log prefixes
    /// - Parameter message: Raw error message
    /// - Returns: Cleaned message
    static func cleanMessage(_ message: String) -> String {
        var cleaned = message

        // Remove Hugo timestamp prefix (ERROR 2024/01/15 10:30:00)
        let timestampPattern = #"^(ERROR|WARN|INFO)\s+\d{4}/\d{2}/\d{2}\s+\d{2}:\d{2}:\d{2}\s+"#
        if let regex = try? NSRegularExpression(pattern: timestampPattern) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }

        // Trim whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)

        return cleaned
    }

    /// Parse multiple lines of Hugo output
    /// - Parameter output: Multi-line Hugo output string
    /// - Returns: Array of parsed build errors
    static func parseOutput(_ output: String) -> [HugoBuildError] {
        output
            .components(separatedBy: .newlines)
            .compactMap { parseLine($0) }
    }

    /// Check if a line indicates Hugo server is ready
    /// - Parameter line: A line of Hugo output
    /// - Returns: Port number if server is ready, nil otherwise
    static func parseServerReady(_ line: String) -> Int? {
        // Look for: "Web Server is available at http://localhost:1313/"
        guard line.contains("Web Server is available") else { return nil }

        let portPattern = #":(\d+)/?"#
        if let regex = try? NSRegularExpression(pattern: portPattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let portRange = Range(match.range(at: 1), in: line) {
            return Int(line[portRange])
        }

        return nil
    }

    /// Check if a line indicates Hugo is rebuilding
    /// - Parameter line: A line of Hugo output
    /// - Returns: true if Hugo is rebuilding
    static func isRebuildingLine(_ line: String) -> Bool {
        line.contains("Change detected") ||
        line.contains("Rebuilding site") ||
        line.contains("change detected")
    }

    /// Check if a line indicates build completion
    /// - Parameter line: A line of Hugo output
    /// - Returns: Build time in milliseconds if completed, nil otherwise
    static func parseBuildComplete(_ line: String) -> Int? {
        // Look for: "Total in 123 ms"
        guard line.contains("Total in") && line.contains("ms") else { return nil }

        let timePattern = #"Total in\s+(\d+)\s*ms"#
        if let regex = try? NSRegularExpression(pattern: timePattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let timeRange = Range(match.range(at: 1), in: line) {
            return Int(line[timeRange])
        }

        return nil
    }
}
