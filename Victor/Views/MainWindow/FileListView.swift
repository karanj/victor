import SwiftUI
import QuickLook

// MARK: - File List View

struct FileListView: View {
    @Bindable var siteViewModel: SiteViewModel

    @State private var quickLookURL: URL?
    /// Which sheet (if any) is presented, and for which node - consolidates
    /// what used to be five separate `@State` booleans on `FolderRowWithSheets`
    /// plus one on `FileRowWithSheets` plus the Return-key rename accelerator's
    /// own `renameTargetNode`, now that context-menu presentation moved from
    /// per-row to List-level `.contextMenu(forSelectionType:)` (victor-sel).
    /// See Docs/SELECTION-MODEL-MEMO.md section 4.
    @State private var sheetTarget: SheetTarget?
    /// Nodes pending the batch-trash confirmation alert (Delete key or the
    /// multi-selection "Move N Items to Trash" context menu item) - already
    /// pruned of ancestor-covered descendants so the alert's count matches
    /// the actual number of trash operations that will run. See
    /// Docs/SELECTION-MODEL-MEMO.md section 5.
    @State private var pendingTrashNodes: [FileNode]?

    var body: some View {
        List(siteViewModel.filteredNodes, selection: $siteViewModel.selectedFileIDs) { node in
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
                FileRowWithSheets(node: node, siteViewModel: siteViewModel)
                    .tag(node.id)
            }
        }
        .listStyle(.sidebar)
        // Single List-level context menu (victor-sel), replacing the former
        // per-row `.contextMenu` on FolderRowWithSheets/FileRowWithSheets.
        // `ids` is whatever the system hands back for this invocation - not
        // necessarily `selectedFileIDs` (right-clicking a row outside the
        // current selection replaces the selection with just that row, standard
        // macOS behavior `forSelectionType` gives for free). See
        // Docs/SELECTION-MODEL-MEMO.md section 4.
        .contextMenu(forSelectionType: FileNode.ID.self) { ids in
            SelectionContextMenu(
                ids: ids,
                siteViewModel: siteViewModel,
                sheetTarget: $sheetTarget,
                pendingTrashNodes: $pendingTrashNodes
            )
        } primaryAction: { ids in
            // List(selection:)'s own click handling already updates
            // selectedFileIDs on a plain click - unrelated to primaryAction,
            // which only fires on double-click. Today there's no explicit
            // double-click-to-open, since single-click-to-select already
            // opens the file as a side effect of selection; this is a
            // no-op-preserving safety net for exactly-one-target double-clicks.
            if ids.count == 1, let node = siteViewModel.findNode(id: ids.first!) {
                siteViewModel.selectNode(node)
            }
        }
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
        // Finder-familiar Return-to-rename accelerator. Only fires when the
        // List itself holds key focus - the sidebar's search TextField
        // (SearchBar, a sibling of FileListView in SidebarView, not a
        // descendant of this List) keeps its own normal Return behavior
        // because .onKeyPress here never sees key events delivered to a
        // separately-focused text field elsewhere in the view tree.
        .onKeyPress(.return) {
            guard let node = siteViewModel.selectedNode else { return .ignored }
            sheetTarget = .rename(node)
            return .handled
        }
        // Delete-key batch trash (victor-sel) - always routes through the
        // confirmation alert below, even for a single selected node, since
        // there was no Delete-key-to-trash accelerator before this change.
        // See Docs/SELECTION-MODEL-MEMO.md section 5.
        .onDeleteCommand {
            let nodes = siteViewModel.selectedFileIDs.compactMap { siteViewModel.findNode(id: $0) }
            guard !nodes.isEmpty else { return }
            pendingTrashNodes = siteViewModel.pruneDescendants(of: nodes)
        }
        // Cmd+C: one NSItemProvider per selected file, registering both the
        // file URL (a paste into Finder performs a real file copy) and the
        // path string (a paste into a text context yields the absolute path,
        // mirroring Copy Path). Ordered by tree display order, not
        // Set-iteration-random order. See Docs/SELECTION-MODEL-MEMO.md section 6.
        .onCopyCommand {
            siteViewModel.treeOrderIndex(of: siteViewModel.selectedFileIDs)
                .compactMap { siteViewModel.findNode(id: $0) }
                .map { node in
                    let provider = NSItemProvider(contentsOf: node.url) ?? NSItemProvider()
                    provider.registerObject(node.url.path as NSString, visibility: .all)
                    return provider
                }
        }
        .quickLookPreview($quickLookURL)
        .sheet(item: $sheetTarget) { target in
            sheetContent(for: target)
        }
        .alert(
            trashConfirmationTitle,
            isPresented: Binding(
                get: { pendingTrashNodes != nil },
                set: { if !$0 { pendingTrashNodes = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pendingTrashNodes = nil
            }
            Button("Move to Trash", role: .destructive) {
                let nodes = pendingTrashNodes ?? []
                pendingTrashNodes = nil
                Task {
                    await siteViewModel.moveToTrash(nodes: nodes)
                }
            }
        }
    }

    /// "Move N Items to Trash?" (or the singular "Move "name" to Trash?" for
    /// one item) - N is the already-pruned count in `pendingTrashNodes`, not
    /// the raw selection count (a folder and its descendants collapse to one
    /// pruned operation). See Docs/SELECTION-MODEL-MEMO.md section 5.
    private var trashConfirmationTitle: String {
        guard let nodes = pendingTrashNodes else { return "" }
        if nodes.count == 1, let name = nodes.first?.name {
            return "Move \u{201C}\(name)\u{201D} to Trash?"
        }
        return "Move \(nodes.count) Items to Trash?"
    }

    /// Dispatches a `SheetTarget` to its concrete sheet view - mirrors the
    /// bodies formerly inlined in `FolderRowWithSheets`'s five `.sheet`
    /// modifiers, now presented once at the List level instead of once per row.
    @ViewBuilder
    private func sheetContent(for target: SheetTarget) -> some View {
        switch target {
        case .rename(let node):
            RenameSheet(node: node, siteViewModel: siteViewModel)
        case .newContent(let node):
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
        case .newDataFile(let node):
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
        case .newTranslation(let node):
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
        case .newArchetype(let node):
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

    /// Resolves a freshly-created file's URL to its canonical `FileNode` after
    /// `reloadSite()` rebuilds the tree - moved here from `FolderRowWithSheets`
    /// now that sheet presentation lives at the List level.
    private func findNodeByURL(_ url: URL) -> FileNode? {
        for rootNode in siteViewModel.fileNodes {
            if let found = rootNode.findNode(url: url) {
                return found
            }
        }
        return nil
    }
}

// MARK: - Sheet Target

/// Which sheet `FileListView` is presenting, and for which node - see the
/// `sheetTarget` state property above and Docs/SELECTION-MODEL-MEMO.md section 4.
/// Internal (not private) because `SelectionContextMenu`'s binding property
/// exposes it at internal access.
enum SheetTarget: Identifiable {
    case rename(FileNode)
    case newContent(FileNode)      // "New Content from Archetype..." target folder
    case newDataFile(FileNode)
    case newTranslation(FileNode)
    case newArchetype(FileNode)

    var id: String {
        switch self {
        case .rename(let n): return "rename-\(n.id)"
        case .newContent(let n): return "newContent-\(n.id)"
        case .newDataFile(let n): return "newDataFile-\(n.id)"
        case .newTranslation(let n): return "newTranslation-\(n.id)"
        case .newArchetype(let n): return "newArchetype-\(n.id)"
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
            FileRowWithSheets(node: node, siteViewModel: siteViewModel)
                .tag(node.id)
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
    // `View` conformance infers @MainActor isolation onto the whole type including
    // plain stored properties, which then blocks reading them from the
    // `nonisolated static func ==` below (needed for the `Equatable` conformance
    // itself, whose requirement is nonisolated by contract).
    // `FileRowViewModel` is a plain `Sendable`-eligible struct (UUID/String/Color/
    // Bool/etc.), so plain `nonisolated` suffices for it.
    nonisolated let viewModel: FileRowViewModel
    /// The node is passed separately to observe contentStatus changes (loaded async).
    /// `nonisolated(unsafe)`, not plain `nonisolated`, because `FileNode` isn't
    /// `Sendable` (weak parent + recursive children, CLAUDE.md: must stay a class).
    /// `(unsafe)` is safe in practice because `FileRowView` (a SwiftUI view) is only
    /// ever constructed/compared on the main actor to begin with - the type system
    /// just can't prove that through the `Equatable` conformance boundary (WP3.5
    /// Cluster 7).
    nonisolated(unsafe) let node: FileNode

    // `nonisolated`: `View`'s `body` carries an implicit `@MainActor`, but
    // `Equatable`'s requirement is nonisolated by contract - that mismatch is
    // exactly what the warning names. `node.contentStatuses` isn't itself
    // actor-isolated (`FileNode` is a plain class), so there's nothing to
    // snapshot here; the fix is annotation-only (WP3.5 Cluster 7).
    nonisolated static func == (lhs: FileRowView, rhs: FileRowView) -> Bool {
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
        // Combines the icon's type label, name, badges, and status indicator
        // into one VoiceOver stop per row instead of five-plus separate ones -
        // standard list-row grouping, and the combined announcement already
        // carries selection-relevant context (name) and file status (badges +
        // FileStatusIndicator's "Unsaved changes"/"Recently saved" label).
        .accessibilityElement(children: .combine)
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

// MARK: - Drag Out

/// Builds the drag-out payload for a sidebar row (victor-sel B.4). If `node`
/// is part of the current multi-selection (2+ members), the grabbed row's
/// own file is still the ONLY one draggable as a real file-copy - SwiftUI's
/// `.onDrag` hands back exactly one `NSItemProvider` per drag gesture (same
/// ceiling AssetBrowserView's single-asset drag source runs into), so a true
/// multi-file Finder drop (N separate file-promise items from one gesture)
/// isn't achievable with this API. The full selection's paths (tree order)
/// are attached as a secondary plain-text representation instead, so a drop
/// into a text-accepting destination (a text editor, Terminal) still
/// surfaces every selected path - not silently dropped, just not expressed
/// as N separate Finder-recognized files; a drop onto Finder itself will
/// only copy the single grabbed file. Dragging a row that ISN'T part of the
/// current selection drags just that row (standard macOS behavior).
/// `@MainActor`: reads `selectedFileIDs`/`treeOrderIndex`/`findNode` on the
/// main-actor-isolated SiteViewModel; `.onDrag` closures in the row views are
/// main-actor-inferred (same pattern as AssetBrowserView's drag source).
@MainActor
private func dragItemProvider(for node: FileNode, siteViewModel: SiteViewModel) -> NSItemProvider {
    let selection = siteViewModel.selectedFileIDs
    if selection.count > 1, selection.contains(node.id) {
        let allPaths = siteViewModel.treeOrderIndex(of: selection)
            .compactMap { siteViewModel.findNode(id: $0)?.url.path }
        return FileDragItemProvider.make(for: node.url, secondaryRepresentation: allPaths.joined(separator: "\n"))
    }
    return FileDragItemProvider.make(for: node.url, secondaryRepresentation: node.url.path)
}

// MARK: - Row Wrappers

/// Wrapper view for a folder row - keeps only what's specific to folder rows
/// (drop-target overlay/`.dropDestination`, drag-out source) plus
/// `.equatable()` row rendering. No longer owns sheet state or a
/// `.contextMenu` (victor-sel): both moved to the List level
/// (`FileListView.body`'s `.contextMenu(forSelectionType:)` and
/// `.sheet(item: $sheetTarget)`) since a per-row context menu can't represent
/// a multi-row selection. See Docs/SELECTION-MODEL-MEMO.md section 4.
struct FolderRowWithSheets: View {
    let node: FileNode
    let siteViewModel: SiteViewModel

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
            // Drag-out source (victor-sel B.4) - see dragItemProvider's doc
            // comment above for the multi-selection/single-provider caveat.
            .onDrag {
                dragItemProvider(for: node, siteViewModel: siteViewModel)
            }
            // Accept file drops onto folder rows - either a same-site MOVE or
            // (for drops from outside the site, e.g. Finder) the existing
            // copy/import path. `node` here can be an ephemeral
            // filtered-search copy (see SiteViewModel.importDroppedFile's doc
            // comment), so the move-vs-copy decision and canonical-node
            // resolution both live in `handleDroppedFile` instead of here.
            .dropDestination(for: URL.self) { droppedURLs, _ in
                guard node.isDirectory, !droppedURLs.isEmpty else { return false }
                for sourceURL in droppedURLs {
                    Task {
                        await siteViewModel.handleDroppedFile(from: sourceURL, into: node)
                    }
                }
                return true
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }
    }
}

/// Wrapper view for a (non-directory) file row - `.equatable()` row
/// rendering plus drag-out source (victor-sel B.4). No longer owns sheet
/// state or a `.contextMenu` (victor-sel) - see `FolderRowWithSheets`'s doc
/// comment above.
struct FileRowWithSheets: View {
    let node: FileNode
    let siteViewModel: SiteViewModel

    var body: some View {
        FileRowView(viewModel: siteViewModel.rowViewModel(for: node), node: node)
            .equatable()
            .onDrag {
                dragItemProvider(for: node, siteViewModel: siteViewModel)
            }
    }
}

// MARK: - Selection Context Menu

/// Single dispatcher for the sidebar's context menu, driven by
/// `.contextMenu(forSelectionType:)` on `FileListView`'s List (victor-sel) -
/// replaces the former per-row `FileContextMenu`/`FolderContextMenu` pair.
/// `ids` is whatever the system hands back for this invocation - not
/// necessarily `siteViewModel.selectedFileIDs`, since right-clicking a row
/// outside the current selection replaces the selection with just that row
/// (standard macOS behavior). See Docs/SELECTION-MODEL-MEMO.md section 4.
struct SelectionContextMenu: View {
    let ids: Set<FileNode.ID>
    let siteViewModel: SiteViewModel
    @Binding var sheetTarget: SheetTarget?
    @Binding var pendingTrashNodes: [FileNode]?

    private var nodes: [FileNode] {
        siteViewModel.treeOrderIndex(of: ids).compactMap { siteViewModel.findNode(id: $0) }
    }

    var body: some View {
        let resolved = nodes
        if resolved.count == 1 {
            singleTargetMenu(for: resolved[0])
        } else if resolved.count > 1 {
            multiTargetMenu(for: resolved)
        }
    }

    // MARK: Single target (content unchanged from the former FileContextMenu/FolderContextMenu)

    @ViewBuilder
    private func singleTargetMenu(for node: FileNode) -> some View {
        if node.isDirectory {
            folderMenu(for: node)
        } else {
            fileMenu(for: node)
        }
    }

    @ViewBuilder
    private func folderMenu(for node: FileNode) -> some View {
        let isInContentDirectory = isDescendantOfOrRole(node, .content)
        let isInDataDirectory = isDescendantOfOrRole(node, .data)
        let isInI18nDirectory = isDescendantOfOrRole(node, .i18n)
        let isInArchetypesDirectory = isDescendantOfOrRole(node, .archetypes)

        // Content directory: New Content from Archetype
        if isInContentDirectory, siteViewModel.site?.rootURL != nil {
            Button {
                sheetTarget = .newContent(node)
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
                sheetTarget = .newDataFile(node)
            } label: {
                Label("New Data File...", systemImage: "doc.badge.gearshape")
            }
        }

        // i18n directory: New Translation File
        if isInI18nDirectory {
            Button {
                sheetTarget = .newTranslation(node)
            } label: {
                Label("New Translation File...", systemImage: "globe.badge.plus")
            }
        }

        // Archetypes directory: New Archetype
        if isInArchetypesDirectory {
            Button {
                sheetTarget = .newArchetype(node)
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
            sheetTarget = .rename(node)
        } label: {
            Label("Rename…", systemImage: "pencil")
        }

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

    @ViewBuilder
    private func fileMenu(for node: FileNode) -> some View {
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

        Button {
            sheetTarget = .rename(node)
        } label: {
            Label("Rename…", systemImage: "pencil")
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

    private func isDescendantOfOrRole(_ node: FileNode, _ role: HugoRole) -> Bool {
        if node.hugoRole == role { return true }
        var current: FileNode? = node.parent
        while let parent = current {
            if parent.hugoRole == role {
                return true
            }
            current = parent.parent
        }
        return false
    }

    // MARK: Multi target - disable/omit single-target-only items (Open,
    // Duplicate, Rename, New-X folder creation); show set-scoped items instead.

    @ViewBuilder
    private func multiTargetMenu(for nodes: [FileNode]) -> some View {
        Button(role: .destructive) {
            pendingTrashNodes = siteViewModel.pruneDescendants(of: nodes)
        } label: {
            Label("Move \(nodes.count) Items to Trash", systemImage: "trash")
        }

        Divider()

        // Mixed files+folders: Reveal in Finder and Copy Path both operate
        // over the resolved node/URL set regardless of type, no special-casing.
        Button {
            siteViewModel.revealInFinder(nodes: nodes)
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }

        Button {
            siteViewModel.copyPathsToClipboard(urls: nodes.map(\.url))
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
