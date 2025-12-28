import SwiftUI

/// Quick Open overlay for fuzzy file search (Cmd+P)
struct QuickOpenView: View {
    @Bindable var siteViewModel: SiteViewModel
    @Binding var isPresented: Bool

    @State private var searchQuery = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFieldFocused: Bool

    /// Filtered results based on search query
    private var searchResults: [FuzzyMatchResult] {
        guard !searchQuery.isEmpty else {
            return []
        }
        return FuzzyMatcher.match(query: searchQuery, in: siteViewModel.fileNodes, limit: 15)
    }

    /// Recent files to show when search is empty
    private var recentFiles: [FileNode] {
        siteViewModel.recentFiles.prefix(8).compactMap { $0 }
    }

    /// Items to display (search results or recent files)
    private var displayItems: [QuickOpenItem] {
        if searchQuery.isEmpty {
            return recentFiles.map { QuickOpenItem.recent($0) }
        } else {
            return searchResults.map { QuickOpenItem.searchResult($0) }
        }
    }

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            // Quick Open panel
            VStack(spacing: 0) {
                // Search field
                searchFieldView

                Divider()

                // Results list
                if displayItems.isEmpty {
                    emptyStateView
                } else {
                    resultsListView
                }
            }
            .frame(width: 500)
            .frame(maxHeight: 400)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            .padding(.top, 80) // Position near top of window
        }
        .onAppear {
            isSearchFieldFocused = true
            selectedIndex = 0
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.return) {
            selectCurrentItem()
            return .handled
        }
    }

    // MARK: - Subviews

    private var searchFieldView: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search files...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isSearchFieldFocused)
                .onChange(of: searchQuery) { _, _ in
                    // Reset selection when query changes
                    selectedIndex = 0
                }

            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var resultsListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                        QuickOpenResultRow(
                            item: item,
                            isSelected: index == selectedIndex,
                            contentDirectory: siteViewModel.site?.contentDirectory
                        )
                        .id(index)
                        .onTapGesture {
                            selectedIndex = index
                            selectCurrentItem()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: selectedIndex) { _, newIndex in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            if searchQuery.isEmpty {
                Text("Type to search files")
                    .foregroundStyle(.secondary)
                Text("Recent files will appear here")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("No matching files")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Actions

    private func dismiss() {
        isPresented = false
        searchQuery = ""
    }

    private func moveSelection(by offset: Int) {
        let newIndex = selectedIndex + offset
        if newIndex >= 0 && newIndex < displayItems.count {
            selectedIndex = newIndex
        }
    }

    private func selectCurrentItem() {
        guard selectedIndex < displayItems.count else { return }

        let item = displayItems[selectedIndex]
        let node: FileNode

        switch item {
        case .searchResult(let result):
            node = result.node
        case .recent(let fileNode):
            node = fileNode
        }

        // Add to recent files
        siteViewModel.addRecentFile(node)

        // Select the file
        siteViewModel.selectNode(node)

        // Close the dialog
        dismiss()
    }
}

// MARK: - Quick Open Item

/// Represents an item in the quick open list
enum QuickOpenItem: Identifiable {
    case searchResult(FuzzyMatchResult)
    case recent(FileNode)

    var id: String {
        switch self {
        case .searchResult(let result):
            return "search-\(result.node.id)"
        case .recent(let node):
            return "recent-\(node.id)"
        }
    }
}

// MARK: - Result Row

/// Individual row in the quick open results list
struct QuickOpenResultRow: View {
    let item: QuickOpenItem
    let isSelected: Bool
    let contentDirectory: URL?

    private var node: FileNode {
        switch item {
        case .searchResult(let result):
            return result.node
        case .recent(let fileNode):
            return fileNode
        }
    }

    private var isRecent: Bool {
        if case .recent = item { return true }
        return false
    }

    /// Path relative to content directory
    private var relativePath: String {
        guard let contentDir = contentDirectory else {
            return node.url.path
        }

        let fullPath = node.url.path
        let contentPath = contentDir.path

        if fullPath.hasPrefix(contentPath) {
            var relative = String(fullPath.dropFirst(contentPath.count))
            if relative.hasPrefix("/") {
                relative = String(relative.dropFirst())
            }
            return relative
        }

        return fullPath
    }

    var body: some View {
        HStack(spacing: 10) {
            // File icon
            Image(systemName: "doc.text.fill")
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 20)

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .primary)

                Text(relativePath)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Recent indicator
            if isRecent {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary.opacity(0.6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    QuickOpenView(
        siteViewModel: SiteViewModel(),
        isPresented: .constant(true)
    )
}
