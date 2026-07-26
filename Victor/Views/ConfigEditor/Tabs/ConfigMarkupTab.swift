import SwiftUI

/// Markup tab: goldmark, syntax highlighting, table of contents (CONFIG-SCHEMA-SPEC §3.5).
/// Every row is a `ConfigFieldView` looked up by key; this body reads no store values
/// itself, so a keystroke invalidates one row rather than the tab.
///
/// The inverted "Smart Punctuation" label is handled generically via
/// `ConfigSettingSpec.invertedBoolLabel` - no bespoke logic here.
struct ConfigMarkupTab: View {
    let config: HugoConfig

    /// No validator among the fields rendered here needs `siteURL`.
    private var validationContext: ValidationContext {
        ValidationContext(siteURL: nil, store: config.store)
    }

    var body: some View {
        Form {
            markdownSection
            syntaxHighlightingSection
            tableOfContentsSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Markdown (goldmark)

    private static let markdownKeys: [String] = [
        "markup.defaultMarkdownHandler",
        "markup.goldmark.renderer.unsafe",
        "markup.goldmark.renderer.hardWraps",
        "markup.goldmark.extensions.typographer.disable",
        "markup.goldmark.extensions.table",
        "markup.goldmark.extensions.strikethrough",
        "markup.goldmark.extensions.linkify",
        "markup.goldmark.extensions.linkifyProtocol",
        "markup.goldmark.extensions.taskList",
        "markup.goldmark.extensions.definitionList",
        "markup.goldmark.extensions.footnote.enable",
        "markup.goldmark.parser.autoHeadingID",
        "markup.goldmark.parser.autoIDType",
        "markup.goldmark.parser.attribute.title",
        "markup.goldmark.parser.attribute.block"
    ]

    private var markdownSection: some View {
        Section {
            ForEach(Self.markdownKeys, id: \.self) { key in
                markdownRow(for: key)
            }
        } header: {
            Text("Markdown (goldmark)")
        } footer: {
            Text("Non-goldmark handlers (asciidocext, org, pandoc, rst) require the matching external tool installed and on PATH.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// `renderer.unsafe`'s schema help already carries the security note
    /// (`.help` tooltip), but a key this consequential warrants a
    /// non-hover-dependent warning too — a static caption under the row,
    /// same visual language as `ConfigFieldView`'s own validator warnings.
    @ViewBuilder
    private func markdownRow(for key: String) -> some View {
        row(for: key)
        if key == "markup.goldmark.renderer.unsafe" {
            Text("Security: raw HTML and unsafe links from content pass straight through to output when enabled.")
                .font(.caption2)
                .foregroundStyle(Color.Status.warning)
        }
    }

    // MARK: - Syntax Highlighting

    private static let highlightingKeys: [String] = [
        "markup.highlight.style",
        "markup.highlight.codeFences",
        "markup.highlight.lineNos",
        "markup.highlight.lineNumbersInTable",
        "markup.highlight.lineNoStart",
        "markup.highlight.noClasses",
        "markup.highlight.tabWidth",
        "markup.highlight.guessSyntax"
    ]

    private var syntaxHighlightingSection: some View {
        Section {
            ForEach(Self.highlightingKeys, id: \.self) { key in
                row(for: key)
            }
        } header: {
            Text("Syntax Highlighting")
        }
    }

    // MARK: - Table of Contents

    private static let tableOfContentsKeys: [String] = [
        "markup.tableOfContents.startLevel",
        "markup.tableOfContents.endLevel",
        "markup.tableOfContents.ordered"
    ]

    private var tableOfContentsSection: some View {
        Section {
            ForEach(Self.tableOfContentsKeys, id: \.self) { key in
                row(for: key)
            }
        } header: {
            Text("Table of Contents")
        } footer: {
            Text("End Level -1 includes every heading level below Start Level.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Row lookup

    /// Force-unwrap is deliberate: a missing key here is a programmer error
    /// (a typo'd key in one of the lists above), matching
    /// `ConfigSchema.spec(for:)`'s doc comment and the existing
    /// `ConfigContentTab` pattern — it should surface immediately in a debug
    /// run, not silently drop a field from the tab.
    private func row(for key: String) -> some View {
        ConfigFieldView(spec: ConfigSchema.spec(for: key)!, store: config.store, context: validationContext)
    }

    /// All keys this tab renders, exposed for `ConfigAdvancedTab`'s
    /// `renderedOnOtherTabs` exclusion set so the same field never appears
    /// twice (here and in All Settings).
    static var allRenderedKeys: Set<String> {
        Set(markdownKeys + highlightingKeys + tableOfContentsKeys)
    }
}
