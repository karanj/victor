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
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Site Open")
                .font(.headline)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    await siteViewModel.openSiteFolder()
                }
            } label: {
                Text("Open Hugo Site")
                    .frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
