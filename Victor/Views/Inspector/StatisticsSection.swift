import SwiftUI

/// Statistics section for the inspector panel
/// Shows word count, character count, reading time, and file dates
struct StatisticsSection: View {
    let content: String
    let contentFile: ContentFile

    /// Words per minute for reading time estimate
    private let wordsPerMinute = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Word and character counts
            StatRow(label: "Words", value: "\(wordCount)")
            StatRow(label: "Characters", value: "\(characterCount)")
            StatRow(label: "Reading time", value: readingTime)

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

            if let paragraphs = paragraphCount, paragraphs > 0 {
                StatRow(label: "Paragraphs", value: "\(paragraphs)")
            }

            if let sentences = sentenceCount, sentences > 0 {
                StatRow(label: "Sentences", value: "\(sentences)")
            }
        }
    }

    // MARK: - Computed Properties

    private var wordCount: Int {
        content
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    private var characterCount: Int {
        content.count
    }

    private var readingTime: String {
        let minutes = max(1, wordCount / wordsPerMinute)
        if minutes == 1 {
            return "~1 min"
        } else {
            return "~\(minutes) mins"
        }
    }

    private var paragraphCount: Int? {
        let paragraphs = content
            .components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
        return paragraphs > 0 ? paragraphs : nil
    }

    private var sentenceCount: Int? {
        // Simple sentence counting (ends with . ! ?)
        let pattern = "[.!?]"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(content.startIndex..., in: content)
        let count = regex?.numberOfMatches(in: content, range: range) ?? 0
        return count > 0 ? count : nil
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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

    StatisticsSection(content: sampleContent, contentFile: contentFile)
        .padding()
        .frame(width: 260)
}
