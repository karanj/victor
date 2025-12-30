import SwiftUI

// MARK: - Preview Panel

struct PreviewPanel: View {
    let contentFile: ContentFile
    @Bindable var siteViewModel: SiteViewModel

    @State private var renderedHTML: String = ""
    @State private var debounceTask: Task<Void, Never>?

    /// Get the current content to display
    private var currentContent: String {
        siteViewModel.currentEditingContent.isEmpty ? contentFile.markdownContent : siteViewModel.currentEditingContent
    }

    /// Get the title from frontmatter for preview heading
    private var previewTitle: String? {
        contentFile.frontmatter?.title
    }

    var body: some View {
        PreviewWebView(html: renderedHTML)
            .navigationTitle(previewTitle ?? contentFile.fileName)
            .navigationSubtitle("Preview")
            .onAppear {
                // Always render current content when view appears (e.g., switching to Preview tab)
                updatePreview(content: currentContent)
            }
            .onChange(of: siteViewModel.currentEditingContent) { _, newContent in
                // Only do live updates if enabled (for split view performance)
                // In Preview-only mode, onAppear handles the update
                guard siteViewModel.isLivePreviewEnabled else { return }

                // Debounce preview updates (wait after typing stops)
                // Store old task reference before creating new one to avoid race condition
                let oldTask = debounceTask
                debounceTask = Task {
                    oldTask?.cancel()
                    try? await Task.sleep(for: .seconds(AppConstants.Preview.debounceInterval))
                    if !Task.isCancelled {
                        updatePreview(content: newContent)
                    }
                }
            }
            .onChange(of: contentFile.id) { _, _ in
                // File changed, update immediately regardless of live preview setting
                debounceTask?.cancel()
                updatePreview(content: currentContent)
            }
            .onDisappear {
                // Cancel pending debounce task when view disappears
                debounceTask?.cancel()
            }
    }

    private func updatePreview(content: String) {
        renderedHTML = MarkdownRenderer.shared.renderOrError(markdown: content, title: previewTitle)
    }
}

// MARK: - Preview Panel Placeholder

struct PreviewPanelPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "Preview",
            systemImage: "eye",
            description: Text("Select a markdown file to see preview")
        )
    }
}
