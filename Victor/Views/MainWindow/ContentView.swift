import SwiftUI

struct ContentView: View {
    @Bindable var siteViewModel: SiteViewModel
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        ZStack {
            mainContent

            // Focus Mode overlay
            if siteViewModel.isFocusModeActive,
               let selectedNode = siteViewModel.selectedNode,
               let contentFile = selectedNode.contentFile {
                FocusModeView(
                    text: $siteViewModel.currentEditingContent,
                    siteViewModel: siteViewModel,
                    fileName: selectedNode.name,
                    contentFile: contentFile
                )
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: siteViewModel.isFocusModeActive)
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar - File navigation
            SidebarView(siteViewModel: siteViewModel)
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
        } detail: {
            // Main content area with optional inspector
            HSplitView {
                // Main content area with tab-based layout
                VStack(spacing: 0) {
                    // Tab bar for switching between Editor/Preview/Split
                    TabBarView(viewModel: siteViewModel)

                    // Content based on selected layout mode
                    if let selectedNode = siteViewModel.selectedNode,
                       let contentFile = selectedNode.contentFile {
                        layoutContent(for: selectedNode, contentFile: contentFile)
                            .animation(.easeInOut(duration: 0.2), value: siteViewModel.layoutMode)
                    } else {
                        noFileSelectedView
                    }
                }
                .frame(minWidth: 400)

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
            .animation(.easeInOut(duration: 0.2), value: siteViewModel.isInspectorVisible)
        }
        .navigationTitle(siteViewModel.site?.displayName ?? "Victor")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
            }

            if siteViewModel.isLoading {
                ToolbarItem {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        siteViewModel.toggleInspector()
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
        // Quick Open overlay - disabled temporarily (needs keyboard navigation fix)
        // .overlay {
        //     if siteViewModel.isQuickOpenVisible {
        //         QuickOpenView(
        //             siteViewModel: siteViewModel,
        //             isPresented: $siteViewModel.isQuickOpenVisible
        //         )
        //         .transition(.opacity.combined(with: .move(edge: .top)))
        //     }
        // }
        // .animation(.easeOut(duration: 0.15), value: siteViewModel.isQuickOpenVisible)
    }

    // MARK: - Layout Content

    /// Returns the appropriate view based on the current layout mode
    @ViewBuilder
    private func layoutContent(for node: FileNode, contentFile: ContentFile) -> some View {
        switch siteViewModel.layoutMode {
        case .editor:
            // Full-width editor only
            EditorPanelView(
                contentFile: contentFile,
                fileNode: node,
                siteViewModel: siteViewModel
            )

        case .preview:
            // Full-width preview only
            PreviewPanel(contentFile: contentFile, siteViewModel: siteViewModel)

        case .split:
            // Side-by-side editor and preview
            HSplitView {
                EditorPanelView(
                    contentFile: contentFile,
                    fileNode: node,
                    siteViewModel: siteViewModel
                )
                .frame(minWidth: 300)

                PreviewPanel(contentFile: contentFile, siteViewModel: siteViewModel)
                    .frame(minWidth: 300)
            }
        }
    }

    // MARK: - Empty States

    /// View shown when no file is selected
    private var noFileSelectedView: some View {
        ContentUnavailableView(
            "No File Selected",
            systemImage: "doc.text",
            description: Text("Select a markdown file from the sidebar")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func toggleSidebar() {
        columnVisibility = columnVisibility == .all ? .detailOnly : .all
    }
}

#Preview {
    ContentView(siteViewModel: SiteViewModel())
}
