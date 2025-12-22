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
            // Editor Panel - Markdown content (Phase 1: Simple text view)
            if let selectedNode = siteViewModel.selectedNode,
               let contentFile = selectedNode.contentFile {
                EditorPanelView(contentFile: contentFile)
            } else {
                ContentUnavailableView(
                    "No File Selected",
                    systemImage: "doc.text",
                    description: Text("Select a markdown file from the sidebar")
                )
            }
        } detail: {
            // Preview Panel - Will be implemented in Phase 2
            PreviewPanelPlaceholder()
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
        .alert("Error", isPresented: .constant(siteViewModel.errorMessage != nil)) {
            Button("OK") {
                siteViewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = siteViewModel.errorMessage {
                Text(errorMessage)
            }
        }
    }

    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }
}

// MARK: - Editor Panel (Phase 1)

struct EditorPanelView: View {
    let contentFile: ContentFile

    var body: some View {
        ScrollView {
            Text(contentFile.markdownContent)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(contentFile.fileName)
        .navigationSubtitle(contentFile.relativePath)
    }
}

// MARK: - Preview Panel Placeholder

struct PreviewPanelPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "Preview",
            systemImage: "eye",
            description: Text("Markdown preview will be implemented in Phase 2")
        )
    }
}

#Preview {
    ContentView(siteViewModel: SiteViewModel())
}
