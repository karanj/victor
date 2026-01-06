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
                    set: { newValue in
                        node.isExpanded = newValue
                        // Load status metadata for children when folder is expanded
                        if newValue {
                            siteViewModel.onFolderExpanded(node)
                        }
                    }
                )) {
                    ForEach(node.children) { child in
                        FileTreeRow(node: child, siteViewModel: siteViewModel)
                    }
                } label: {
                    FileRowView(viewModel: siteViewModel.rowViewModel(for: node))
                        .tag(node.id)
                        .contextMenu {
                            FolderContextMenu(node: node, siteViewModel: siteViewModel)
                        }
                        .onTapGesture(count: 2) {
                            // Double-click to expand/collapse folder
                            node.isExpanded.toggle()
                            if node.isExpanded {
                                siteViewModel.onFolderExpanded(node)
                            }
                        }
                        .onTapGesture {
                            // Single-click to select folder (DisclosureGroup doesn't work with List selection)
                            siteViewModel.selectedFileID = node.id
                        }
                }
            } else {
                // Regular file row
                FileRowView(viewModel: siteViewModel.rowViewModel(for: node))
                    .tag(node.id)
                    .contextMenu {
                        FileContextMenu(node: node, siteViewModel: siteViewModel)
                    }
            }
        }
        .listStyle(.sidebar)
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
                set: { newValue in
                    node.isExpanded = newValue
                    // Load status metadata for children when folder is expanded
                    if newValue {
                        siteViewModel.onFolderExpanded(node)
                    }
                }
            )) {
                ForEach(node.children) { child in
                    FileTreeRow(node: child, siteViewModel: siteViewModel)
                }
            } label: {
                FileRowView(viewModel: siteViewModel.rowViewModel(for: node))
                    .tag(node.id)
                    .contextMenu {
                        FolderContextMenu(node: node, siteViewModel: siteViewModel)
                    }
                    .onTapGesture(count: 2) {
                        // Double-click to expand/collapse folder
                        node.isExpanded.toggle()
                        if node.isExpanded {
                            siteViewModel.onFolderExpanded(node)
                        }
                    }
                    .onTapGesture {
                        // Single-click to select folder (DisclosureGroup doesn't work with List selection)
                        siteViewModel.selectedFileID = node.id
                    }
            }
        } else {
            FileRowView(viewModel: siteViewModel.rowViewModel(for: node))
                .tag(node.id)
                .contextMenu {
                    FileContextMenu(node: node, siteViewModel: siteViewModel)
                }
        }
    }

}

// MARK: - File Row View Model

/// Cached view model for file row to avoid repeated computations
struct FileRowViewModel: Equatable {
    let id: UUID
    let name: String
    let iconName: String
    let iconColor: Color
    let accessibilityLabel: String
    let fileStatus: FileStatus
    let contentStatus: ContentStatus?
    let isPageBundle: Bool
    let isConfigFile: Bool
    let isDirectory: Bool
    let fileTypeDisplayName: String?

    @MainActor
    init(node: FileNode, siteViewModel: SiteViewModel?) {
        self.id = node.id
        self.name = node.name
        self.isPageBundle = node.isPageBundle
        self.isConfigFile = node.isConfigFile
        self.isDirectory = node.isDirectory

        // Compute icon (once)
        if node.isPageBundle {
            self.iconName = "folder.fill.badge.gearshape"
            self.iconColor = .purple
            self.accessibilityLabel = "Page bundle"
        } else if node.isDirectory {
            if let role = node.hugoRole {
                self.iconName = role.systemImage
                self.iconColor = role.accentColor
                self.accessibilityLabel = "\(role.displayName) folder"
            } else {
                self.iconName = "folder"
                self.iconColor = .blue
                self.accessibilityLabel = "Folder"
            }
        } else if node.isConfigFile {
            self.iconName = "gearshape.fill"
            self.iconColor = .orange
            self.accessibilityLabel = "Hugo config file"
        } else {
            self.iconName = node.fileType.systemImage
            self.iconColor = node.fileType.defaultColor
            self.accessibilityLabel = node.fileType.displayName
        }

        // Compute file status (once)
        if let viewModel = siteViewModel, node.isEditable {
            if viewModel.isFileModified(node.id) {
                self.fileStatus = .modified
            } else if viewModel.isFileRecentlySaved(node.id) {
                self.fileStatus = .saved
            } else {
                self.fileStatus = .none
            }
        } else {
            self.fileStatus = .none
        }

        self.contentStatus = node.contentStatus
        self.fileTypeDisplayName = (!node.isDirectory && !node.isMarkdownFile && !node.isConfigFile)
            ? node.fileType.displayName : nil
    }
}

// MARK: - File Row

struct FileRowView: View {
    let viewModel: FileRowViewModel

    var body: some View {
        HStack(spacing: 8) {
            // Icon: different for page bundles, folders, and files
            Image(systemName: viewModel.iconName)
                .foregroundStyle(viewModel.iconColor)
                .imageScale(.medium)
                .accessibilityLabel(viewModel.accessibilityLabel)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(viewModel.name)
                        .lineLimit(1)

                    // Page bundle badge
                    if viewModel.isPageBundle {
                        Text("bundle")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.purple)
                            .cornerRadius(3)
                    }

                    // Config file badge
                    if viewModel.isConfigFile {
                        Text("config")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.orange)
                            .cornerRadius(3)
                    }
                }

                // Content status badge (Draft/Scheduled/Expired)
                if let status = viewModel.contentStatus, status != .published {
                    ContentStatusBadge(status: status)
                }

                // File type indicator for non-markdown files
                if let displayName = viewModel.fileTypeDisplayName {
                    Text(displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // File status indicator
            FileStatusIndicator(status: viewModel.fileStatus)
        }
        .contentShape(Rectangle())
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
                    .accessibilityLabel("Unsaved changes")
                    .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))

            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                    .accessibilityLabel("Recently saved")
                    .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: status)
    }
}

// MARK: - Content Status Badge

/// Badge displaying content publication status (Draft/Scheduled/Expired)
struct ContentStatusBadge: View {
    let status: ContentStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(status.badgeColor)
            .cornerRadius(3)
    }

    private var foregroundColor: Color {
        switch status {
        case .draft, .scheduled, .expired:
            return .white
        case .published:
            return .clear
        }
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
