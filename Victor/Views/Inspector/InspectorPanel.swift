import SwiftUI

/// Right-side inspector panel for file metadata and statistics
struct InspectorPanel: View {
    let contentFile: ContentFile?
    let fileNode: FileNode?
    @Bindable var siteViewModel: SiteViewModel

    /// Tracks which sections are expanded
    @State private var isMetadataExpanded = true
    @State private var isStatisticsExpanded = true

    /// Cached document statistics (debounced computation)
    @State private var cachedStats = DocumentStats()
    @State private var statsUpdateTask: Task<Void, Never>?

    /// Debounce interval for statistics updates (1 second after typing stops)
    private let statsDebounceInterval: TimeInterval = 1.0

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
                            stats: cachedStats,
                            contentFile: contentFile
                        )
                    }
                } else {
                    // No file selected
                    EmptyStateView(
                        icon: "doc.text",
                        title: "No File Selected",
                        message: "Select a file to view its metadata"
                    )
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(12)
        }
        .frame(width: 260)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            // Compute initial stats when panel appears
            updateStatsImmediately()
        }
        .onChange(of: contentFile?.id) { _, _ in
            // File changed - update stats immediately
            updateStatsImmediately()
        }
        .onChange(of: siteViewModel.currentEditingContent) { _, _ in
            // Content changed - debounce the stats update
            // Only update if statistics section is expanded (visible)
            if isStatisticsExpanded {
                scheduleStatsUpdate()
            }
        }
        .onChange(of: isStatisticsExpanded) { _, isExpanded in
            // If user expands statistics section, update stats immediately
            if isExpanded {
                updateStatsImmediately()
            }
        }
    }

    /// Schedule a debounced statistics update
    private func scheduleStatsUpdate() {
        statsUpdateTask?.cancel()
        statsUpdateTask = Task {
            do {
                try await Task.sleep(for: .seconds(statsDebounceInterval))
                guard !Task.isCancelled else { return }
                updateStatsImmediately()
            } catch {
                // Task was cancelled, ignore
            }
        }
    }

    /// Update statistics immediately (no debounce)
    private func updateStatsImmediately() {
        guard let contentFile = contentFile else { return }
        let content = effectiveContent(for: contentFile)
        cachedStats = DocumentStats.compute(from: content)
    }

    /// Get the effective content for statistics - use editing content if available, otherwise file content
    private func effectiveContent(for contentFile: ContentFile) -> String {
        // If there's current editing content for this file, use it
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

    @State private var isHovered = false

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
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(isHovered ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : Color.clear)
                .cornerRadius(4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }
            .help("Click to \(isExpanded ? "collapse" : "expand")")

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
