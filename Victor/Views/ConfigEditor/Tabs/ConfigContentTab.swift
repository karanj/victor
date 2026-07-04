import SwiftUI

/// Content tab for Hugo configuration editor
/// Handles build options, permalinks, and output settings
struct ConfigContentTab: View {
    @Bindable var config: HugoConfig

    var body: some View {
        Form {
            Section("Build Options") {
                Toggle("Build Drafts", isOn: $config.buildDrafts)
                    .toggleStyle(.checkbox)
                    .help("Include draft content in builds")
                    .onChange(of: config.buildDrafts) { _, _ in
                        config.syncRawContentFromStructuredData()
                    }

                Toggle("Build Future", isOn: $config.buildFuture)
                    .toggleStyle(.checkbox)
                    .help("Include future-dated content in builds")
                    .onChange(of: config.buildFuture) { _, _ in
                        config.syncRawContentFromStructuredData()
                    }

                Toggle("Build Expired", isOn: $config.buildExpired)
                    .toggleStyle(.checkbox)
                    .help("Include expired content in builds")
                    .onChange(of: config.buildExpired) { _, _ in
                        config.syncRawContentFromStructuredData()
                    }
            }

            PermalinksSectionView(config: config)

            Section("Output") {
                Toggle("Enable robots.txt", isOn: $config.enableRobotsTXT)
                    .toggleStyle(.checkbox)
                    .help("Generate robots.txt file")
                    .onChange(of: config.enableRobotsTXT) { _, _ in
                        config.syncRawContentFromStructuredData()
                    }

                LabeledContent("Summary Length") {
                    Stepper("\(config.summaryLength) words",
                            value: $config.summaryLength, in: 10...500, step: 10)
                        .onChange(of: config.summaryLength) { _, _ in
                            config.syncRawContentFromStructuredData()
                        }
                }
                .help("Default length for auto-generated summaries")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Permalinks Section

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
                ForEach(PermalinkResolver.validTokens.filter { isDateToken($0.token) }) { info in
                    tokenButton(info)
                }
            }
            Section("Content Tokens") {
                ForEach(PermalinkResolver.validTokens.filter { !isDateToken($0.token) }) { info in
                    tokenButton(info)
                }
            }
        } label: {
            Image(systemName: "plus.circle")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 24)
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
