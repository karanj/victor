import SwiftUI

/// Main view for editing Hugo configuration
struct ConfigEditorView: View {
    @Bindable var config: HugoConfig
    let onSave: () async -> Void

    @State private var selectedTab: ConfigTab = .essentials
    @State private var showRawEditor = false
    @State private var isSaving = false
    @State private var showSavedIndicator = false

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
    }

    private var configToolbar: some View {
        HStack {
            // Config file icon
            Image(systemName: "gearshape.fill")
                .foregroundStyle(.orange)

            // File name
            if let url = config.sourceURL {
                Text(url.lastPathComponent)
                    .font(.headline)
            } else {
                Text("Hugo Configuration")
                    .font(.headline)
            }

            // Format badge
            Text(config.sourceFormat.rawValue.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.2))
                .cornerRadius(4)

            // Unsaved indicator
            if config.hasUnsavedChanges {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Unsaved changes")
                    .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
            }

            // Saved indicator
            if showSavedIndicator {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                    .accessibilityLabel("Saved")
                    .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
            }

            Spacer()

            // Toggle between form and raw
            Picker("View", selection: $showRawEditor) {
                Text("Form").tag(false)
                Text("Raw").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Divider()
                .frame(height: 20)

            // Save button
            Button {
                Task {
                    isSaving = true
                    await onSave()
                    isSaving = false
                    showSavedIndicatorBriefly()
                }
            } label: {
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            .disabled(!config.hasUnsavedChanges || isSaving)
            .keyboardShortcut("s", modifiers: .command)
            .help("Save (⌘S)")

            // Open in external editor
            if let url = config.sourceURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .help("Open in default app")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(reduceMotion ? nil : .easeInOut(duration: AppConstants.Animation.fast), value: config.hasUnsavedChanges)
        .animation(reduceMotion ? nil : .easeInOut(duration: AppConstants.Animation.fast), value: showSavedIndicator)
    }

    private func showSavedIndicatorBriefly() {
        showSavedIndicator = true
        Task {
            try? await Task.sleep(for: .seconds(2.0))
            showSavedIndicator = false
        }
    }
}

// MARK: - Essentials Tab

struct ConfigEssentialsTab: View {
    @Bindable var config: HugoConfig

    var body: some View {
        Form {
            Section("Site Identity") {
                LabeledContent("Base URL") {
                    TextField("",text: $config.baseURL, prompt: Text("https://example.com/"))
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                        .onChange(of: config.baseURL) { _, _ in
                            config.hasUnsavedChanges = true
                        }
                }
                .help("The absolute URL of your site")

                LabeledContent("Title") {
                    TextField("", text: $config.title, prompt: Text("My Site"))
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: config.title) { _, _ in
                            config.hasUnsavedChanges = true
                        }
                }
                .help("The title of your site")

                LabeledContent("Language Code") {
                    TextField("", text: $config.languageCode,prompt: Text("en-us"))
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: config.languageCode) { _, _ in
                            config.hasUnsavedChanges = true
                        }
                }
                .help("RFC 5646 language code (e.g., en-us)")
            }

            Section("Theme") {
                LabeledContent("Theme") {
                    TextField("", text: Binding(
                        get: { config.theme ?? "" },
                        set: { config.theme = $0.isEmpty ? nil : $0 }
                    ),prompt: Text("theme-name"))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: config.theme) { _, _ in
                        config.hasUnsavedChanges = true
                    }
                }
                .help("Theme name or comma-separated list of themes")
            }

            Section("Copyright") {
                LabeledContent("Copyright") {
                    TextField("", text: Binding(
                        get: { config.copyright ?? "" },
                        set: { config.copyright = $0.isEmpty ? nil : $0 }
                    ), prompt: Text("© 2025 Your Name"))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: config.copyright) { _, _ in
                        config.hasUnsavedChanges = true
                    }
                }
                .help("Copyright notice for your site footer")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Content Tab

struct ConfigContentTab: View {
    @Bindable var config: HugoConfig

    var body: some View {
        Form {
            Section("Build Options") {
                Toggle("Build Drafts", isOn: $config.buildDrafts)
                    .help("Include draft content in builds")
                    .onChange(of: config.buildDrafts) { _, _ in
                        config.hasUnsavedChanges = true
                    }

                Toggle("Build Future", isOn: $config.buildFuture)
                    .help("Include future-dated content in builds")
                    .onChange(of: config.buildFuture) { _, _ in
                        config.hasUnsavedChanges = true
                    }

                Toggle("Build Expired", isOn: $config.buildExpired)
                    .help("Include expired content in builds")
                    .onChange(of: config.buildExpired) { _, _ in
                        config.hasUnsavedChanges = true
                    }
            }

            Section("Output") {
                Toggle("Enable robots.txt", isOn: $config.enableRobotsTXT)
                    .help("Generate robots.txt file")
                    .onChange(of: config.enableRobotsTXT) { _, _ in
                        config.hasUnsavedChanges = true
                    }

                LabeledContent("Summary Length") {
                    Stepper("\(config.summaryLength) words",
                            value: $config.summaryLength, in: 10...500, step: 10)
                        .onChange(of: config.summaryLength) { _, _ in
                            config.hasUnsavedChanges = true
                        }
                }
                .help("Default length for auto-generated summaries")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Taxonomies Tab

struct ConfigTaxonomiesTab: View {
    @Bindable var config: HugoConfig
    @State private var newSingular = ""
    @State private var newPlural = ""

    var body: some View {
        Form {
            Section {
                ForEach(Array(config.taxonomies.keys.sorted()), id: \.self) { singular in
                    HStack {
                        Text(singular)
                            .fontWeight(.medium)
                            .frame(width: 120, alignment: .trailing)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(config.taxonomies[singular] ?? "")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) {
                            config.taxonomies.removeValue(forKey: singular)
                            config.hasUnsavedChanges = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    TextField("singular", text: $newSingular)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("plural", text: $newPlural)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Button("Add") {
                        if !newSingular.isEmpty && !newPlural.isEmpty {
                            config.taxonomies[newSingular] = newPlural
                            config.hasUnsavedChanges = true
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
        .formStyle(.grouped)
    }
}

// MARK: - Advanced Tab

struct ConfigAdvancedTab: View {
    @Bindable var config: HugoConfig

    var body: some View {
        Form {
            Section("Localization") {
                LabeledContent("Default Language") {
                    TextField("", text: $config.defaultContentLanguage,prompt: Text("en"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .onChange(of: config.defaultContentLanguage) { _, _ in
                            config.hasUnsavedChanges = true
                        }
                }

                LabeledContent("Time Zone") {
                    TextField("", text: Binding(
                        get: { config.timeZone ?? "" },
                        set: { config.timeZone = $0.isEmpty ? nil : $0 }
                    ),prompt: Text("America/New_York"))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: config.timeZone) { _, _ in
                        config.hasUnsavedChanges = true
                    }
                }
                .help("IANA time zone (e.g., America/New_York, Europe/London)")
            }

            if !config.customFields.isEmpty {
                Section("Other Fields (Preserved)") {
                    ForEach(Array(config.customFields.keys.sorted()), id: \.self) { key in
                        LabeledContent(key) {
                            Text(formatValue(config.customFields[key]))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            if !config.params.isEmpty {
                Section("Site Params") {
                    ForEach(Array(config.params.keys.sorted()), id: \.self) { key in
                        LabeledContent(key) {
                            Text(formatValue(config.params[key]))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func formatValue(_ value: Any?) -> String {
        guard let value = value else { return "nil" }
        if let dict = value as? [String: Any] {
            return "{\(dict.count) fields}"
        } else if let array = value as? [Any] {
            return "[\(array.count) items]"
        }
        return String(describing: value)
    }
}

// MARK: - Raw Editor

struct ConfigRawEditorView: View {
    @Bindable var config: HugoConfig
    @State private var editableContent: String = ""
    @State private var isLoading = false
    @State private var hasParseError = false
    @State private var parseErrorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            // Info banner
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
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
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.blue.opacity(0.05))

            if hasParseError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
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
                TextEditor(text: $editableContent)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .onChange(of: editableContent) { _, newValue in
                        // Update the rawContent in config when edited
                        config.rawContent = newValue
                        config.hasUnsavedChanges = true
                    }
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
