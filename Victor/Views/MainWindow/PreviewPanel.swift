import SwiftUI

// MARK: - Preview Panel

struct PreviewPanel: View {
    let contentFile: ContentFile
    @Bindable var siteViewModel: SiteViewModel

    @State private var renderedHTML: String = ""
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        PreviewWebView(html: renderedHTML)
            .navigationTitle("Preview")
            .navigationSubtitle(contentFile.fileName)
            .onAppear {
                // Initial render
                updatePreview(content: siteViewModel.currentEditingContent.isEmpty ? contentFile.markdownContent : siteViewModel.currentEditingContent)
            }
            .onChange(of: siteViewModel.currentEditingContent) { _, newContent in
                // Debounce preview updates (wait after typing stops)
                debounceTask?.cancel()
                debounceTask = Task {
                    try? await Task.sleep(for: .seconds(AppConstants.Preview.debounceInterval))
                    if !Task.isCancelled {
                        updatePreview(content: newContent)
                    }
                }
            }
            .onChange(of: contentFile.id) { _, _ in
                // File changed, update immediately
                debounceTask?.cancel()
                updatePreview(content: siteViewModel.currentEditingContent.isEmpty ? contentFile.markdownContent : siteViewModel.currentEditingContent)
            }
            .onDisappear {
                // Cancel pending debounce task when view disappears
                debounceTask?.cancel()
            }
    }

    private func updatePreview(content: String) {
        renderedHTML = MarkdownRenderer.shared.renderOrError(markdown: content)
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
