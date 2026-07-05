import SwiftUI

/// Routes to the appropriate viewer/editor based on file type
struct FileViewerRouter: View {
    let node: FileNode
    @Bindable var siteViewModel: SiteViewModel

    // ViewModel for text file editing (created per-file). victor-zw4: this `@State`
    // default-value expression runs before `siteViewModel` is available (struct
    // property defaults can't reference `self`), so there's no seam here to thread
    // `siteViewModel.fileSystemService` through - kept on `TextEditorViewModel`'s
    // `.shared` default parameter instead.
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
                            nodeID: node.id,
                            viewModel: textEditorViewModel,
                            siteViewModel: siteViewModel
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
        .onAppear {
            textEditorViewModel.siteViewModel = siteViewModel
        }
        .onChange(of: node.id) { _, _ in
            // Reset view model when switching files
            textEditorViewModel.siteViewModel = siteViewModel
            if let textFile = node.textFile {
                textEditorViewModel.loadFile(textFile, nodeID: node.id)
            }
        }
    }

    /// Config editor content - shows loading, config editor, or fallback
    @ViewBuilder
    private var configEditorContent: some View {
        if siteViewModel.isLoadingConfig {
            LoadingStateView(message: "Loading configuration...")
        } else if let config = siteViewModel.hugoConfig, config.sourceURL == node.url {
            ConfigEditorView(config: config, onSave: {
                await siteViewModel.saveHugoConfig()
            }, onSaveRaw: {
                await siteViewModel.saveHugoConfigRaw()
            })
        } else {
            // Config not loaded yet - trigger load
            LoadingStateView(message: "Loading configuration...")
                .task {
                    await siteViewModel.loadHugoConfig(from: node.url)
                }
        }
    }

    private var directoryPlaceholder: some View {
        EmptyStateView(
            icon: "folder",
            title: "Directory Selected",
            message: "Select a file to view its contents"
        )
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
            EmptyStateView(
                icon: "doc.text.magnifyingglass",
                title: "No Site Loaded",
                message: "Open a Hugo site to browse templates"
            )
        }
    }

    /// Data file editor content - shows loading, editor, or fallback
    @ViewBuilder
    private var dataFileEditorContent: some View {
        if siteViewModel.isLoadingDataFile {
            LoadingStateView(message: "Loading data file...")
        } else if let dataFile = siteViewModel.currentDataFile, dataFile.url == node.url {
            DataFileEditorView(dataFile: dataFile, onSave: {
                await siteViewModel.saveDataFile()
            })
        } else if let error = siteViewModel.dataFileLoadError, siteViewModel.failedDataFileURL == node.url {
            ErrorStateView(
                title: "Failed to load data file",
                message: error,
                retryAction: { Task { await siteViewModel.loadDataFile(from: node.url) } },
                openURL: node.url
            )
        } else {
            // Data file not loaded yet - trigger load
            LoadingStateView(message: "Loading data file...")
                .task {
                    await siteViewModel.loadDataFile(from: node.url)
                }
        }
    }

    /// Translation file editor content - shows loading, editor, or fallback
    @ViewBuilder
    private var translationEditorContent: some View {
        if siteViewModel.isLoadingDataFile {
            LoadingStateView(message: "Loading translation file...")
        } else if let dataFile = siteViewModel.currentDataFile, dataFile.url == node.url {
            TranslationEditorView(dataFile: dataFile, onSave: {
                await siteViewModel.saveDataFile()
            })
        } else if let error = siteViewModel.dataFileLoadError, siteViewModel.failedDataFileURL == node.url {
            ErrorStateView(
                title: "Failed to load translation file",
                message: error,
                retryAction: { Task { await siteViewModel.loadDataFile(from: node.url) } },
                openURL: node.url
            )
        } else {
            // Translation file not loaded yet - trigger load
            LoadingStateView(message: "Loading translation file...")
                .task {
                    await siteViewModel.loadDataFile(from: node.url)
                }
        }
    }

    /// Template editor content - shows loading, editor, or fallback
    @ViewBuilder
    private var templateEditorContent: some View {
        if siteViewModel.isLoadingTemplate {
            LoadingStateView(message: "Loading template...")
        } else if let template = siteViewModel.currentTemplate, template.url == node.url {
            TemplateEditorView(template: template, onSave: {
                await siteViewModel.saveTemplate()
            })
        } else if let error = siteViewModel.templateLoadError, siteViewModel.failedTemplateURL == node.url {
            ErrorStateView(
                title: "Failed to load template",
                message: error,
                retryAction: { Task { await siteViewModel.loadTemplate(from: node.url) } },
                openURL: node.url
            )
        } else {
            // Template not loaded yet - trigger load
            LoadingStateView(message: "Loading template...")
                .task {
                    await siteViewModel.loadTemplate(from: node.url)
                }
        }
    }

    /// Archetype editor content - shows loading, editor, or fallback
    @ViewBuilder
    private var archetypeEditorContent: some View {
        if siteViewModel.isLoadingArchetype {
            LoadingStateView(message: "Loading archetype...")
        } else if let archetype = siteViewModel.currentArchetype, archetype.url == node.url {
            ArchetypeEditorView(archetype: archetype, onSave: {
                await siteViewModel.saveArchetype()
            })
        } else if let error = siteViewModel.archetypeLoadError, siteViewModel.failedArchetypeURL == node.url {
            ErrorStateView(
                title: "Failed to load archetype",
                message: error,
                retryAction: { Task { await siteViewModel.loadArchetype(from: node.url) } },
                openURL: node.url
            )
        } else {
            // Archetype not loaded yet - trigger load
            LoadingStateView(message: "Loading archetype...")
                .task {
                    await siteViewModel.loadArchetype(from: node.url)
                }
        }
    }
}
