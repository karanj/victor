import SwiftUI

/// Right-side inspector panel for file metadata and statistics
struct InspectorPanel: View {
    let contentFile: ContentFile?
    let fileNode: FileNode?
    @Bindable var siteViewModel: SiteViewModel

    /// Tracks which sections are expanded
    @State private var isMetadataExpanded = true
    @State private var isStatisticsExpanded = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let contentFile = contentFile, let _ = fileNode {
                    // Metadata Section (only if frontmatter exists)
                    if let frontmatter = contentFile.frontmatter {
                        InspectorSection(
                            title: "Metadata",
                            systemImage: "doc.text",
                            isExpanded: $isMetadataExpanded
                        ) {
                            MetadataSection(frontmatter: frontmatter)
                        }

                        Divider()
                            .padding(.vertical, 8)
                    }

                    // Statistics Section
                    InspectorSection(
                        title: "Statistics",
                        systemImage: "chart.bar",
                        isExpanded: $isStatisticsExpanded
                    ) {
                        StatisticsSection(
                            content: effectiveContent(for: contentFile),
                            contentFile: contentFile
                        )
                    }
                } else {
                    // No file selected
                    ContentUnavailableView(
                        "No File Selected",
                        systemImage: "doc.text",
                        description: Text("Select a file to view its metadata")
                    )
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(12)
        }
        .frame(width: 260)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Get the effective content for statistics - use editing content if available, otherwise file content
    private func effectiveContent(for contentFile: ContentFile) -> String {
        // If there's current editing content for this file, use it (for live updates)
        // Otherwise fall back to the file's markdown content
        let editingContent = siteViewModel.currentEditingContent
        if !editingContent.isEmpty {
            return editingContent
        }
        return contentFile.markdownContent
    }
}

// MARK: - Inspector Section

/// Collapsible section container for inspector panels
struct InspectorSection<Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: systemImage)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Section content
            if isExpanded {
                content
                    .padding(.leading, 4)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    InspectorPanel(
        contentFile: nil,
        fileNode: nil,
        siteViewModel: SiteViewModel()
    )
}
