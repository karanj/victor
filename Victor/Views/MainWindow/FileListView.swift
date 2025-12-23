import SwiftUI

// MARK: - File List View

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
