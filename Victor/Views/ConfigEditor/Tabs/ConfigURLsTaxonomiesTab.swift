import SwiftUI

/// URLs & Taxonomies tab for Hugo configuration editor (CONFIG-SCHEMA-SPEC
/// §3.3, Phase 5) — renamed/reorganized from the former "Taxonomies" tab.
///
/// Contents, in order: the bespoke taxonomies pair editor (unchanged), the
/// Permalinks section (moved wholesale from `ConfigContentTab` — same
/// `PermalinkRowView`/`InsertTokenMenuButton` types, just relocated), then
/// pagination/URL-handling/section fields wired through `ConfigFieldView`.
/// `enableRobotsTXT` moved here from Content per §3.3's field placement.
struct ConfigURLsTaxonomiesTab: View {
    @Bindable var config: HugoConfig
    @State private var newSingular = ""
    @State private var newPlural = ""

    /// No validator among the `ConfigFieldView`-rendered fields here needs
    /// `siteURL`.
    private var validationContext: ValidationContext {
        ValidationContext(siteURL: nil, store: config.store)
    }

    var body: some View {
        Form {
            taxonomiesSection
            PermalinksSectionView(config: config)
            paginationSection
            urlHandlingSection
            sectionsSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Taxonomies (bespoke, unchanged)

    private var taxonomiesSection: some View {
        Section {
            ForEach(Array(config.taxonomies.keys.sorted()), id: \.self) { singular in
                HStack {
                    Text(singular)
                        .fontWeight(.medium)
                        .frame(width: 120, alignment: .trailing)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .accessibilityHidden(true)
                    Text(config.taxonomies[singular] ?? "")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        config.taxonomies.removeValue(forKey: singular)
                        config.syncRawContentFromStructuredData()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove Taxonomy \(singular)")
                }
            }

            HStack {
                TextField("singular", text: $newSingular)
                    .frame(width: 120)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .accessibilityHidden(true)
                TextField("plural", text: $newPlural)
                    .frame(width: 120)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                Button("Add") {
                    if !newSingular.isEmpty && !newPlural.isEmpty {
                        config.taxonomies[newSingular] = newPlural
                        config.syncRawContentFromStructuredData()
                        newSingular = ""
                        newPlural = ""
                    }
                }
                .disabled(newSingular.isEmpty || newPlural.isEmpty)
            }
        } header: {
            Text("Taxonomies")
        } footer: {
            Text("Define custom taxonomies for organizing content. The singular form is used in URLs, the plural in section names.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Pagination

    private var paginationSection: some View {
        Section("Pagination") {
            ConfigFieldView(spec: ConfigSchema.spec(for: "pagination.pagerSize")!, store: config.store, context: validationContext)
            ConfigFieldView(spec: ConfigSchema.spec(for: "pagination.path")!, store: config.store, context: validationContext)
            ConfigFieldView(spec: ConfigSchema.spec(for: "pagination.disableAliases")!, store: config.store, context: validationContext)
        }
    }

    // MARK: - URL Handling

    private var urlHandlingSection: some View {
        Section("URL Handling") {
            ConfigFieldView(spec: ConfigSchema.spec(for: "canonifyURLs")!, store: config.store, context: validationContext)
            ConfigFieldView(spec: ConfigSchema.spec(for: "relativeURLs")!, store: config.store, context: validationContext)
            ConfigFieldView(spec: ConfigSchema.spec(for: "uglyURLs")!, store: config.store, context: validationContext)
            ConfigFieldView(spec: ConfigSchema.spec(for: "disablePathToLower")!, store: config.store, context: validationContext)
            ConfigFieldView(spec: ConfigSchema.spec(for: "removePathAccents")!, store: config.store, context: validationContext)
            ConfigFieldView(spec: ConfigSchema.spec(for: "disableAliases")!, store: config.store, context: validationContext)
        }
    }

    // MARK: - Sections

    private var sectionsSection: some View {
        Section("Sections") {
            ConfigFieldView(spec: ConfigSchema.spec(for: "sectionPagesMenu")!, store: config.store, context: validationContext)
            ConfigFieldView(spec: ConfigSchema.spec(for: "enableRobotsTXT")!, store: config.store, context: validationContext)
        }
    }

    /// Every key this tab renders — `taxonomies` via its bespoke editor,
    /// `permalinks` via the section below (no schema entry of its own, see
    /// `ConfigSchema`'s note), everything else via `ConfigFieldView`. Feeds
    /// `ConfigAdvancedTab`'s `renderedOnOtherTabs` exclusion set, mirroring
    /// `ConfigMarkupTab.allRenderedKeys`.
    static var allRenderedKeys: Set<String> = [
        "taxonomies",
        "pagination.pagerSize", "pagination.path", "pagination.disableAliases",
        "canonifyURLs", "relativeURLs", "uglyURLs",
        "disablePathToLower", "removePathAccents", "disableAliases",
        "sectionPagesMenu", "enableRobotsTXT"
    ]
}

// MARK: - Permalinks Section (moved wholesale from ConfigContentTab, §3.3)

private struct PermalinksSectionView: View {
    @Bindable var config: HugoConfig
    @State private var newSection = ""
    @State private var newPattern = "/:year/:month/:title/"

    var body: some View {
        Section {
            // Existing entries
            ForEach(Array(config.permalinks.keys.sorted()), id: \.self) { section in
                PermalinkRowView(
                    section: section,
                    pattern: Binding(
                        get: { config.permalinks[section] ?? "" },
                        set: { newValue in
                            config.permalinks[section] = newValue
                            config.syncRawContentFromStructuredData()
                        }
                    ),
                    onDelete: {
                        config.permalinks.removeValue(forKey: section)
                        config.syncRawContentFromStructuredData()
                    }
                )
            }

            // Add new entry
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    TextField("section", text: $newSection)
                        .frame(width: 120)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor))
                        .help("Content section name (e.g. posts, blog, articles)")

                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .accessibilityHidden(true)

                    TextField("/:year/:month/:title/", text: $newPattern)
                        .font(.system(.body, design: .monospaced))
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor))
                        .help("Permalink pattern with :tokens")

                    InsertTokenMenuButton { token in
                        newPattern = insertToken(token, into: newPattern)
                    }

                    Button("Add") {
                        let trimmedSection = newSection
                            .trimmingCharacters(in: .whitespaces)
                            .lowercased()
                        let trimmedPattern = newPattern.trimmingCharacters(in: .whitespaces)
                        config.permalinks[trimmedSection] = trimmedPattern
                        config.syncRawContentFromStructuredData()
                        newSection = ""
                        newPattern = "/:year/:month/:title/"
                    }
                    .disabled(!canAdd)
                }

                // Validation messages for the "add" row
                if let sectionError = sectionValidationError {
                    Label(sectionError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.Status.warning)
                }
                if let patternError = patternValidationError {
                    Label(patternError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.Status.warning)
                }
            }
        } header: {
            Text("Permalinks")
        } footer: {
            Text("URL patterns for content sections. Use tokens like :year, :month, :title to build dynamic URLs.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sectionValidationError: String? {
        guard !newSection.isEmpty else { return nil }
        if let error = PermalinkResolver.validateSectionName(newSection) {
            return error
        }
        if config.permalinks.keys.contains(newSection.lowercased()) {
            return "Section '\(newSection)' already has a pattern"
        }
        return nil
    }

    private var patternValidationError: String? {
        guard !newPattern.isEmpty else { return nil }
        return PermalinkResolver.validate(pattern: newPattern)
    }

    private var canAdd: Bool {
        let trimmed = newSection.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !newPattern.isEmpty else { return false }
        guard PermalinkResolver.validateSectionName(trimmed) == nil else { return false }
        guard PermalinkResolver.validate(pattern: newPattern) == nil else { return false }
        guard !config.permalinks.keys.contains(trimmed.lowercased()) else { return false }
        return true
    }

    private func insertToken(_ token: String, into pattern: String) -> String {
        // Insert before trailing slash if present, otherwise append
        if pattern.hasSuffix("/") {
            return String(pattern.dropLast()) + "/\(token)/"
        }
        return pattern + "/\(token)"
    }
}

// MARK: - Permalink Row (existing entry)

private struct PermalinkRowView: View {
    let section: String
    @Binding var pattern: String
    let onDelete: () -> Void

    @State private var editingPattern: String = ""
    @FocusState private var isFocused: Bool

    private var validationError: String? {
        PermalinkResolver.validate(pattern: editingPattern)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(section)
                    .fontWeight(.medium)
                    .frame(width: 120, alignment: .trailing)

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                TextField("pattern", text: $editingPattern)
                    .font(.system(.body, design: .monospaced))
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(validationError != nil ? .orange : .clear, lineWidth: 1)
                    )
                    .focused($isFocused)
                    .onSubmit { commitEdit() }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commitEdit() }
                    }

                InsertTokenMenuButton { token in
                    editingPattern = insertToken(token, into: editingPattern)
                    commitEdit()
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove permalink pattern for \(section)")
                .accessibilityLabel("Remove Permalink Pattern for \(section)")
            }

            if let error = validationError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.Status.warning)
                    .padding(.leading, 136) // Align under the pattern field
            }
        }
        .onAppear {
            editingPattern = pattern
        }
        .onChange(of: pattern) { _, newValue in
            // Sync if external change (e.g. undo)
            if editingPattern != newValue && !isFocused {
                editingPattern = newValue
            }
        }
    }

    private func commitEdit() {
        let trimmed = editingPattern.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if trimmed != pattern {
            pattern = trimmed
        }
    }

    private func insertToken(_ token: String, into text: String) -> String {
        if text.hasSuffix("/") {
            return String(text.dropLast()) + "/\(token)/"
        }
        return text + "/\(token)"
    }
}

// MARK: - Token Insertion Menu

private struct InsertTokenMenuButton: View {
    let onInsert: (String) -> Void

    var body: some View {
        Menu {
            Section("Date Tokens") {
                ForEach(PermalinkResolver.insertableTokens.filter { isDateToken($0.token) }) { info in
                    tokenButton(info)
                }
            }
            Section("Content Tokens") {
                ForEach(PermalinkResolver.insertableTokens.filter { !isDateToken($0.token) }) { info in
                    tokenButton(info)
                }
            }
        } label: {
            Image(systemName: "plus.circle")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 24)
        .accessibilityLabel("Insert Permalink Token")
        .help("Insert a permalink token")
    }

    @ViewBuilder
    private func tokenButton(_ info: PermalinkResolver.TokenInfo) -> some View {
        Button {
            onInsert(info.token)
        } label: {
            HStack {
                Text(info.token)
                    .font(.system(.body, design: .monospaced))
                Text("— \(info.description)")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(info.example)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func isDateToken(_ token: String) -> Bool {
        [":year", ":month", ":day", ":yearday", ":monthname", ":weekday", ":weekdayname"].contains(token)
    }
}
