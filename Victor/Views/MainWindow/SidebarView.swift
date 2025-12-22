import SwiftUI

struct SidebarView: View {
    @Bindable var siteViewModel: SiteViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            if siteViewModel.site == nil {
                OpenFolderPrompt(siteViewModel: siteViewModel)
            } else {
                SiteHeader(siteViewModel: siteViewModel)
            }

            Divider()

            // Search bar
            if siteViewModel.site != nil {
                SearchBar(searchText: $siteViewModel.searchQuery, siteViewModel: siteViewModel)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                Divider()
            }

            // File list
            if siteViewModel.isLoading {
                LoadingView()
            } else if siteViewModel.site != nil {
                FileListView(siteViewModel: siteViewModel)
            } else {
                ContentUnavailableView(
                    "No Site Opened",
                    systemImage: "folder",
                    description: Text("Click above to open a Hugo site folder")
                )
            }
        }
    }
}

// MARK: - Open Folder Prompt

struct OpenFolderPrompt: View {
    let siteViewModel: SiteViewModel

    var body: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    await siteViewModel.openSiteFolder()
                }
            } label: {
                Label("Open Hugo Site", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }
}

// MARK: - Site Header

struct SiteHeader: View {
    let siteViewModel: SiteViewModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(siteViewModel.site?.displayName ?? "")
                    .font(.headline)
                    .lineLimit(1)

                Text("\(siteViewModel.fileNodes.count) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button("Reload Site") {
                    Task {
                        await siteViewModel.reloadSite()
                    }
                }

                Button("Open New Site...") {
                    Task {
                        await siteViewModel.openSiteFolder()
                    }
                }

                Divider()

                Button("Close Site") {
                    siteViewModel.closeSite()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Search Bar

struct SearchBar: View {
    @Binding var searchText: String
    @Bindable var siteViewModel: SiteViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search files", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
        .onChange(of: siteViewModel.shouldFocusSearch) { _, newValue in
            if newValue {
                isSearchFocused = true
                siteViewModel.shouldFocusSearch = false
            }
        }
    }
}

// MARK: - File List
/// TODO: double-click on folder should cause it to expand or collapse the folder
/// TODO: can this be notified of file system changes (e.g. if a new file is added on the file system, it should automatically show up in the folder list - not sure if this is possible.
/// TODO: add new post - maybe as a right-click, it should prompt to create a new file with a title slug
struct FileListView: View {
    @Bindable var siteViewModel: SiteViewModel

    var body: some View {
        List(siteViewModel.filteredNodes, selection: $siteViewModel.selectedFileID) { node in
            if node.isDirectory {
                // Use DisclosureGroup for folders with children
                DisclosureGroup(isExpanded: Binding(
                    get: { node.isExpanded },
                    set: { node.isExpanded = $0 }
                )) {
                    ForEach(node.children) { child in
                        FileTreeRow(node: child, siteViewModel: siteViewModel)
                    }
                } label: {
                    FileRowView(node: node)
                        .contextMenu {
                            Button {
                                Task {
                                    await siteViewModel.createMarkdownFile(in: node)
                                }
                            } label: {
                                Label("New Markdown File", systemImage: "doc.badge.plus")
                            }
                        }
                        .onTapGesture(count: 2) {
                            // Double-click to expand/collapse folder
                            node.isExpanded.toggle()
                        }
                        .onTapGesture {
                            // If page bundle, open the index file
                            if node.isPageBundle, let indexFile = node.indexFile {
                                siteViewModel.selectNode(indexFile)
                            }
                        }
                }
            } else {
                // Regular file row
                FileRowView(node: node)
                    .tag(node.id)
                    .onTapGesture {
                        siteViewModel.selectNode(node)
                    }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: siteViewModel.selectedFileID) { _, newValue in
            if let id = newValue {
                if let node = findNode(id: id, in: siteViewModel.fileNodes) {
                    siteViewModel.selectNode(node)
                }
            }
        }
    }

    // Recursively find a node by ID
    private func findNode(id: UUID, in nodes: [FileNode]) -> FileNode? {
        for node in nodes {
            if node.id == id {
                return node
            }
            if let found = findNode(id: id, in: node.children) {
                return found
            }
        }
        return nil
    }

}

// MARK: - Recursive File Tree Row

struct FileTreeRow: View {
    let node: FileNode
    let siteViewModel: SiteViewModel

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: Binding(
                get: { node.isExpanded },
                set: { node.isExpanded = $0 }
            )) {
                ForEach(node.children) { child in
                    FileTreeRow(node: child, siteViewModel: siteViewModel)
                }
            } label: {
                FileRowView(node: node)
                    .contextMenu {
                        Button {
                            Task {
                                await siteViewModel.createMarkdownFile(in: node)
                            }
                        } label: {
                            Label("New Markdown File", systemImage: "doc.badge.plus")
                        }
                    }
                    .onTapGesture(count: 2) {
                        // Double-click to expand/collapse folder
                        node.isExpanded.toggle()
                    }
                    .onTapGesture {
                        // If page bundle, open the index file
                        if node.isPageBundle, let indexFile = node.indexFile {
                            siteViewModel.selectNode(indexFile)
                        }
                    }
            }
        } else {
            FileRowView(node: node)
                .tag(node.id)
                .onTapGesture {
                    siteViewModel.selectNode(node)
                }
        }
    }

}

// MARK: - File Row

struct FileRowView: View {
    let node: FileNode

    var body: some View {
        HStack(spacing: 8) {
            // Icon: different for page bundles, folders, and files
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .imageScale(.medium)
                .accessibilityLabel(accessibilityIconLabel)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(node.name)
                        .lineLimit(1)

                    // Page bundle badge
                    if node.isPageBundle {
                        Text("bundle")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.purple)
                            .cornerRadius(3)
                    }
                }

                if let contentFile = node.contentFile, contentFile.isDraft {
                    Text("Draft")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.orange.opacity(0.2))
                        .cornerRadius(3)
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
    }

    private var iconName: String {
        if node.isPageBundle {
            return "folder.fill.badge.gearshape"
        } else if node.isDirectory {
            return "folder"
        } else {
            return "doc.text"
        }
    }

    private var iconColor: Color {
        if node.isPageBundle {
            return .purple
        } else if node.isDirectory {
            return .blue
        } else {
            return .primary
        }
    }

    private var accessibilityIconLabel: String {
        if node.isPageBundle {
            return "Page bundle"
        } else if node.isDirectory {
            return "Folder"
        } else {
            return "Markdown file"
        }
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading files...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SidebarView(siteViewModel: SiteViewModel())
        .frame(width: 250, height: 600)
}
