import SwiftUI

/// Main view for editing Hugo configuration
struct ConfigEditorView: View {
    @Bindable var config: HugoConfig
    let onSave: () async -> Void
    let onSaveRaw: () async -> Void

    @State private var selectedTab: ConfigTab = .essentials
    @State private var showRawEditor = false
    @State private var isSaving = false
    @State private var showSavedIndicator = false
    @State private var parseError: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum ConfigTab: String, CaseIterable {
        case essentials = "Essentials"
        case content = "Content"
        case taxonomies = "Taxonomies"
        case advanced = "Advanced"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            configToolbar

            Divider()

            if showRawEditor {
                // Raw editor mode
                ConfigRawEditorView(config: config)
            } else {
                // Form editor mode
                TabView(selection: $selectedTab) {
                    ConfigEssentialsTab(config: config)
                        .tabItem { Label("Essentials", systemImage: "star") }
                        .tag(ConfigTab.essentials)

                    ConfigContentTab(config: config)
                        .tabItem { Label("Content", systemImage: "doc.text") }
                        .tag(ConfigTab.content)

                    ConfigTaxonomiesTab(config: config)
                        .tabItem { Label("Taxonomies", systemImage: "tag") }
                        .tag(ConfigTab.taxonomies)

                    ConfigAdvancedTab(config: config)
                        .tabItem { Label("Advanced", systemImage: "gearshape.2") }
                        .tag(ConfigTab.advanced)
                }
                .padding()
            }
        }
        .onChange(of: showRawEditor) { oldValue, newValue in
            if oldValue == false && newValue == true {
                FormRawToggleHandler.handleFormToRaw(
                    serializeToRaw: {
                        let serialized = try HugoConfigParser.shared.serialize(config)
                        config.rawContent = serialized
                        print("[ConfigEditorView] Form→Raw: serialized \(serialized.count) chars")
                    },
                    parseError: &parseError
                )
            } else if oldValue == true && newValue == false {
                FormRawToggleHandler.handleRawToForm(
                    parseFromRaw: {
                        try config.updateFromRawContent()
                    },
                    parseError: &parseError
                )
            }
        }
        .parseErrorAlert($parseError)
    }

    private var configToolbar: some View {
        HStack {
            // Config file icon
            Image(systemName: "gearshape.fill")
                .foregroundStyle(Color.FileIcon.config)
                .accessibilityHidden(true)

            // File name
            if let url = config.sourceURL {
                Text(url.lastPathComponent)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            } else {
                Text("Hugo Configuration")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }

            // Format badge
            Text(config.sourceFormat.rawValue.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.2))
                .cornerRadius(4)

            // File status badges
            FileStatusBadgeView(
                hasUnsavedChanges: config.hasUnsavedChanges,
                showSavedIndicator: showSavedIndicator
            )

            Spacer()

            // Toggle between form and raw
            FormRawPickerView(showRawEditor: $showRawEditor)

            EditorToolbarDivider()

            EditorSaveButton(
                isSaving: isSaving,
                hasUnsavedChanges: config.hasUnsavedChanges,
                action: save
            )

            // Open in external editor
            if let url = config.sourceURL {
                EditorOpenExternalButton(url: url)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(reduceMotion ? nil : .easeInOut(duration: AppConstants.Animation.fast), value: config.hasUnsavedChanges)
        .animation(reduceMotion ? nil : .easeInOut(duration: AppConstants.Animation.fast), value: showSavedIndicator)
    }

    // MARK: - Actions

    private func save() async {
        let helper = EditorSaveHelper()
        var errorMessage: String?
        await helper.performSave(
            operation: {
                if showRawEditor {
                    // In raw mode, save rawContent directly (bypass serialize)
                    await onSaveRaw()
                } else {
                    // In form mode, serialize from structured fields
                    await onSave()
                }
            },
            isSaving: { isSaving },
            setIsSaving: { isSaving = $0 },
            showSavedIndicator: { showSavedIndicator },
            setShowSavedIndicator: { showSavedIndicator = $0 },
            errorMessage: { errorMessage },
            setErrorMessage: { errorMessage = $0 },
            afterSave: {}
        )
    }
}

// MARK: - Raw Editor

struct ConfigRawEditorView: View {
    @Bindable var config: HugoConfig
    @State private var editableContent: String = ""
    @State private var isLoading = false
    @State private var hasParseError = false
    @State private var parseErrorMessage = ""

    /// Map config format to Highlightr language
    private var highlightrLanguage: String {
        switch config.sourceFormat {
        case .yaml:
            return "yaml"
        case .toml:
            return "ini" // Closest match for TOML
        case .json:
            return "json"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Info banner
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.Status.info)
                    .accessibilityHidden(true)
                Text("Changes made here will update the form view when you switch tabs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()

                // Refresh from disk button
                Button {
                    Task {
                        await refreshFromDisk()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Reload from disk")
                .accessibilityLabel("Reload from Disk")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.blue.opacity(0.05))

            if hasParseError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.Status.warning)
                        .accessibilityHidden(true)
                    Text(parseErrorMessage)
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.1))
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SyntaxHighlightedTextView(
                    text: $editableContent,
                    language: highlightrLanguage,
                    onTextChange: {
                        // Update the rawContent in config when edited
                        config.rawContent = editableContent
                        config.syncRawContentFromStructuredData()
                    }
                )
            }
        }
        .onAppear {
            loadContent()
        }
    }

    private func loadContent() {
        // Use the raw content stored in config (loaded from disk)
        if !config.rawContent.isEmpty {
            editableContent = config.rawContent
        } else {
            // Fallback: serialize from current config state
            do {
                editableContent = try HugoConfigParser.shared.serialize(config)
            } catch {
                editableContent = "// Error: Could not serialize configuration"
                hasParseError = true
                parseErrorMessage = error.localizedDescription
            }
        }
    }

    private func refreshFromDisk() async {
        guard let url = config.sourceURL else { return }

        isLoading = true
        do {
            let content = try await HugoConfigParser.shared.readRawContent(from: url)
            await MainActor.run {
                editableContent = content
                config.rawContent = content
                hasParseError = false
                parseErrorMessage = ""
                isLoading = false
            }
        } catch {
            await MainActor.run {
                hasParseError = true
                parseErrorMessage = "Failed to reload: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}
