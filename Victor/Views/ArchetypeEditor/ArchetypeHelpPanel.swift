import SwiftUI

/// Help panel showing available Hugo template variables and functions for archetypes
struct ArchetypeHelpPanel: View {
    @State private var expandedSections: Set<String> = ["variables"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Template Reference")
                        .font(.headline)
                }
                .padding(.bottom, 4)

                Text("Archetypes use Go template syntax. Variables are replaced when creating new content.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                // Variables Section
                HelpSection(
                    title: "Variables",
                    systemImage: "curlybraces",
                    isExpanded: expandedSections.contains("variables"),
                    onToggle: { toggleSection("variables") }
                ) {
                    variablesContent
                }

                // Functions Section
                HelpSection(
                    title: "Functions",
                    systemImage: "function",
                    isExpanded: expandedSections.contains("functions"),
                    onToggle: { toggleSection("functions") }
                ) {
                    functionsContent
                }

                // Examples Section
                HelpSection(
                    title: "Examples",
                    systemImage: "doc.text",
                    isExpanded: expandedSections.contains("examples"),
                    onToggle: { toggleSection("examples") }
                ) {
                    examplesContent
                }

                Spacer()
            }
            .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func toggleSection(_ section: String) {
        if expandedSections.contains(section) {
            expandedSections.remove(section)
        } else {
            expandedSections.insert(section)
        }
    }

    // MARK: - Variables Content

    private var variablesContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpItem(
                variable: ".Title",
                description: "Page title (from filename or --title flag)"
            )
            HelpItem(
                variable: ".Date",
                description: "Current date/time in RFC3339 format"
            )
            HelpItem(
                variable: ".File.ContentBaseName",
                description: "Filename without extension"
            )
            HelpItem(
                variable: ".File.Path",
                description: "Path relative to content directory"
            )
            HelpItem(
                variable: ".File.Dir",
                description: "Directory containing the file"
            )
            HelpItem(
                variable: ".Type",
                description: "Content type from directory name"
            )
            HelpItem(
                variable: ".Site.Title",
                description: "Site title from config"
            )
            HelpItem(
                variable: ".Site.BaseURL",
                description: "Site base URL from config"
            )
        }
    }

    // MARK: - Functions Content

    private var functionsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpItem(
                variable: "replace",
                description: "Replace substring",
                example: "replace .File.ContentBaseName \"-\" \" \""
            )
            HelpItem(
                variable: "title",
                description: "Title case string",
                example: "title .File.ContentBaseName"
            )
            HelpItem(
                variable: "lower",
                description: "Lowercase string",
                example: "lower .Title"
            )
            HelpItem(
                variable: "upper",
                description: "Uppercase string",
                example: "upper .Title"
            )
            HelpItem(
                variable: "urlize",
                description: "URL-safe string",
                example: "urlize .Title"
            )
            HelpItem(
                variable: "time.Now",
                description: "Current time",
                example: "time.Now.Format \"2006-01-02\""
            )
            HelpItem(
                variable: "humanize",
                description: "Human-readable string",
                example: "humanize .File.ContentBaseName"
            )
            HelpItem(
                variable: "default",
                description: "Default value if empty",
                example: "default \"Untitled\" .Title"
            )
        }
    }

    // MARK: - Examples Content

    private var examplesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            ExampleBlock(
                title: "Basic Archetype",
                code: """
                ---
                title: "{{ .Title }}"
                date: {{ .Date }}
                draft: true
                ---

                Write your content here.
                """
            )

            ExampleBlock(
                title: "Title from Filename",
                code: """
                ---
                title: "{{ replace .File.ContentBaseName \"-\" \" \" | title }}"
                date: {{ .Date }}
                ---
                """
            )

            ExampleBlock(
                title: "With Categories",
                code: """
                ---
                title: "{{ .Title }}"
                date: {{ .Date }}
                categories: ["{{ .File.Dir }}"]
                tags: []
                ---
                """
            )
        }
    }
}

// MARK: - Help Section

private struct HelpSection<Content: View>: View {
    let title: String
    let systemImage: String
    let isExpanded: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack {
                    Image(systemName: systemImage)
                        .foregroundStyle(.orange)
                        .frame(width: 20)

                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .padding(.leading, 24)
            }
        }
    }
}

// MARK: - Help Item

private struct HelpItem: View {
    let variable: String
    let description: String
    var example: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(variable)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(3)

                Spacer()

                // Copy button
                Button {
                    let textToCopy = example != nil ? "{{ \(example!) }}" : "{{ \(variable) }}"
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(textToCopy, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy to clipboard")
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let example = example {
                Text("{{ \(example) }}")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(3)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Example Block

private struct ExampleBlock: View {
    let title: String
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy example")
            }

            Text(code)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
    }
}

#Preview {
    ArchetypeHelpPanel()
        .frame(width: 300, height: 600)
}
