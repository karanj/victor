import SwiftUI
import UniformTypeIdentifiers

/// Main view for browsing and managing assets
struct AssetBrowserView: View {
    let folderURL: URL           // The specific folder being browsed (static/ or assets/)
    let isAssetsDir: Bool        // true = assets/, false = static/
    let onInsert: ((String) -> Void)?  // Callback when inserting into markdown

    @State private var assets: [Asset] = []
    @State private var isLoading = true
    @State private var selectedAsset: Asset?
    @State private var viewMode: AssetViewMode = .grid
    @State private var filterType: AssetFilterType = .all
    @State private var searchText = ""
    @State private var sortOrder: AssetSortOrder = .name

    var filteredAssets: [Asset] {
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

        return result
    }

    var body: some View {
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
                }
            }

            // Asset detail panel
            if let asset = selectedAsset {
                AssetDetailPanel(asset: asset, onInsert: onInsert)
                    .frame(minWidth: 250, maxWidth: 300)
            }
        }
        .task {
            await loadAssets()
        }
    }

    // MARK: - Toolbar

    private var assetToolbar: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                    .foregroundStyle(.blue)
                Text(isAssetsDir ? "assets/" : "static/")
                    .font(.headline)

                Text("\(filteredAssets.count) of \(assets.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Refresh button
                Button {
                    Task { await loadAssets() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh assets")
            }

            HStack {
                // Filter
                Picker("Filter", selection: $filterType) {
                    ForEach(AssetFilterType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                Spacer()

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
                        Image(systemName: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 100)

                Divider().frame(height: 20)

                // Search
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading assets...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No assets found")
                .font(.headline)
            Text("Add files to this directory")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                // Reveal folder in Finder
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
            } label: {
                Label("Open in Finder", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No matching assets")
                .font(.headline)
            Text("Try adjusting your search or filter")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Clear filters") {
                searchText = ""
                filterType = .all
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    AssetGridItem(asset: asset, isSelected: asset == selectedAsset)
                        .onTapGesture {
                            selectedAsset = asset
                        }
                        .onDrag {
                            NSItemProvider(object: asset.markdownSyntax as NSString)
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
            AssetListRow(asset: asset)
                .onDrag {
                    NSItemProvider(object: asset.markdownSyntax as NSString)
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
}

// MARK: - Grid Item

struct AssetGridItem: View {
    let asset: Asset
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Thumbnail or icon
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
            .cornerRadius(8)

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
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - List Row

struct AssetListRow: View {
    let asset: Asset

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail or icon
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
    }
}
