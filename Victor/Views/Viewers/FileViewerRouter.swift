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
                // Check if this is an asset directory (static/ or assets/)
                if node.hugoRole == .staticFiles || node.hugoRole == .assets {
                    assetBrowserContent
                } else if node.hugoRole == .layouts || node.hugoRole == .themes {
                    // Show template browser for layouts/ and themes/ directories
                    templateBrowserContent
                } else {
                    // Show folder contents for other directories
                    FolderContentsView(node: node, siteViewModel: siteViewModel)
                }
            } else if node.isConfigFile {
                // Hugo config files get the GUI editor
                configEditorContent
            } else if node.isTranslationFile {
                // Translation files in i18n/ directory get the translation editor
                translationEditorContent
            } else if node.isDataFile {
                // Data files in data/ directory get the data editor
                dataFileEditorContent
            } else if node.isTemplateFile {
                // Template files in layouts/ or themes/ get the template editor
                templateEditorContent
            } else if node.isArchetypeFile {
                // Archetype files in archetypes/ get the archetype editor
                archetypeEditorContent
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
            ConfigEditorView(config: config, onSave: {
                await siteViewModel.saveHugoConfig()
            }, onSaveRaw: {
                await siteViewModel.saveHugoConfigRaw()
            })
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

    /// Asset browser content for static/ and assets/ directories
    @ViewBuilder
    private var assetBrowserContent: some View {
        AssetBrowserView(
            folderURL: node.url,
            isAssetsDir: node.hugoRole == .assets,
            onInsert: nil  // Drag-drop is supported; clipboard copy is in detail panel
        )
    }

    /// Template browser content for layouts/ and themes/ directories
    @ViewBuilder
    private var templateBrowserContent: some View {
        if let siteURL = siteViewModel.site?.rootURL {
            TemplateBrowserView(
                siteURL: siteURL,
                siteViewModel: siteViewModel
            )
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No site loaded")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Data file editor content - shows loading, editor, or fallback
    @ViewBuilder
    private var dataFileEditorContent: some View {
        if siteViewModel.isLoadingDataFile {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading data file...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let dataFile = siteViewModel.currentDataFile, dataFile.url == node.url {
            DataFileEditorView(dataFile: dataFile, onSave: {
                await siteViewModel.saveDataFile()
            })
        } else if let error = siteViewModel.dataFileLoadError, siteViewModel.failedDataFileURL == node.url {
            // Show error state - don't retry
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("Failed to load data file")
                    .font(.headline)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Retry") {
                    Task {
                        await siteViewModel.loadDataFile(from: node.url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)

                Button("Open in Default App") {
                    NSWorkspace.shared.open(node.url)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Data file not loaded yet - trigger load
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading data file...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                await siteViewModel.loadDataFile(from: node.url)
            }
        }
    }

    /// Translation file editor content - shows loading, editor, or fallback
    @ViewBuilder
    private var translationEditorContent: some View {
        if siteViewModel.isLoadingDataFile {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading translation file...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let dataFile = siteViewModel.currentDataFile, dataFile.url == node.url {
            TranslationEditorView(dataFile: dataFile, onSave: {
                await siteViewModel.saveDataFile()
            })
        } else if let error = siteViewModel.dataFileLoadError, siteViewModel.failedDataFileURL == node.url {
            // Show error state - don't retry
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("Failed to load translation file")
                    .font(.headline)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Retry") {
                    Task {
                        await siteViewModel.loadDataFile(from: node.url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)

                Button("Open in Default App") {
                    NSWorkspace.shared.open(node.url)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Translation file not loaded yet - trigger load
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading translation file...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                await siteViewModel.loadDataFile(from: node.url)
            }
        }
    }

    /// Template editor content - shows loading, editor, or fallback
    @ViewBuilder
    private var templateEditorContent: some View {
        if siteViewModel.isLoadingTemplate {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading template...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let template = siteViewModel.currentTemplate, template.url == node.url {
            TemplateEditorView(template: template, onSave: {
                await siteViewModel.saveTemplate()
            })
        } else if let error = siteViewModel.templateLoadError, siteViewModel.failedTemplateURL == node.url {
            // Show error state - don't retry
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("Failed to load template")
                    .font(.headline)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Retry") {
                    Task {
                        await siteViewModel.loadTemplate(from: node.url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)

                Button("Open in Default App") {
                    NSWorkspace.shared.open(node.url)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Template not loaded yet - trigger load
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading template...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                await siteViewModel.loadTemplate(from: node.url)
            }
        }
    }

    /// Archetype editor content - shows loading, editor, or fallback
    @ViewBuilder
    private var archetypeEditorContent: some View {
        if siteViewModel.isLoadingArchetype {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading archetype...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let archetype = siteViewModel.currentArchetype, archetype.url == node.url {
            ArchetypeEditorView(archetype: archetype, onSave: {
                await siteViewModel.saveArchetype()
            })
        } else if let error = siteViewModel.archetypeLoadError, siteViewModel.failedArchetypeURL == node.url {
            // Show error state - don't retry
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("Failed to load archetype")
                    .font(.headline)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Retry") {
                    Task {
                        await siteViewModel.loadArchetype(from: node.url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)

                Button("Open in Default App") {
                    NSWorkspace.shared.open(node.url)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Archetype not loaded yet - trigger load
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading archetype...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                await siteViewModel.loadArchetype(from: node.url)
            }
        }
    }
}
