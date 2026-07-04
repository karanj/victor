import SwiftUI
import QuickLook

// MARK: - File List View

struct FileListView: View {
    @Bindable var siteViewModel: SiteViewModel

    @State private var quickLookURL: URL?

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
                    FolderRowWithSheets(node: node, siteViewModel: siteViewModel)
                }
                .tag(node.id)
            } else {
                // Regular file row
                FileRowView(viewModel: siteViewModel.rowViewModel(for: node), node: node)
                    .equatable()
                    .tag(node.id)
                    .contextMenu {
                        FileContextMenu(node: node, siteViewModel: siteViewModel)
                    }
            }
        }
        .listStyle(.sidebar)
        // Space Quick Looks the selected file, but only when it's not an
        // editable text type (markdown, config, code, etc). Editable files
        // route Space through to the editor's NSTextView for typing, so we
        // deliberately don't intercept it here for those - only non-editable
        // files (images, PDFs, binaries) get Quick Look on Space.
        .onKeyPress(.space) {
            guard let node = siteViewModel.selectedNode,
                  !node.isDirectory,
                  !node.isEditable else {
                return .ignored
            }
            quickLookURL = node.url
            return .handled
        }
        .quickLookPreview($quickLookURL)
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
                FolderRowWithSheets(node: node, siteViewModel: siteViewModel)
            }
            .tag(node.id)
        } else {
            FileRowView(viewModel: siteViewModel.rowViewModel(for: node), node: node)
                .equatable()
                .tag(node.id)
                .contextMenu {
                    FileContextMenu(node: node, siteViewModel: siteViewModel)
                }
        }
    }

}

// MARK: - File Row View Model

/// Cached view model for file row to avoid repeated computations
/// Note: contentStatus is NOT cached here - it's read directly from FileNode
/// to ensure async-loaded status metadata triggers re-renders
struct FileRowViewModel: Equatable {
    let id: UUID
    let name: String
    let iconName: String
    let iconColor: Color
    let accessibilityLabel: String
    let fileStatus: FileStatus
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
            self.iconColor = Color.FileIcon.pageBundle
            self.accessibilityLabel = "Page bundle"
        } else if node.isDirectory {
            if let role = node.hugoRole {
                self.iconName = role.systemImage
                self.iconColor = role.accentColor
                self.accessibilityLabel = "\(role.displayName) folder"
            } else {
                self.iconName = "folder"
                self.iconColor = Color.FileIcon.folder
                self.accessibilityLabel = "Folder"
            }
        } else if node.isConfigFile {
            self.iconName = "gearshape.fill"
            self.iconColor = Color.FileIcon.config
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

        self.fileTypeDisplayName = (!node.isDirectory && !node.isMarkdownFile && !node.isConfigFile)
            ? node.fileType.displayName : nil
    }
}

// MARK: - File Row

struct FileRowView: View, Equatable {
    let viewModel: FileRowViewModel
    /// The node is passed separately to observe contentStatus changes (loaded async)
    let node: FileNode

    static func == (lhs: FileRowView, rhs: FileRowView) -> Bool {
        lhs.viewModel == rhs.viewModel &&
        lhs.node.contentStatuses == rhs.node.contentStatuses
    }

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
                            .foregroundStyle(Color.Badge.pageBundle.contrastingTextColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.Badge.pageBundle)
                            .cornerRadius(3)
                    }

                    // Config file badge
                    if viewModel.isConfigFile {
                        Text("config")
                            .font(.caption2)
                            .foregroundStyle(Color.Badge.config.contrastingTextColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.Badge.config)
                            .cornerRadius(3)
                    }
                }

                // Content status badges (Draft/Scheduled/Expired)
                // Read directly from node to observe async changes
                // A file can have multiple statuses (e.g., draft AND scheduled)
                let statuses = node.contentStatuses
                if !statuses.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(statuses, id: \.self) { status in
                            ContentStatusBadge(status: status)
                        }
                    }
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
                    .fill(Color.Status.modified)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Unsaved changes")
                    .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))

            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.Status.saved)
                    .accessibilityLabel("Recently saved")
                    .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: AppConstants.Animation.standard), value: status)
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
            .help(tooltipText)
    }

    private var foregroundColor: Color {
        switch status {
        case .draft, .scheduled, .expired:
            // Use contrast-aware text color based on badge background luminance
            return status.badgeColor.contrastingTextColor
        case .published:
            return .clear
        }
    }

    private var tooltipText: String {
        switch status {
        case .draft:
            return "Draft: This content has draft: true and won't be published"
        case .scheduled:
            return "Scheduled: This content has a future publish date"
        case .expired:
            return "Expired: This content has passed its expiry date"
        case .published:
            return "Published: This content is live"
        }
    }
}

// MARK: - Context Menus

/// Context menu for folder nodes - returns menu items only
/// Sheets are handled by FolderRowWithSheets wrapper
struct FolderContextMenu: View {
    let node: FileNode
    let siteViewModel: SiteViewModel
    @Binding var showNewContentSheet: Bool
    @Binding var showNewDataFileSheet: Bool
    @Binding var showNewTranslationSheet: Bool
    @Binding var showNewArchetypeSheet: Bool

    /// Check if this folder is within content/ directory
    private var isInContentDirectory: Bool {
        node.hugoRole == .content || isDescendantOf(role: .content)
    }

    /// Check if this folder is within data/ directory
    private var isInDataDirectory: Bool {
        node.hugoRole == .data || isDescendantOf(role: .data)
    }

    /// Check if this folder is within i18n/ directory
    private var isInI18nDirectory: Bool {
        node.hugoRole == .i18n || isDescendantOf(role: .i18n)
    }

    /// Check if this folder is within archetypes/ directory
    private var isInArchetypesDirectory: Bool {
        node.hugoRole == .archetypes || isDescendantOf(role: .archetypes)
    }

    private func isDescendantOf(role: HugoRole) -> Bool {
        var current: FileNode? = node.parent
        while let parent = current {
            if parent.hugoRole == role {
                return true
            }
            current = parent.parent
        }
        return false
    }

    var body: some View {
        // Content directory: New Content from Archetype
        if isInContentDirectory, siteViewModel.site?.rootURL != nil {
            Button {
                showNewContentSheet = true
            } label: {
                Label("New Content from Archetype...", systemImage: "doc.badge.gearshape")
            }

            Button {
                Task {
                    await siteViewModel.createMarkdownFile(in: node)
                }
            } label: {
                Label("New Markdown File", systemImage: "doc.badge.plus")
            }
        }

        // Data directory: New Data File
        if isInDataDirectory {
            Button {
                showNewDataFileSheet = true
            } label: {
                Label("New Data File...", systemImage: "doc.badge.gearshape")
            }
        }

        // i18n directory: New Translation File
        if isInI18nDirectory {
            Button {
                showNewTranslationSheet = true
            } label: {
                Label("New Translation File...", systemImage: "globe.badge.plus")
            }
        }

        // Archetypes directory: New Archetype
        if isInArchetypesDirectory {
            Button {
                showNewArchetypeSheet = true
            } label: {
                Label("New Archetype...", systemImage: "doc.text.fill.viewfinder")
            }
        }

        // Generic folder operations (always shown)
        if !isInContentDirectory && !isInDataDirectory && !isInI18nDirectory && !isInArchetypesDirectory {
            Button {
                Task {
                    await siteViewModel.createMarkdownFile(in: node)
                }
            } label: {
                Label("New Markdown File", systemImage: "doc.badge.plus")
            }
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

/// Wrapper view that handles folder row with context menu and sheets
struct FolderRowWithSheets: View {
    let node: FileNode
    let siteViewModel: SiteViewModel

    @State private var showNewContentSheet = false
    @State private var showNewDataFileSheet = false
    @State private var showNewTranslationSheet = false
    @State private var showNewArchetypeSheet = false
    @State private var isDropTargeted = false

    var body: some View {
        FileRowView(viewModel: siteViewModel.rowViewModel(for: node), node: node)
            .equatable()
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
            // Accept file drops (images and any other file type) onto folder rows.
            // `node` here can be an ephemeral filtered-search copy (see
            // SiteViewModel.importDroppedFile's doc comment), so the actual import -
            // resolving the canonical node, copying, inserting, registering,
            // invalidating the filter cache - lives there instead of here.
            .dropDestination(for: URL.self) { droppedURLs, _ in
                guard node.isDirectory, !droppedURLs.isEmpty else { return false }
                for sourceURL in droppedURLs {
                    Task {
                        await siteViewModel.importDroppedFile(from: sourceURL, into: node)
                    }
                }
                return true
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }
            .contextMenu {
                FolderContextMenu(
                    node: node,
                    siteViewModel: siteViewModel,
                    showNewContentSheet: $showNewContentSheet,
                    showNewDataFileSheet: $showNewDataFileSheet,
                    showNewTranslationSheet: $showNewTranslationSheet,
                    showNewArchetypeSheet: $showNewArchetypeSheet
                )
            }
            .sheet(isPresented: $showNewContentSheet) {
                if let siteURL = siteViewModel.site?.rootURL {
                    NewContentView(
                        siteURL: siteURL,
                        targetDirectory: node.url,
                        onCreated: { fileURL in
                            Task {
                                await siteViewModel.reloadSite()
                                if let newNode = findNodeByURL(fileURL) {
                                    siteViewModel.selectNode(newNode)
                                }
                            }
                        }
                    )
                }
            }
            .sheet(isPresented: $showNewDataFileSheet) {
                NewDataFileView(
                    targetDirectory: node.url,
                    onCreated: { fileURL in
                        Task {
                            await siteViewModel.reloadSite()
                            if let newNode = findNodeByURL(fileURL) {
                                siteViewModel.selectNode(newNode)
                            }
                        }
                    }
                )
            }
            .sheet(isPresented: $showNewTranslationSheet) {
                NewTranslationFileView(
                    targetDirectory: node.url,
                    onCreated: { fileURL in
                        Task {
                            await siteViewModel.reloadSite()
                            if let newNode = findNodeByURL(fileURL) {
                                siteViewModel.selectNode(newNode)
                            }
                        }
                    }
                )
            }
            .sheet(isPresented: $showNewArchetypeSheet) {
                NewArchetypeView(
                    targetDirectory: node.url,
                    onCreated: { fileURL in
                        Task {
                            await siteViewModel.reloadSite()
                            if let newNode = findNodeByURL(fileURL) {
                                siteViewModel.selectNode(newNode)
                            }
                        }
                    }
                )
            }
    }

    private func findNodeByURL(_ url: URL) -> FileNode? {
        for rootNode in siteViewModel.fileNodes {
            if let found = rootNode.findNode(url: url) {
                return found
            }
        }
        return nil
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

// MARK: - Previews

#Preview("File Status Indicators") {
    VStack(alignment: .leading, spacing: 16) {
        HStack {
            Text("No status:")
            Spacer()
            FileStatusIndicator(status: .none)
        }

        HStack {
            Text("Modified:")
            Spacer()
            FileStatusIndicator(status: .modified)
        }

        HStack {
            Text("Saved:")
            Spacer()
            FileStatusIndicator(status: .saved)
        }
    }
    .padding()
    .frame(width: 200)
}

#Preview("Content Status Badges") {
    VStack(alignment: .leading, spacing: 12) {
        ContentStatusBadge(status: .draft)
        ContentStatusBadge(status: .scheduled)
        ContentStatusBadge(status: .expired)
    }
    .padding()
}
