import SwiftUI

/// Routes to the appropriate viewer/editor based on file type
struct FileViewerRouter: View {
    let node: FileNode
    @Bindable var siteViewModel: SiteViewModel

    // ViewModel for text file editing (created per-file)
    @State private var textEditorViewModel = TextEditorViewModel()

    var body: some View {
        Group {
            if node.isDirectory {
                // Directories shouldn't reach here, but handle gracefully
                directoryPlaceholder
            } else if node.isConfigFile {
                // Hugo config files get the GUI editor
                configEditorContent
            } else {
                switch node.fileType {
                case .markdown:
                    // Use existing markdown editor for markdown files in content/
                    if let contentFile = node.contentFile {
                        EditorPanelView(
                            contentFile: contentFile,
                            fileNode: node,
                            siteViewModel: siteViewModel
                        )
                    } else {
                        // Markdown file not in content/ - show as text viewer
                        TextViewerPanel(url: node.url, fileType: node.fileType)
                    }

                case .image:
                    ImageViewerPanel(url: node.url)

                case .yaml, .toml, .json, .html, .css, .javascript, .typescript,
                     .scss, .sass, .less, .xml, .go, .plainText:
                    // Text-based files - use editor if loaded, viewer otherwise
                    if let textFile = node.textFile {
                        TextEditorPanel(
                            textFile: textFile,
                            viewModel: textEditorViewModel
                        )
                    } else {
                        // Fallback to read-only viewer while loading
                        TextViewerPanel(url: node.url, fileType: node.fileType)
                    }

                case .video, .audio, .pdf, .binary:
                    UnsupportedFilePanel(url: node.url, fileType: node.fileType)
                }
            }
        }
        .onChange(of: node.id) { _, _ in
            // Reset view model when switching files
            if let textFile = node.textFile {
                textEditorViewModel.loadFile(textFile)
            }
        }
    }

    /// Config editor content - shows loading, config editor, or fallback
    @ViewBuilder
    private var configEditorContent: some View {
        if siteViewModel.isLoadingConfig {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading configuration...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let config = siteViewModel.hugoConfig, config.sourceURL == node.url {
            ConfigEditorView(config: config) {
                await siteViewModel.saveHugoConfig()
            }
        } else {
            // Config not loaded yet - trigger load
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading configuration...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                await siteViewModel.loadHugoConfig(from: node.url)
            }
        }
    }

    private var directoryPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Select a file to view")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
