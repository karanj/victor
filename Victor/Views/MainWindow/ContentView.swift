import SwiftUI

struct ContentView: View {
    @Bindable var siteViewModel: SiteViewModel
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar - File navigation
            SidebarView(siteViewModel: siteViewModel)
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
        } content: {
            // Editor Panel - Markdown content (Phase 2: Editable)
            if let selectedNode = siteViewModel.selectedNode,
               let contentFile = selectedNode.contentFile {
                EditorPanelView(
                    contentFile: contentFile,
                    fileNode: selectedNode,
                    siteViewModel: siteViewModel
                )
            } else {
                ContentUnavailableView(
                    "No File Selected",
                    systemImage: "doc.text",
                    description: Text("Select a markdown file from the sidebar")
                )
            }
        } detail: {
            // Preview Panel - Live markdown preview
            if let selectedNode = siteViewModel.selectedNode,
               let contentFile = selectedNode.contentFile {
                PreviewPanel(contentFile: contentFile, siteViewModel: siteViewModel)
            } else {
                PreviewPanelPlaceholder()
            }
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

    private func toggleSidebar() {
        columnVisibility = columnVisibility == .all ? .detailOnly : .all
    }
}

#Preview {
    ContentView(siteViewModel: SiteViewModel())
}
