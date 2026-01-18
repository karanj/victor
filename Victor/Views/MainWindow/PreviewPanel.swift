import SwiftUI

// MARK: - Preview Panel

struct PreviewPanel: View {
    let contentFile: ContentFile
    @Bindable var siteViewModel: SiteViewModel

    @State private var renderedHTML: String = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var themeCSS: String?
    @State private var lastLoadedTheme: String?

    /// Get the current content to display
    private var currentContent: String {
        siteViewModel.currentEditingContent.isEmpty ? contentFile.markdownContent : siteViewModel.currentEditingContent
    }

    /// Get the title from frontmatter for preview heading
    private var previewTitle: String? {
        contentFile.frontmatter?.title
    }

    /// Current theme name from Hugo config
    private var currentTheme: String? {
        siteViewModel.hugoConfig?.theme
    }

    var body: some View {
        PreviewWebView(html: renderedHTML)
            .navigationTitle(previewTitle ?? contentFile.fileName)
            .onAppear {
                // Load theme CSS and render content when view appears
                Task {
                    await loadThemeCSSIfNeeded()
                    updatePreview(content: currentContent)
                }
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
            .onChange(of: currentTheme) { _, _ in
                // Theme changed in config, reload theme CSS
                Task {
                    await loadThemeCSSIfNeeded()
                    updatePreview(content: currentContent)
                }
            }
            .onDisappear {
                // Cancel pending debounce task when view disappears
                debounceTask?.cancel()
            }
    }

    /// Load theme CSS from Hugo theme directory if theme has changed
    private func loadThemeCSSIfNeeded() async {
        let theme = currentTheme

        // Skip if theme hasn't changed
        guard theme != lastLoadedTheme else { return }

        lastLoadedTheme = theme
        themeCSS = await ThemeCSSService.shared.loadThemeCSS(
            themeName: theme,
            siteRootURL: siteViewModel.site?.rootURL
        )
    }

    private func updatePreview(content: String) {
        renderedHTML = MarkdownRenderer.shared.renderOrError(
            markdown: content,
            title: previewTitle,
            themeCSS: themeCSS
        )
    }
}

// MARK: - Preview Panel Placeholder

struct PreviewPanelPlaceholder: View {
    var body: some View {
        EmptyStateView(
            icon: "eye",
            title: "Preview",
            message: "Select a markdown file to see preview"
        )
    }
}
