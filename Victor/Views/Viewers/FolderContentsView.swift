import SwiftUI

/// Displays the contents of a folder when selected in the sidebar
struct FolderContentsView: View {
    let node: FileNode
    @Bindable var siteViewModel: SiteViewModel

    @State private var viewMode: FolderViewMode = .list

    var body: some View {
        VStack(spacing: 0) {
            // Header
            folderHeader
            Divider()

            // Contents
            if node.children.isEmpty {
                emptyFolderView
            } else {
                switch viewMode {
                case .grid:
                    gridView
                case .list:
                    listView
                }
            }
        }
        .onAppear {
            // Load status metadata for children when folder is displayed
            siteViewModel.onFolderExpanded(node)
        }
    }

    // MARK: - Header

    private var folderHeader: some View {
        HStack {
            // Folder icon and name
            Image(systemName: node.hugoRole?.systemImage ?? "folder.fill")
                .foregroundStyle(node.hugoRole?.accentColor ?? .blue)
                .font(.title2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                if let role = node.hugoRole {
                    Text(role.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Item count
            Text("\(node.children.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider().frame(height: 20)

            // View mode toggle
            Picker("View", selection: $viewMode) {
                ForEach(FolderViewMode.allCases) { mode in
                    Image(systemName: mode.icon)
                        .accessibilityLabel(mode.rawValue)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: AppConstants.Toolbar.viewIconLabelFrameWidth)

            // Reveal in Finder
            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: node.url.path)
            } label: {
                Image(systemName: "folder")
            }
            .help("Reveal in Finder")
            .accessibilityLabel("Reveal in Finder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Empty State

    private var emptyFolderView: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Empty Folder")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("This folder has no contents")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: node.url.path)
            } label: {
                Label("Open in Finder", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
            // TODO Add buttons for contextually appropriate data, e.g. New Data File in the data/ folder, New Translation in i18n/, new post in content/, etc
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Grid View

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 16) {
                ForEach(sortedChildren) { child in
                    FolderItemGridCell(node: child)
                        .onTapGesture(count: 2) {
                            handleDoubleClick(child)
                        }
                        .onTapGesture {
                            siteViewModel.selectNode(child)
                        }
                }
            }
            .padding()
        }
    }

    // MARK: - List View

    private var listView: some View {
        List(sortedChildren) { child in
            FolderItemListRow(node: child)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    handleDoubleClick(child)
                }
                .onTapGesture {
                    siteViewModel.selectNode(child)
                }
        }
        .listStyle(.plain)
    }

    // MARK: - Helpers

    /// Sort children: folders first, then files, alphabetically
    private var sortedChildren: [FileNode] {
        node.children.sorted { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// Handle double-click: expand folder or select file
    private func handleDoubleClick(_ child: FileNode) {
        if child.isDirectory {
            // Expand the folder in sidebar and select it
            child.isExpanded = true
            siteViewModel.onFolderExpanded(child)
        }
        siteViewModel.selectNode(child)
    }
}

// MARK: - View Mode

enum FolderViewMode: String, CaseIterable, Identifiable {
    case grid = "Grid"
    case list = "List"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}

// MARK: - Grid Cell

struct FolderItemGridCell: View {
    let node: FileNode

    var body: some View {
        VStack(spacing: 8) {
            // Icon
            Image(systemName: iconName)
                .font(.system(size: 32))
                .foregroundStyle(iconColor)
                .frame(width: 60, height: 50)
                .accessibilityHidden(true)

            // Name
            Text(node.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 90)

            // Content status badges (Draft/Scheduled/Expired)
            let statuses = node.contentStatuses
            if !statuses.isEmpty {
                HStack(spacing: 2) {
                    ForEach(statuses, id: \.self) { status in
                        ContentStatusBadge(status: status)
                    }
                }
            } else if !node.isDirectory {
                // Type badge for non-markdown files
                Text(node.fileType.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.2))
                    .cornerRadius(3)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    private var iconName: String {
        if node.isPageBundle {
            return "folder.fill.badge.gearshape"
        } else if node.isDirectory {
            return node.hugoRole?.systemImage ?? "folder.fill"
        } else {
            return node.fileType.systemImage
        }
    }

    private var iconColor: Color {
        if node.isPageBundle {
            return Color.FileIcon.pageBundle
        } else if node.isDirectory {
            return node.hugoRole?.accentColor ?? Color.FileIcon.folder
        } else {
            return node.fileType.defaultColor
        }
    }
}

// MARK: - List Row

struct FolderItemListRow: View {
    let node: FileNode

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 24)
                .accessibilityHidden(true)

            // Name and details
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(node.name)
                        .lineLimit(1)

                    if node.isPageBundle {
                        Text("bundle")
                            .font(.caption2)
                            .foregroundStyle(Color.Badge.pageBundle.contrastingTextColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.Badge.pageBundle)
                            .cornerRadius(3)
                    }

                    // Content status badges (Draft/Scheduled/Expired)
                    ForEach(node.contentStatuses, id: \.self) { status in
                        ContentStatusBadge(status: status)
                    }
                }

                // Subtitle
                HStack(spacing: 8) {
                    if node.isDirectory {
                        Text("\(node.children.count) items")
                    } else {
                        Text(node.fileType.displayName)
                    }

                    if let role = node.hugoRole {
                        Text("•")
                        Text(role.displayName)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Chevron for folders
            if node.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        if node.isPageBundle {
            return "folder.fill.badge.gearshape"
        } else if node.isDirectory {
            return node.hugoRole?.systemImage ?? "folder.fill"
        } else {
            return node.fileType.systemImage
        }
    }

    private var iconColor: Color {
        if node.isPageBundle {
            return Color.FileIcon.pageBundle
        } else if node.isDirectory {
            return node.hugoRole?.accentColor ?? Color.FileIcon.folder
        } else {
            return node.fileType.defaultColor
        }
    }
}
