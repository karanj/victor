import SwiftUI

/// Browser view for navigating Hugo template hierarchy
struct TemplateBrowserView: View {
    let siteURL: URL
    @Bindable var siteViewModel: SiteViewModel

    @State private var templates: [Template] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var selectedType: TemplateType?
    @State private var showThemeTemplates = true
    @State private var viewMode: ViewMode = .byType

    enum ViewMode: String, CaseIterable {
        case byType = "By Type"
        case byDirectory = "By Directory"
        case inheritance = "Inheritance"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            templateBrowserToolbar

            Divider()

            if isLoading {
                loadingView
            } else if templates.isEmpty {
                emptyStateView
            } else {
                // Main content
                HSplitView {
                    // Template list
                    templateListView
                        .frame(minWidth: 250, idealWidth: 300)

                    // Statistics panel
                    templateStatsPanel
                        .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
                }
            }
        }
        .task {
            await loadTemplates()
        }
    }

    // MARK: - Toolbar

    private var templateBrowserToolbar: some View {
        HStack {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.blue)

            Text("Template Browser")
                .font(.headline)

            // Template count
            Text("\(filteredTemplates.count) templates")
                .badgeStyle(color: .secondary, font: Font.caption, backgroundOpacity: 0.1, horizontalPadding: 8)

            Spacer()

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search templates...", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 150)

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
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.secondary.opacity(0.1))
            .cornerRadius(6)

            Divider()
                .frame(height: 20)

            // View mode picker
            Picker("View", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: AppConstants.Toolbar.viewFormLabelFrameWidth*2)

            Divider()
                .frame(height: 20)

            // Theme toggle
            Toggle(isOn: $showThemeTemplates) {
                Text("Themes")
            }
            .toggleStyle(.checkbox)

            // Refresh button
            Button {
                Task {
                    await loadTemplates()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh templates")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Template List

    private var templateListView: some View {
        List {
            switch viewMode {
            case .byType:
                templatesByTypeContent
            case .byDirectory:
                templatesByDirectoryContent
            case .inheritance:
                templatesInheritanceContent
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var templatesByTypeContent: some View {
        ForEach(TemplateType.allCases, id: \.self) { type in
            let typeTemplates = filteredTemplates.filter { $0.templateType == type }
            if !typeTemplates.isEmpty {
                Section {
                    ForEach(typeTemplates) { template in
                        TemplateRow(template: template, onSelect: {
                            selectTemplate(template)
                        })
                    }
                } header: {
                    HStack {
                        Image(systemName: type.systemImage)
                            .foregroundStyle(typeColor(for: type))
                        Text(type.displayName)
                        Spacer()
                        Text("\(typeTemplates.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var templatesByDirectoryContent: some View {
        let grouped = Dictionary(grouping: filteredTemplates) { $0.directoryPath }
        let sortedDirs = grouped.keys.sorted()

        ForEach(sortedDirs, id: \.self) { dir in
            let dirTemplates = grouped[dir] ?? []
            Section {
                ForEach(dirTemplates) { template in
                    TemplateRow(template: template, onSelect: {
                        selectTemplate(template)
                    })
                }
            } header: {
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(Color.FileIcon.folder)
                    Text(dir.isEmpty ? "Root" : dir)
                    Spacer()
                    Text("\(dirTemplates.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var templatesInheritanceContent: some View {
        // Base templates
        let baseTemplates = filteredTemplates.filter { $0.templateType == .base || $0.metadata.definesBlocks }
        if !baseTemplates.isEmpty {
            Section("Base Templates") {
                ForEach(baseTemplates) { template in
                    VStack(alignment: .leading, spacing: 4) {
                        TemplateRow(template: template, onSelect: {
                            selectTemplate(template)
                        })

                        // Show templates that extend this base
                        let extending = filteredTemplates.filter { ext in
                            ext.metadata.hasBaseTemplate && ext.id != template.id
                        }
                        if !extending.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(extending.prefix(5)) { ext in
                                    HStack {
                                        Image(systemName: "arrow.turn.down.right")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(ext.fileName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.leading, 24)
                                    .onTapGesture {
                                        selectTemplate(ext)
                                    }
                                }
                                if extending.count > 5 {
                                    Text("... and \(extending.count - 5) more")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .padding(.leading, 24)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Partials section
        let partials = filteredTemplates.filter { $0.templateType == .partial }
        if !partials.isEmpty {
            Section("Partials") {
                ForEach(partials) { template in
                    TemplateRow(template: template, onSelect: {
                        selectTemplate(template)
                    })
                }
            }
        }

        // Shortcodes section
        let shortcodes = filteredTemplates.filter { $0.templateType == .shortcode }
        if !shortcodes.isEmpty {
            Section("Shortcodes") {
                ForEach(shortcodes) { template in
                    TemplateRow(template: template, onSelect: {
                        selectTemplate(template)
                    })
                }
            }
        }
    }

    // MARK: - Stats Panel

    private var templateStatsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Summary
                VStack(alignment: .leading, spacing: 8) {
                    Label("Summary", systemImage: "chart.bar")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 4) {
                        TemplateStatRow(label: "Total templates", value: "\(templates.count)")
                        TemplateStatRow(label: "Site templates", value: "\(templates.siteTemplates.count)")
                        TemplateStatRow(label: "Theme templates", value: "\(templates.themeTemplates.count)")
                    }
                    .font(.caption)
                }

                Divider()

                // By Type
                VStack(alignment: .leading, spacing: 8) {
                    Label("By Type", systemImage: "square.stack.3d.up")
                        .font(.headline)

                    let grouped = templates.groupedByType
                    ForEach(TemplateType.allCases, id: \.self) { type in
                        if let count = grouped[type]?.count, count > 0 {
                            HStack {
                                Image(systemName: type.systemImage)
                                    .foregroundStyle(typeColor(for: type))
                                    .frame(width: 20)
                                Text(type.displayName)
                                Spacer()
                                Text("\(count)")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                }

                Divider()

                // Most used partials
                VStack(alignment: .leading, spacing: 8) {
                    Label("Popular Partials", systemImage: "puzzlepiece")
                        .font(.headline)

                    let partialCounts = TemplateParser.shared.getAllPartialReferences(templates: templates)
                    let sorted = partialCounts.sorted { $0.value > $1.value }

                    if sorted.isEmpty {
                        Text("No partials used")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sorted.prefix(10), id: \.key) { partial, count in
                            HStack {
                                Text(partial.replacingOccurrences(of: ".html", with: ""))
                                    .font(.system(.caption, design: .monospaced))
                                Spacer()
                                Text("×\(count)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Supporting Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Scanning templates...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No Templates Found")
                .font(.headline)
            Text("This Hugo site doesn't have any template files in layouts/ or themes/.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Computed Properties

    private var filteredTemplates: [Template] {
        var result = templates

        // Filter by theme toggle
        if !showThemeTemplates {
            result = result.filter { !$0.isThemeTemplate }
        }

        // Filter by search text
        if !searchText.isEmpty {
            let lowercased = searchText.lowercased()
            result = result.filter {
                $0.fileName.lowercased().contains(lowercased) ||
                $0.relativePath.lowercased().contains(lowercased) ||
                $0.templateType.displayName.lowercased().contains(lowercased)
            }
        }

        // Filter by selected type
        if let selectedType = selectedType {
            result = result.filter { $0.templateType == selectedType }
        }

        return result
    }

    // MARK: - Helper Methods

    private func loadTemplates() async {
        isLoading = true
        do {
            templates = try await TemplateParser.shared.discoverTemplates(in: siteURL)
            templates.sort { $0.relativePath < $1.relativePath }
        } catch {
            Logger.shared.error("Failed to load templates", error: error)
        }
        isLoading = false
    }

    private func selectTemplate(_ template: Template) {
        // Find the file node for this template and select it in the sidebar
        for rootNode in siteViewModel.fileNodes {
            if let node = rootNode.findNode(url: template.url) {
                // Use selectAndRevealNode to expand parent folders and select
                siteViewModel.selectAndRevealNode(node)
                return
            }
        }
    }

    private func typeColor(for type: TemplateType) -> Color {
        switch type {
        case .base: return .purple
        case .partial: return .teal
        case .shortcode: return .orange
        case .single, .list: return .blue
        case .home: return .green
        case .taxonomy, .section: return .indigo
        case .other: return .gray
        }
    }
}

// MARK: - Template Row

private struct TemplateRow: View {
    let template: Template
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: template.templateType.systemImage)
                .foregroundStyle(typeColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(template.fileName)
                    .lineLimit(1)

                // Show full path for context (e.g., "layouts/_default" or "themes/mytheme/layouts/partials")
                Text(template.fullDirectoryPath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Badges
            if template.isThemeTemplate {
                Text("theme")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.purple.opacity(0.7))
                    .cornerRadius(3)
            }

            if template.metadata.definesBlocks {
                Image(systemName: "square.stack.3d.up")
                    .font(.caption2)
                    .foregroundStyle(.purple)
                    .help("Defines blocks")
            }

            if !template.metadata.partials.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: "puzzlepiece")
                        .font(.caption2)
                    Text("\(template.metadata.partials.count)")
                        .font(.caption2)
                }
                .foregroundStyle(.teal)
                .help("\(template.metadata.partials.count) partials used")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }

    private var typeColor: Color {
        switch template.templateType {
        case .base: return .purple
        case .partial: return .teal
        case .shortcode: return .orange
        case .single, .list: return .blue
        case .home: return .green
        case .taxonomy, .section: return .indigo
        case .other: return .gray
        }
    }
}

// MARK: - Template Stat Row

private struct TemplateStatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }
}
