import SwiftUI

struct SidebarView: View {
    @Bindable var siteViewModel: SiteViewModel

    var body: some View {
        VStack(spacing: 0) {
            if siteViewModel.site == nil {
                // Empty state - centered prompt to open a site
                EmptySiteView(siteViewModel: siteViewModel)
            } else {
                // Site header
                SiteHeader(siteViewModel: siteViewModel)

                Divider()

                // Search bar
                SearchBar(searchText: $siteViewModel.searchQuery, siteViewModel: siteViewModel)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                Divider()

                // File list
                if siteViewModel.isLoading {
                    LoadingView()
                } else {
                    FileListView(siteViewModel: siteViewModel)
                }
            }
        }
    }
}

// MARK: - Empty Site View

struct EmptySiteView: View {
    let siteViewModel: SiteViewModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Icon
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)

            // Title and description
            VStack(spacing: 6) {
                Text("Open a Hugo Site")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Select a folder containing your Hugo site")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Open button
            Button {
                Task {
                    await siteViewModel.openSiteFolder()
                }
            } label: {
                Label("Open Folder", systemImage: "folder")
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // Keyboard shortcut hint
            Text("⌘O")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, -8)

            // Recent sites section
            if !siteViewModel.recentSitePaths.isEmpty {
                Divider()
                    .padding(.vertical, 8)

                RecentSitesSection(siteViewModel: siteViewModel)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Recent Sites Section

struct RecentSitesSection: View {
    let siteViewModel: SiteViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Sites")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 4) {
                ForEach(siteViewModel.recentSitePaths, id: \.self) { path in
                    RecentSiteRow(path: path, siteViewModel: siteViewModel)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Recent Site Row

struct RecentSiteRow: View {
    let path: String
    let siteViewModel: SiteViewModel

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Extract site name from path
    private var siteName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    /// Shorten path for display
    private var displayPath: String {
        let url = URL(fileURLWithPath: path)
        let components = url.pathComponents
        if components.count > 3 {
            return "~/" + components.suffix(2).joined(separator: "/")
        }
        return path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    var body: some View {
        Button {
            Task {
                await siteViewModel.openRecentSite(path)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(siteName)
                        .font(.callout)
                        .lineLimit(1)

                    Text(displayPath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isHovering {
                    Image(systemName: "arrow.right.circle")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isHovering ? Color(nsColor: .controlBackgroundColor) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
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

                Text("\(siteViewModel.totalFileCount) files")
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
                .onKeyPress(.escape) {
                    searchText = ""
                    return .handled
                }

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
