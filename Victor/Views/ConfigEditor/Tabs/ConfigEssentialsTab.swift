import SwiftUI

/// Essentials tab: site identity, theme, copyright.
///
/// Fields render via `ConfigFieldView` off `config.store`. This body never reads a
/// computed accessor or `store.version` - that's the leaf's job, so a keystroke in one
/// field doesn't invalidate the tab.
///
/// `theme` and `locale`/`languageCode` get bespoke rows: the first needs a runtime
/// `themes/` listing plus shape preservation for module themes, the second writes to
/// either of two keys depending on file state. Neither fits a `ConfigValueType` case.
struct ConfigEssentialsTab: View {
    let config: HugoConfig
    /// Site root, for the `theme` field's `themeExists` validator (checks
    /// `themes/<name>` on disk) and `ConfigThemeRowView`'s directory listing.
    /// `nil` when no site is open (tests, or a config with no known root) —
    /// both no-op harmlessly in that case.
    var siteRootURL: URL? = nil

    @Environment(\.configCommitAction) private var commit

    private var validationContext: ValidationContext {
        ValidationContext(siteURL: siteRootURL, store: config.store)
    }

    var body: some View {
        Form {
            Section("Site Identity") {
                ConfigFieldView(spec: ConfigSchema.spec(for: "baseURL")!, store: config.store, context: validationContext)
                ConfigFieldView(spec: ConfigSchema.spec(for: "title")!, store: config.store, context: validationContext)
                ConfigLocaleRowView(store: config.store, commit: commit)
                ConfigFieldView(spec: ConfigSchema.spec(for: "timeZone")!, store: config.store, context: validationContext)
            }

            Section("Theme") {
                ConfigThemeRowView(store: config.store, siteRootURL: siteRootURL, commit: commit)
            }

            Section("Copyright") {
                ConfigFieldView(spec: ConfigSchema.spec(for: "copyright")!, store: config.store, context: validationContext)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Locale row (CONFIG-SCHEMA-SPEC §7.1)

/// One row serving both `locale` and the deprecated `languageCode`: shows whichever the
/// file has, writes back to that same key, and lints when both are present (`locale`
/// wins). Thin view over `ConfigLocaleResolver`, which holds the logic.
private struct ConfigLocaleRowView: View {
    let store: ConfigValueStore
    let commit: () -> Void

    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    private var resolution: ConfigLocaleResolution {
        ConfigLocaleResolver.resolve(
            localeValue: store.stringValue("locale"),
            languageCodeValue: store.stringValue("languageCode")
        )
    }

    var body: some View {
        let _ = store.version // observation leaf, same contract as ConfigFieldView

        LabeledContent("Locale") {
            VStack(alignment: .trailing, spacing: 4) {
                TextField("", text: $draft, prompt: Text("e.g. en-US"))
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .frame(width: 200)
                    .focused($isFocused)
                    .onSubmit { commitDraft() }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commitDraft() }
                    }

                if let warning = ConfigValidators.bcp47ish.validate(resolution.value, ValidationContext(siteURL: nil, store: store)) {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.Status.warning)
                }

                if resolution.displayedFromDeprecatedKey {
                    HStack(spacing: 6) {
                        Text("from languageCode (deprecated)")
                            .capsuleBadgeStyle(color: Color.Status.warning)
                        Button("Rename key to locale") {
                            store.remove(at: "languageCode")
                            store.set(resolution.value, at: "locale")
                            commit()
                        }
                        .font(.caption2)
                        .buttonStyle(.borderless)
                    }
                }

                if let lint = resolution.bothPresentLintMessage {
                    Label(lint, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.Status.warning)
                }
            }
        }
        .help("BCP 47 language/locale tag (e.g. en-US). Supersedes languageCode since Hugo v0.158.0.")
        .onAppear { draft = resolution.value }
        .onChange(of: resolution.value) { _, newValue in
            if !isFocused { draft = newValue }
        }
    }

    private func commitDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = resolution.writeKey
        if trimmed.isEmpty {
            if store.isPresent(key) {
                store.remove(at: key)
                commit()
            }
            return
        }
        guard trimmed != resolution.value else { return }
        store.set(trimmed, at: key)
        commit()
    }
}

// MARK: - Theme row (Phase 5 task brief item 7)

/// Free-text `theme` field (unchanged — preserves module-theme names not on
/// disk, and comma-joined array shape) plus a directory-listing menu button
/// that fills the field from `themes/` on disk when a site root is known.
private struct ConfigThemeRowView: View {
    let store: ConfigValueStore
    let siteRootURL: URL?
    let commit: () -> Void

    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    private var isPresent: Bool { store.isPresent("theme") }

    private var storedText: String {
        let raw = store.value(at: "theme")
        if raw is [Any] || raw is [String] {
            return store.stringArrayValue("theme")?.joined(separator: ", ") ?? ""
        }
        return store.stringValue("theme") ?? ""
    }

    /// Subdirectories of `themes/` — each a candidate theme name. Empty
    /// (menu button hidden) when there's no known site root or no
    /// `themes/` directory, e.g. a module-only site.
    private var availableThemes: [String] {
        guard let siteRootURL else { return [] }
        let themesDir = siteRootURL.appendingPathComponent("themes")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: themesDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .map(\.lastPathComponent)
            .sorted()
    }

    var body: some View {
        let _ = store.version

        LabeledContent("Theme") {
            HStack(spacing: 6) {
                TextField("", text: $draft, prompt: Text("none"))
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .frame(width: 200)
                    .focused($isFocused)
                    .onSubmit { commitDraft() }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commitDraft() }
                    }

                if !availableThemes.isEmpty {
                    Menu {
                        ForEach(availableThemes, id: \.self) { name in
                            Button(name) {
                                draft = name
                                commitDraft()
                            }
                        }
                    } label: {
                        Image(systemName: "folder")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24)
                    .help("Choose from themes/ directory")
                    .accessibilityLabel("Choose Theme from Directory")
                }

                if !isPresent {
                    Text("default")
                        .badgeStyle(color: .secondary)
                }
            }
        }
        .help("Theme name(s), read from the themes/ directory (or Hugo Modules).")
        .onAppear { draft = storedText }
        .onChange(of: storedText) { _, newValue in
            if !isFocused { draft = newValue }
        }
    }

    private func commitDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if isPresent {
                store.remove(at: "theme")
                commit()
            }
            return
        }
        guard trimmed != storedText else { return }
        if trimmed.contains(",") {
            let parts = trimmed.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            store.set(parts, at: "theme")
        } else {
            store.set(trimmed, at: "theme")
        }
        commit()
    }
}
