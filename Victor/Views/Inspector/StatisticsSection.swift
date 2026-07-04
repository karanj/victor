import SwiftUI

/// Cached document statistics for the inspector panel
/// Computed asynchronously and debounced to avoid performance impact during typing
struct DocumentStats: Equatable {
    var wordCount: Int = 0
    var characterCount: Int = 0
    var paragraphCount: Int = 0
    var sentenceCount: Int = 0

    /// Words per minute for reading time estimate
    private static let wordsPerMinute = 200

    var readingTime: String {
        let minutes = max(1, wordCount / Self.wordsPerMinute)
        if minutes == 1 {
            return "~1 min"
        } else {
            return "~\(minutes) mins"
        }
    }

    /// Compute statistics from content string
    /// This is intentionally a static method to be called off the main actor if needed
    static func compute(from content: String) -> DocumentStats {
        var stats = DocumentStats()

        stats.characterCount = content.count

        stats.wordCount = content
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count

        stats.paragraphCount = content
            .components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count

        // Simple sentence counting (ends with . ! ?)
        let pattern = "[.!?]"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(content.startIndex..., in: content)
            stats.sentenceCount = regex.numberOfMatches(in: content, range: range)
        }

        return stats
    }
}

/// Statistics section for the inspector panel
/// Shows word count, character count, reading time, and file dates
struct StatisticsSection: View {
    let stats: DocumentStats
    let contentFile: ContentFile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Word and character counts
            StatRow(label: "Words", value: "\(stats.wordCount)")
            StatRow(label: "Characters", value: "\(stats.characterCount)")
            StatRow(label: "Reading time", value: stats.readingTime)

            Divider()
                .padding(.vertical, 4)

            // File dates
            StatRow(label: "Modified", value: formatDate(contentFile.lastModified))

            // File info
            Divider()
                .padding(.vertical, 4)

            if let frontmatter = contentFile.frontmatter {
                StatRow(label: "Format", value: frontmatter.format.displayName)
            }

            if stats.paragraphCount > 0 {
                StatRow(label: "Paragraphs", value: "\(stats.paragraphCount)")
            }

            if stats.sentenceCount > 0 {
                StatRow(label: "Sentences", value: "\(stats.sentenceCount)")
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Stat Row

/// Single row in the statistics section
struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Frontmatter Format Extension

extension FrontmatterFormat {
    var displayName: String {
        switch self {
        case .yaml: return "YAML"
        case .toml: return "TOML"
        case .json: return "JSON"
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleContent = """
    # Hello World

    This is a sample blog post with some content.
    It has multiple sentences. And paragraphs too!

    Here is another paragraph with more text.
    """

    let contentFile = ContentFile(
        url: URL(fileURLWithPath: "/sample.md"),
        markdownContent: sampleContent
    )

    let stats = DocumentStats.compute(from: sampleContent)

    StatisticsSection(stats: stats, contentFile: contentFile)
        .padding()
        .frame(width: 260)
}
