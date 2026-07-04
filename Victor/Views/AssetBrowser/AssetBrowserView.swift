import SwiftUI
import UniformTypeIdentifiers
import QuickLook

/// Main view for browsing and managing assets
struct AssetBrowserView: View {
    let folderURL: URL           // The specific folder being browsed (static/ or assets/)
    let isAssetsDir: Bool        // true = assets/, false = static/
    let onInsert: ((String) -> Void)?  // Callback when inserting into markdown

    @State private var assets: [Asset] = []
    @State private var filteredAssets: [Asset] = []
    @State private var isLoading = true
    @State private var selectedAsset: Asset?
    @State private var viewMode: AssetViewMode = .grid
    @State private var filterType: AssetFilterType = .all
    @State private var searchText = ""
    @State private var sortOrder: AssetSortOrder = .name
    @State private var quickLookURL: URL?

    /// Updates filteredAssets based on current filter/search/sort criteria
    /// Called only when inputs change, not on every view update
    private func updateFilteredAssets() {
        var result = assets

        // Apply search
        if !searchText.isEmpty {
            result = result.filter {
                $0.url.lastPathComponent.localizedCaseInsensitiveContains(searchText) ||
                $0.relativePath.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Apply filter
        result = result.filter { filterType.matches($0) }

        // Apply sort
        result.sort { sortOrder.compare($0, $1) }

        filteredAssets = result
    }

    var body: some View {
        splitContent
            .quickLookPreview($quickLookURL)
            .task {
                await loadAssets()
            }
            .onChange(of: assets) { _, _ in updateFilteredAssets() }
            .onChange(of: searchText) { _, _ in updateFilteredAssets() }
            .onChange(of: filterType) { _, _ in updateFilteredAssets() }
            .onChange(of: sortOrder) { _, _ in updateFilteredAssets() }
    }

    private var splitContent: some View {
        HSplitView {
            // Asset browser
            VStack(spacing: 0) {
                assetToolbar
                Divider()

                if isLoading {
                    loadingView
                } else if assets.isEmpty {
                    emptyState
                } else if filteredAssets.isEmpty {
                    noResultsView
                } else {
                    assetContent
                        // Space Quick Looks the selected asset. Grid mode has no
                        // built-in selection focus like List, so this container
                        // is made focusable to receive the key press regardless
                        // of view mode (grid/list share this handler).
                        .focusable()
                        .onKeyPress(.space) {
                            guard let asset = selectedAsset else { return .ignored }
                            quickLookURL = asset.url
                            return .handled
                        }
                }
            }

            // Asset detail panel
            if let asset = selectedAsset {
                AssetDetailPanel(asset: asset, onInsert: onInsert)
                    .frame(minWidth: 250, maxWidth: 300)
            }
        }
    }

    // MARK: - Toolbar

    private var assetToolbar: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(isAssetsDir ? "assets/" : "static/")
                        .font(.headline)

                    Text("Site Assets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text("\(filteredAssets.count) of \(assets.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Filter
                Picker("Filter", selection: $filterType) {
                    ForEach(AssetFilterType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                Spacer()
                
                // Refresh button
                Button {
                    Task { await loadAssets() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh assets")
                
                Divider().frame(height: 20)
                // Sort
                Picker("Sort", selection: $sortOrder) {
                    ForEach(AssetSortOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .frame(width: 120)

                Divider().frame(height: 20)

                // View mode
                Picker("View", selection: $viewMode) {
                    ForEach(AssetViewMode.allCases) { mode in
                        Image(systemName: mode.icon)
                            .tag(mode)
                            .accessibilityLabel("\(mode.rawValue) view")
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: AppConstants.Toolbar.viewIconLabelFrameWidth)
                .accessibilityLabel("View mode")

                Divider().frame(height: 20)

                // Search
                TextField("Search...", text: $searchText)
                    .frame(width: 150)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content Views

    private var loadingView: some View {
        LoadingStateView(message: "Loading assets...")
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "photo.on.rectangle.angled",
            title: "No Assets Found",
            message: "Add files to this directory",
            actionLabel: "Open in Finder",
            actionIcon: "folder"
        ) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
        }
    }

    private var noResultsView: some View {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No Matching Assets",
            message: "Try adjusting your search or filter",
            actionLabel: "Clear Filters"
        ) {
            searchText = ""
            filterType = .all
        }
    }

    @ViewBuilder
    private var assetContent: some View {
        switch viewMode {
        case .grid:
            assetGridView
        case .list:
            assetListView
        }
    }

    private var assetGridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 16) {
                ForEach(filteredAssets) { asset in
                    AssetGridItem(asset: asset, isSelected: asset == selectedAsset, onInsert: onInsert)
                        .onTapGesture {
                            selectedAsset = asset
                        }
                        .onDrag {
                            assetDragItemProvider(for: asset)
                        }
                        .task {
                            // Load metadata lazily
                            if !asset.isMetadataLoaded {
                                await AssetService.shared.loadAssetMetadata(asset)
                            }
                        }
                }
            }
            .padding()
        }
    }

    private var assetListView: some View {
        List(filteredAssets, selection: $selectedAsset) { asset in
            AssetListRow(asset: asset, onInsert: onInsert)
                .onDrag {
                    assetDragItemProvider(for: asset)
                }
                .task {
                    if !asset.isMetadataLoaded {
                        await AssetService.shared.loadAssetMetadata(asset)
                    }
                }
        }
    }

    // MARK: - Data Loading

    private func loadAssets() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Scan only the specific folder that was selected
            assets = try await AssetService.shared.scanAssets(in: folderURL, isAssetsDir: isAssetsDir)

            // Start loading metadata for visible assets
            // The rest will be loaded lazily as they scroll into view
            let initialBatch = Array(assets.prefix(20))
            await AssetService.shared.loadMetadataForAssets(initialBatch)
        } catch {
            print("Failed to load assets: \(error)")
            assets = []
        }
    }

    // MARK: - Drag Out

    /// Build the drag payload for an asset: the file itself (so dropping on Finder or
    /// another app performs a real file copy - `NSItemProvider(contentsOf:)` is what
    /// registers the file-promise/`public.file-url` representation Finder accepts for
    /// a copy) plus the existing markdown-syntax string representation, so dropping
    /// back into Victor's own editor still inserts `![alt](path)` exactly as before
    /// (EditorTextView's `performDragOperation` reads the `NSString` representation
    /// first). `.draggable(asset.url)` was considered but its `Transferable`
    /// conformance for `URL` also exports a plain `absoluteString` representation,
    /// which would have replaced the markdown-insert behavior with a raw `file://` path.
    private func assetDragItemProvider(for asset: Asset) -> NSItemProvider {
        let provider = NSItemProvider(contentsOf: asset.url) ?? NSItemProvider()
        provider.registerObject(asset.markdownSyntax as NSString, visibility: .all)
        return provider
    }
}

// MARK: - Grid Item

struct AssetGridItem: View {
    let asset: Asset
    let isSelected: Bool
    let onInsert: ((String) -> Void)?

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            // Thumbnail or icon
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail = asset.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: asset.fileType.systemImage)
                            .font(.system(size: 32))
                            .foregroundStyle(asset.fileType.defaultColor)
                    }
                }
                .frame(width: 100, height: 80)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)

                // Drag hint indicator on hover
                if isHovered {
                    Image(systemName: "hand.draw")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Color.accentColor.opacity(0.8))
                        .cornerRadius(4)
                        .offset(x: 4, y: -4)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isHovered)

            // Filename
            Text(asset.url.lastPathComponent)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 100)

            // Location badge
            Text(asset.isInAssetsDir ? "assets" : "static")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.2))
                .cornerRadius(4)
        }
        .padding(8)
        .background(backgroundColor)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .help("Drag to insert into editor")
        .contextMenu {
            AssetContextMenu(asset: asset, onInsert: onInsert)
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.2)
        } else if isHovered {
            return Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
        }
        return Color.clear
    }
}

// MARK: - List Row

struct AssetListRow: View {
    let asset: Asset
    let onInsert: ((String) -> Void)?

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail or icon
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let thumbnail = asset.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: asset.fileType.systemImage)
                            .font(.title2)
                            .foregroundStyle(asset.fileType.defaultColor)
                    }
                }
                .frame(width: 40, height: 40)

                // Drag hint indicator on hover
                if isHovered {
                    Image(systemName: "hand.draw")
                        .font(.system(size: 8))
                        .foregroundStyle(.white)
                        .padding(2)
                        .background(Color.accentColor.opacity(0.8))
                        .cornerRadius(3)
                        .offset(x: 2, y: 2)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isHovered)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.url.lastPathComponent)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let size = asset.fileSize {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    }
                    if let dims = asset.formattedDimensions {
                        Text("•")
                        Text(dims)
                    }
                    Text("•")
                    Text(asset.isInAssetsDir ? "assets/" : "static/")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // File type badge
            Text(asset.fileType.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.2))
                .cornerRadius(4)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(isHovered ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : Color.clear)
        .cornerRadius(4)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("Drag to insert into editor")
        .contextMenu {
            AssetContextMenu(asset: asset, onInsert: onInsert)
        }
    }
}

// MARK: - Context Menu

struct AssetContextMenu: View {
    let asset: Asset
    let onInsert: ((String) -> Void)?

    var body: some View {
        // Insert options (only if callback is provided)
        if let onInsert = onInsert {
            if asset.fileType == .image {
                Button {
                    onInsert(asset.markdownSyntax)
                } label: {
                    Label("Insert Markdown Image", systemImage: "photo")
                }

                Button {
                    onInsert(asset.figureShortcode)
                } label: {
                    Label("Insert Figure Shortcode", systemImage: "text.below.photo")
                }

                Divider()
            }
        }

        // Copy options
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(asset.relativePath, forType: .string)
        } label: {
            Label("Copy Relative Path", systemImage: "doc.on.clipboard")
        }

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(asset.url.path, forType: .string)
        } label: {
            Label("Copy Full Path", systemImage: "doc.on.clipboard.fill")
        }

        if asset.fileType == .image {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(asset.markdownSyntax, forType: .string)
            } label: {
                Label("Copy Markdown Syntax", systemImage: "curlybraces")
            }
        }

        Divider()

        // File operations
        Button {
            NSWorkspace.shared.selectFile(asset.url.path, inFileViewerRootedAtPath: asset.url.deletingLastPathComponent().path)
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }

        Button {
            NSWorkspace.shared.open(asset.url)
        } label: {
            Label("Open in Default App", systemImage: "arrow.up.forward.app")
        }
    }
}
