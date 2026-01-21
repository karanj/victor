import SwiftUI

/// Global search and replace panel
struct GlobalSearchView: View {
    @Bindable var siteViewModel: SiteViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery = ""
    @State private var replaceQuery = ""
    @State private var isRegex = false
    @State private var isCaseSensitive = false
    @State private var scope: SearchScope = .allFiles
    @State private var isSearching = false
    @State private var results = GlobalSearchResults()
    @State private var selectedMatch: (FileSearchResult, SearchMatch)?
    @State private var showReplaceField = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Search fields
            searchFields

            Divider()

            // Options bar
            optionsBar

            Divider()

            // Results
            if isSearching {
                loadingView
            } else if results.isEmpty && !searchQuery.isEmpty {
                emptyResultsView
            } else if !results.isEmpty {
                resultsView
            } else {
                placeholderView
            }
        }
        .frame(
            width: AppConstants.GlobalSearch.panelWidth,
            height: AppConstants.GlobalSearch.panelHeight
        )
        .onAppear {
            isSearchFieldFocused = true
        }
        .alert("Search Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Find in Files")
                .font(.headline)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    // MARK: - Search Fields

    private var searchFields: some View {
        VStack(spacing: 8) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .focused($isSearchFieldFocused)
                    .onSubmit {
                        performSearch()
                    }
                    .onChange(of: searchQuery) { _, newValue in
                        if newValue.count >= AppConstants.GlobalSearch.minQueryLength {
                            debounceSearch()
                        } else {
                            // Clear results for short queries
                            searchTask?.cancel()
                            results = GlobalSearchResults()
                        }
                    }

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        results = GlobalSearchResults()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    showReplaceField.toggle()
                } label: {
                    Image(systemName: showReplaceField ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(showReplaceField ? "Hide replace" : "Show replace")
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)

            // Replace field (collapsible)
            if showReplaceField {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundStyle(.secondary)

                    TextField("Replace", text: $replaceQuery)
                        .textFieldStyle(.plain)

                    if !replaceQuery.isEmpty {
                        Button {
                            replaceQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Replace All") {
                        performReplaceAll()
                    }
                    .disabled(results.isEmpty || replaceQuery.isEmpty)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Options Bar

    private var optionsBar: some View {
        HStack(spacing: 16) {
            // Scope picker
            HStack(spacing: 4) {
                Text("Scope:")
                    .foregroundStyle(.secondary)
                Picker("", selection: $scope) {
                    ForEach(SearchScope.allCases) { scopeOption in
                        Text(scopeOption.rawValue).tag(scopeOption)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
                .onChange(of: scope) { _, _ in
                    debounceSearch()
                }
            }

            Divider()
                .frame(height: 16)

            // Regex toggle
            Toggle("Regex", isOn: $isRegex)
                .toggleStyle(.checkbox)
                .onChange(of: isRegex) { _, _ in
                    debounceSearch()
                }

            // Case sensitive toggle
            Toggle("Match Case", isOn: $isCaseSensitive)
                .toggleStyle(.checkbox)
                .onChange(of: isCaseSensitive) { _, _ in
                    debounceSearch()
                }

            Spacer()

            // Results summary
            if !results.isEmpty {
                Text(results.summaryText)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: - Results View

    private var resultsView: some View {
        List(results.fileResults) { fileResult in
            DisclosureGroup(isExpanded: Binding(
                get: { fileResult.isExpanded },
                set: { _ in toggleFileExpanded(fileResult) }
            )) {
                ForEach(fileResult.matches) { match in
                    SearchMatchRow(match: match, searchQuery: searchQuery)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            jumpToMatch(fileResult: fileResult, match: match)
                        }
                }
            } label: {
                HStack {
                    Image(systemName: FileType(url: fileResult.fileURL).systemImage)
                        .foregroundStyle(FileType(url: fileResult.fileURL).defaultColor)

                    Text(fileResult.relativePath)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Text("\(fileResult.matchCount)")
                        .countBadgeStyle()
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - State Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Searching...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No results found")
                .font(.headline)
            Text("Try a different search term or scope")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholderView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Search across all files")
                .font(.headline)
            Text("Enter a search term to find matches in your Hugo site")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Actions

    private func debounceSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .seconds(AppConstants.GlobalSearch.debounceInterval))
            guard !Task.isCancelled else { return }
            await performSearchAsync()
        }
    }

    private func performSearch() {
        searchTask?.cancel()
        Task {
            await performSearchAsync()
        }
    }

    @MainActor
    private func performSearchAsync() async {
        guard !searchQuery.isEmpty else {
            results = GlobalSearchResults()
            return
        }

        guard let siteRootURL = siteViewModel.site?.rootURL else { return }

        isSearching = true

        let options = SearchOptions(
            query: searchQuery,
            replaceWith: replaceQuery,
            isRegex: isRegex,
            isCaseSensitive: isCaseSensitive,
            scope: scope
        )

        let fileResults = await SearchService.shared.search(
            options: options,
            in: siteViewModel.fileNodes,
            siteRootURL: siteRootURL
        )

        results = GlobalSearchResults(options: options)
        results.fileResults = fileResults

        isSearching = false
    }

    private func performReplaceAll() {
        Task {
            guard !results.isEmpty else { return }

            isSearching = true

            let options = SearchOptions(
                query: searchQuery,
                replaceWith: replaceQuery,
                isRegex: isRegex,
                isCaseSensitive: isCaseSensitive,
                scope: scope
            )

            do {
                let count = try await SearchService.shared.replaceAll(
                    in: results.fileResults,
                    options: options
                )

                Logger.shared.info("[GlobalSearch] Replaced \(count) matches")

                // Refresh search results
                await performSearchAsync()

                // Reload site to reflect changes
                await siteViewModel.reloadSite()

            } catch {
                errorMessage = error.localizedDescription
            }

            isSearching = false
        }
    }

    private func toggleFileExpanded(_ fileResult: FileSearchResult) {
        if let index = results.fileResults.firstIndex(where: { $0.id == fileResult.id }) {
            results.fileResults[index].isExpanded.toggle()
        }
    }

    private func jumpToMatch(fileResult: FileSearchResult, match: SearchMatch) {
        // Find the node for this file
        if let node = siteViewModel.findNode(url: fileResult.fileURL) {
            siteViewModel.selectNode(node)
            // TODO: Scroll to line number in editor
            dismiss()
        }
    }
}

// MARK: - Search Match Row

struct SearchMatchRow: View {
    let match: SearchMatch
    let searchQuery: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(match.lineNumber)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)

            // Line content with highlighted match
            lineContentView
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .padding(.leading, 8)
    }

    private var lineContentView: some View {
        // Use HStack for highlighted match since Text concatenation
        // doesn't support background modifier
        HStack(spacing: 0) {
            Text(match.textBeforeMatch)
                .foregroundStyle(.primary)
            Text(match.matchedText)
                .foregroundStyle(.white)
                .padding(.horizontal, 2)
                .background(Color.accentColor)
                .cornerRadius(2)
            Text(match.textAfterMatch)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Preview

#Preview {
    GlobalSearchView(siteViewModel: SiteViewModel())
}
