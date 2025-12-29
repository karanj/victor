import SwiftUI

// MARK: - Shortcode Picker View

/// Main view for selecting and configuring Hugo shortcodes
struct ShortcodePickerView: View {
    let onInsert: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedCategory: ShortcodeCategory? = .media
    @State private var selectedShortcode: HugoShortcode?

    var body: some View {
        NavigationSplitView {
            // Category sidebar
            List(selection: $selectedCategory) {
                Section("Categories") {
                    ForEach(ShortcodeCategory.allCases, id: \.self) { category in
                        Label(category.rawValue, systemImage: category.icon)
                            .tag(category)
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 150)
        } content: {
            // Shortcode list
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search shortcodes...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                List(selection: $selectedShortcode) {
                    ForEach(filteredShortcodes) { shortcode in
                        ShortcodeCardView(shortcode: shortcode)
                            .tag(shortcode)
                    }
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 250)
        } detail: {
            // Shortcode form
            if let shortcode = selectedShortcode {
                ShortcodeFormView(
                    shortcode: shortcode,
                    onInsert: { text in
                        onInsert(text)
                        dismiss()
                    },
                    onCancel: { dismiss() }
                )
            } else {
                ContentUnavailableView(
                    "Select a Shortcode",
                    systemImage: "curlybraces",
                    description: Text("Choose a shortcode from the list to configure and insert it.")
                )
            }
        }
        .frame(minWidth: AppConstants.Dialog.shortcodePickerWidth, minHeight: AppConstants.Dialog.shortcodePickerHeight)
        .navigationTitle("Insert Shortcode")
    }

    private var filteredShortcodes: [HugoShortcode] {
        let categoryShortcodes: [HugoShortcode]
        if let category = selectedCategory {
            categoryShortcodes = category.shortcodes
        } else {
            categoryShortcodes = HugoShortcode.allShortcodes
        }

        if searchText.isEmpty {
            return categoryShortcodes
        }

        return categoryShortcodes.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText) ||
            $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }
}

// MARK: - Preview

#Preview {
    ShortcodePickerView { shortcodeText in
        print("Insert: \(shortcodeText)")
    }
}
