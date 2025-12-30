import SwiftUI

// MARK: - File List View

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
                    FileRowView(node: node, siteViewModel: siteViewModel)
                        .contextMenu {
                            FolderContextMenu(node: node, siteViewModel: siteViewModel)
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
                FileRowView(node: node, siteViewModel: siteViewModel)
                    .tag(node.id)
                    .contextMenu {
                        FileContextMenu(node: node, siteViewModel: siteViewModel)
                    }
                    .onTapGesture {
                        siteViewModel.selectNode(node)
                    }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: siteViewModel.selectedFileID) { _, newValue in
            if let id = newValue {
                if let node = FileNode.findNode(id: id, in: siteViewModel.fileNodes) {
                    siteViewModel.selectNode(node)
                }
            }
        }
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
                FileRowView(node: node, siteViewModel: siteViewModel)
                    .contextMenu {
                        FolderContextMenu(node: node, siteViewModel: siteViewModel)
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
            FileRowView(node: node, siteViewModel: siteViewModel)
                .tag(node.id)
                .contextMenu {
                    FileContextMenu(node: node, siteViewModel: siteViewModel)
                }
                .onTapGesture {
                    siteViewModel.selectNode(node)
                }
        }
    }

}

// MARK: - File Row

struct FileRowView: View {
    let node: FileNode
    var siteViewModel: SiteViewModel? = nil

    /// File status for indicator display
    private var fileStatus: FileStatus {
        guard let viewModel = siteViewModel, node.isMarkdownFile else {
            return .none
        }

        if viewModel.isFileModified(node.id) {
            return .modified
        } else if viewModel.isFileRecentlySaved(node.id) {
            return .saved
        }
        return .none
    }

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

            // File status indicator
            FileStatusIndicator(status: fileStatus)
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

// MARK: - File Status

/// Represents the current status of a file
enum FileStatus: Equatable {
    case none
    case modified   // Has unsaved changes (orange dot)
    case saved      // Recently saved (green checkmark)
}

/// Visual indicator for file status in the sidebar
struct FileStatusIndicator: View {
    let status: FileStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch status {
            case .none:
                EmptyView()

            case .modified:
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                    .help("Unsaved changes")
                    .accessibilityLabel("Unsaved changes")
                    .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))

            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                    .help("Saved")
                    .accessibilityLabel("Recently saved")
                    .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: status)
    }
}

// MARK: - Context Menus

/// Context menu for folder nodes
struct FolderContextMenu: View {
    let node: FileNode
    let siteViewModel: SiteViewModel

    @State private var isRenaming = false
    @State private var newName = ""

    var body: some View {
        // Create operations
        Button {
            Task {
                await siteViewModel.createMarkdownFile(in: node)
            }
        } label: {
            Label("New Markdown File", systemImage: "doc.badge.plus")
        }

        Button {
            Task {
                await siteViewModel.createFolder(in: node)
            }
        } label: {
            Label("New Folder", systemImage: "folder.badge.plus")
        }

        Divider()

        // File operations
        Button {
            siteViewModel.revealInFinder(node: node)
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }

        Button {
            siteViewModel.copyPath(node: node)
        } label: {
            Label("Copy Path", systemImage: "doc.on.clipboard")
        }
    }
}

/// Context menu for file nodes
struct FileContextMenu: View {
    let node: FileNode
    let siteViewModel: SiteViewModel

    var body: some View {
        // Open
        Button {
            siteViewModel.selectNode(node)
        } label: {
            Label("Open", systemImage: "doc.text")
        }

        Divider()

        // File operations
        Button {
            Task {
                await siteViewModel.duplicateFile(node: node)
            }
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }

        Divider()

        Button(role: .destructive) {
            Task {
                await siteViewModel.moveToTrash(node: node)
            }
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }

        Divider()

        Button {
            siteViewModel.revealInFinder(node: node)
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }

        Button {
            siteViewModel.copyPath(node: node)
        } label: {
            Label("Copy Path", systemImage: "doc.on.clipboard")
        }
    }
}
