import SwiftUI

struct ContentView: View {
    @Bindable var siteViewModel: SiteViewModel
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    // Accessibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            mainContent

            // Focus Mode overlay
            if siteViewModel.isFocusModeActive,
               let selectedNode = siteViewModel.selectedNode,
               selectedNode.contentFile != nil {
                FocusModeView(
                    text: $siteViewModel.currentEditingContent,
                    siteViewModel: siteViewModel,
                    fileName: selectedNode.name
                )
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: AppConstants.Animation.slow), value: siteViewModel.isFocusModeActive)
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar - File navigation
            SidebarView(siteViewModel: siteViewModel)
                .navigationSplitViewColumnWidth(
                    min: AppConstants.Sidebar.minWidth,
                    ideal: AppConstants.Sidebar.idealWidth,
                    max: AppConstants.Sidebar.maxWidth
                )
        } detail: {
            // Main content area with optional inspector
            HSplitView {
                // Main content area with tab-based layout
                VStack(spacing: 0) {
                    // Tab bar only shown for content files (markdown with frontmatter)
                    if siteViewModel.selectedNode?.contentFile != nil {
                        TabBarView(viewModel: siteViewModel)
                    }

                    // Content based on selected layout mode
                    if let selectedNode = siteViewModel.selectedNode {
                        layoutContent(for: selectedNode)
                            .id(selectedNode.id)  // Force view recreation on file switch
                            .transition(.opacity.animation(.easeInOut(duration: reduceMotion ? 0 : AppConstants.Animation.fast)))
                            .animation(reduceMotion ? nil : .easeInOut(duration: AppConstants.Animation.standard), value: siteViewModel.layoutMode)
                    } else {
                        noFileSelectedView
                            .transition(.opacity.animation(.easeInOut(duration: reduceMotion ? 0 : AppConstants.Animation.fast)))
                    }
                }
                .frame(minWidth: AppConstants.Content.minWidth)

                // Inspector panel (right side)
                if siteViewModel.isInspectorVisible {
                    InspectorPanel(
                        contentFile: siteViewModel.selectedNode?.contentFile,
                        fileNode: siteViewModel.selectedNode,
                        siteViewModel: siteViewModel
                    )
                    .transition(.move(edge: .trailing))
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: AppConstants.Animation.standard), value: siteViewModel.isInspectorVisible)
        }
        .navigationTitle(siteViewModel.site?.displayName ?? "Victor")
        .toolbar {
            // Note: NavigationSplitView automatically provides a sidebar toggle button
            // so we don't need to add our own

            if siteViewModel.isLoading || siteViewModel.isLoadingFile {
                ToolbarItem {
                    ProgressView()
                        .controlSize(.small)
                        .help(siteViewModel.isLoadingFile ? "Loading file..." : "Loading site...")
                }
            }

            // Only show inspector toggle for markdown content files
            // (Assets have their own built-in detail panel)
            if siteViewModel.selectedNode?.contentFile != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if reduceMotion {
                            siteViewModel.toggleInspector()
                        } else {
                            withAnimation(.easeInOut(duration: AppConstants.Animation.standard)) {
                                siteViewModel.toggleInspector()
                            }
                        }
                    } label: {
                        Label(
                            siteViewModel.isInspectorVisible ? "Hide Inspector" : "Show Inspector",
                            systemImage: "sidebar.right"
                        )
                    }
                    .help("Toggle Inspector (⌥⌘I)")
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { siteViewModel.errorMessage != nil },
            set: { if !$0 { siteViewModel.errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            if let errorMessage = siteViewModel.errorMessage {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Layout Content

    /// Determines the effective layout mode based on file type
    /// Non-markdown files always use editor-only mode (no preview)
    private var effectiveLayoutMode: EditorLayoutMode {
        guard let node = siteViewModel.selectedNode else {
            return siteViewModel.layoutMode
        }
        // Only markdown files with content get preview
        if node.fileType != .markdown || node.contentFile == nil {
            return .editor
        }
        return siteViewModel.layoutMode
    }

    /// Returns the appropriate view based on the current layout mode
    @ViewBuilder
    private func layoutContent(for node: FileNode) -> some View {
        switch effectiveLayoutMode {
        case .editor:
            // Full-width viewer/editor only
            FileViewerRouter(node: node, siteViewModel: siteViewModel)

        case .preview:
            // Full-width preview only (markdown only)
            if let contentFile = node.contentFile {
                PreviewPanel(contentFile: contentFile, siteViewModel: siteViewModel)
            } else {
                FileViewerRouter(node: node, siteViewModel: siteViewModel)
            }

        case .split:
            // Side-by-side editor and preview (markdown only)
            if let contentFile = node.contentFile {
                HSplitView {
                    FileViewerRouter(node: node, siteViewModel: siteViewModel)
                        .frame(minWidth: AppConstants.Content.panelMinWidth)

                    PreviewPanel(contentFile: contentFile, siteViewModel: siteViewModel)
                        .frame(minWidth: AppConstants.Content.panelMinWidth)
                }
            } else {
                FileViewerRouter(node: node, siteViewModel: siteViewModel)
            }
        }
    }

    // MARK: - Empty States

    /// View shown when no file is selected
    private var noFileSelectedView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: "doc.text")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)

            // Title and description
            VStack(spacing: 8) {
                Text("Select a File")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Choose a markdown file from the sidebar to start editing")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Helpful hints
            VStack(alignment: .leading, spacing: 12) {
                KeyboardHintRow(keys: "⌘F", description: "Search files")
                KeyboardHintRow(keys: "⌘1", description: "Editor only")
                KeyboardHintRow(keys: "⌘2", description: "Preview only")
                KeyboardHintRow(keys: "⌘3", description: "Split view")
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

// MARK: - Keyboard Hint Row

struct KeyboardHintRow: View {
    let keys: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
                .frame(minWidth: 50)

            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView(siteViewModel: SiteViewModel())
}
