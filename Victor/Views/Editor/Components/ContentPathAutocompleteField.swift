import SwiftUI

// MARK: - Content Path Autocomplete Field

/// A text field with inline autocomplete dropdown for content file paths
struct ContentPathAutocompleteField: View {
    let parameter: ShortcodeParameter
    @Binding var value: String
    let suggestions: [ContentPathSuggestion]

    @State private var showSuggestions = false
    @State private var selectedIndex = 0
    @State private var currentFilteredSuggestions: [ContentPathSuggestion] = []
    @FocusState private var isFocused: Bool

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Text field with validation indicator
            HStack(spacing: 8) {
                TextField(parameter.placeholder, text: $value)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onChange(of: value) { _, newValue in
                        // Dispatch async to avoid layout recursion
                        DispatchQueue.main.async {
                            updateFilteredSuggestions(for: newValue)
                        }
                    }
                    .onChange(of: isFocused) { _, focused in
                        // Dispatch async to avoid layout recursion
                        DispatchQueue.main.async {
                            if focused {
                                updateFilteredSuggestions(for: value)
                                showSuggestions = !currentFilteredSuggestions.isEmpty
                            } else {
                                // Delay hiding to allow click on suggestion
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    if !isFocused {
                                        showSuggestions = false
                                    }
                                }
                            }
                        }
                    }
                    .onKeyPress(.downArrow) {
                        if !showSuggestions && !currentFilteredSuggestions.isEmpty {
                            showSuggestions = true
                            return .handled
                        }
                        if showSuggestions && !currentFilteredSuggestions.isEmpty {
                            selectedIndex = min(selectedIndex + 1, min(currentFilteredSuggestions.count, 10) - 1)
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.upArrow) {
                        if showSuggestions && !currentFilteredSuggestions.isEmpty {
                            selectedIndex = max(selectedIndex - 1, 0)
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.return) {
                        if showSuggestions && !currentFilteredSuggestions.isEmpty && selectedIndex < currentFilteredSuggestions.count {
                            selectSuggestion(currentFilteredSuggestions[selectedIndex])
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.escape) {
                        if showSuggestions {
                            showSuggestions = false
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.tab) {
                        if showSuggestions && !currentFilteredSuggestions.isEmpty && selectedIndex < currentFilteredSuggestions.count {
                            selectSuggestion(currentFilteredSuggestions[selectedIndex])
                            return .handled
                        }
                        return .ignored
                    }

                // Validation indicator
                validationIndicator
            }

            // Suggestions dropdown - use id to force re-render when filter changes
            if showSuggestions && !currentFilteredSuggestions.isEmpty {
                SuggestionsDropdownView(
                    suggestions: Array(currentFilteredSuggestions.prefix(10)),
                    selectedIndex: selectedIndex,
                    onSelect: { selectSuggestion($0) }
                )
                .padding(.top, 4)
                .id(currentFilteredSuggestions.map { $0.path }.joined())
            }
        }
        .onAppear {
            currentFilteredSuggestions = suggestions
        }
    }

    // MARK: - Validation Indicator

    @ViewBuilder
    private var validationIndicator: some View {
        if !value.isEmpty {
            let isValid = suggestions.contains { $0.path == value }
            if isValid {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("Path exists in content/")
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Path not found in content/ directory")
            }
        }
    }

    // MARK: - Actions

    private func updateFilteredSuggestions(for query: String) {
        if query.isEmpty {
            currentFilteredSuggestions = suggestions
        } else {
            currentFilteredSuggestions = suggestions.filter {
                $0.path.localizedCaseInsensitiveContains(query) ||
                $0.displayName.localizedCaseInsensitiveContains(query)
            }
        }
        selectedIndex = 0
        showSuggestions = isFocused && !currentFilteredSuggestions.isEmpty
    }

    private func selectSuggestion(_ suggestion: ContentPathSuggestion) {
        value = suggestion.path
        showSuggestions = false
    }
}

// MARK: - Suggestions Dropdown View

private struct SuggestionsDropdownView: View {
    let suggestions: [ContentPathSuggestion]
    let selectedIndex: Int
    let onSelect: (ContentPathSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.path) { index, suggestion in
                SuggestionRow(
                    suggestion: suggestion,
                    isSelected: index == selectedIndex,
                    onSelect: { onSelect(suggestion) }
                )
            }
        }
        .frame(maxHeight: 250)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}

// MARK: - Suggestion Row

private struct SuggestionRow: View {
    let suggestion: ContentPathSuggestion
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.displayName)
                        .font(.callout)
                        .fontWeight(.medium)

                    if suggestion.path != suggestion.displayName {
                        Text(suggestion.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        ContentPathAutocompleteField(
            parameter: ShortcodeParameter(
                name: "path",
                type: .contentPath,
                isRequired: true,
                placeholder: "posts/my-post.md",
                helpText: "Path to target page"
            ),
            value: .constant(""),
            suggestions: [
                ContentPathSuggestion(path: "posts/hello-world.md", displayName: "hello-world.md"),
                ContentPathSuggestion(path: "posts/getting-started.md", displayName: "getting-started.md"),
                ContentPathSuggestion(path: "about.md", displayName: "about.md"),
                ContentPathSuggestion(path: "contact/index.md", displayName: "index.md"),
            ]
        )
    }
    .padding()
    .frame(width: 400)
}
