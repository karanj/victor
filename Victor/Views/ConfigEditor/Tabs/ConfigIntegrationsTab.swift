import SwiftUI

/// Integrations tab for Hugo configuration editor (CONFIG-SCHEMA-SPEC §3.6,
/// Phase 5) — analytics/comments/social-embed services, their paired privacy
/// toggles, RSS/sitemap settings, and the bespoke output-formats matrix.
///
/// Every row except the matrix is a `ConfigFieldView` off a schema key
/// looked up by `ConfigSchema.spec(for:)`, same pattern as `ConfigMarkupTab`.
/// The matrix (`ConfigOutputsMatrixSection`) is bespoke because its shape —
/// a stringArray-per-kind row toggled cell-by-cell across a dynamic column
/// set (built-ins ∪ the user's own `outputFormats` keys) — doesn't fit any
/// existing `ConfigValueType`; its read/toggle/write-back logic is extracted
/// into the pure, store-free `ConfigOutputsMatrix` type for direct testing.
struct ConfigIntegrationsTab: View {
    let config: HugoConfig

    @Environment(\.configCommitAction) private var commit

    /// No validator among the fields rendered here needs `siteURL`.
    private var validationContext: ValidationContext {
        ValidationContext(siteURL: nil, store: config.store)
    }

    var body: some View {
        Form {
            googleAnalyticsSection
            disqusSection
            xSection
            youtubeSection
            vimeoSection
            instagramSection
            rssSection
            sitemapSection
            ConfigOutputsMatrixSection(store: config.store, commit: commit)
        }
        .formStyle(.grouped)
    }

    // MARK: - Sections (each: service key(s) paired with its privacy toggle(s))

    private var googleAnalyticsSection: some View {
        Section("Google Analytics") {
            row("services.googleAnalytics.ID")
            row("privacy.googleAnalytics.disable")
            row("privacy.googleAnalytics.respectDoNotTrack")
        }
    }

    private var disqusSection: some View {
        Section("Disqus") {
            row("services.disqus.shortname")
            row("privacy.disqus.disable")
        }
    }

    private var xSection: some View {
        Section("X (Twitter)") {
            row("services.x.disableInlineCSS")
            row("privacy.x.disable")
            row("privacy.x.enableDNT")
            row("privacy.x.simple")
        }
    }

    private var youtubeSection: some View {
        Section("YouTube") {
            row("privacy.youtube.disable")
            row("privacy.youtube.privacyEnhanced")
        }
    }

    private var vimeoSection: some View {
        Section("Vimeo") {
            row("privacy.vimeo.disable")
            row("privacy.vimeo.enableDNT")
            row("privacy.vimeo.simple")
        }
    }

    private var instagramSection: some View {
        Section("Instagram") {
            row("privacy.instagram.disable")
            row("privacy.instagram.simple")
        }
    }

    private var rssSection: some View {
        Section("RSS") {
            row("services.rss.limit")
        }
    }

    private var sitemapSection: some View {
        Section("Sitemap") {
            row("sitemap.changeFreq")
            row("sitemap.priority")
            row("sitemap.filename")
            row("sitemap.disable")
        }
    }

    /// Force-unwrap is deliberate: a missing key here is a programmer error
    /// (a typo'd key in one of the section bodies above), matching
    /// `ConfigMarkupTab`'s `row(for:)` / `ConfigSchema.spec(for:)`'s doc
    /// comment.
    private func row(_ key: String) -> some View {
        ConfigFieldView(spec: ConfigSchema.spec(for: key)!, store: config.store, context: validationContext)
    }

    /// Every key this tab renders — the `ConfigFieldView` rows above plus the
    /// 5 `outputs.<kind>` keys the bespoke matrix owns (they have schema
    /// entries for the Advanced "All Settings" list's benefit, but the matrix
    /// is their only UI; excluding them here stops them from *also* showing
    /// as individual chip-array fields on Advanced). Feeds
    /// `ConfigAdvancedTab`'s `renderedOnOtherTabs` exclusion set.
    static var allRenderedKeys: Set<String> = [
        "services.googleAnalytics.ID", "privacy.googleAnalytics.disable", "privacy.googleAnalytics.respectDoNotTrack",
        "services.disqus.shortname", "privacy.disqus.disable",
        "services.x.disableInlineCSS", "privacy.x.disable", "privacy.x.enableDNT", "privacy.x.simple",
        "privacy.youtube.disable", "privacy.youtube.privacyEnhanced",
        "privacy.vimeo.disable", "privacy.vimeo.enableDNT", "privacy.vimeo.simple",
        "privacy.instagram.disable", "privacy.instagram.simple",
        "services.rss.limit",
        "sitemap.changeFreq", "sitemap.priority", "sitemap.filename", "sitemap.disable",
        "outputs.home", "outputs.page", "outputs.section", "outputs.taxonomy", "outputs.term"
    ]
}

// MARK: - Outputs matrix (bespoke)

/// Rows = home/section/taxonomy/term/page (`ConfigOutputsMatrix.kinds`),
/// columns = §4.4 built-in format names ∪ the user's own `outputFormats`
/// section keys. A kind with no `outputs.<kind>` key shows the §4.4 defaults
/// dimmed rather than blank, matching every other field's "default" styling.
private struct ConfigOutputsMatrixSection: View {
    let store: ConfigValueStore
    let commit: () -> Void

    private var rawOutputs: [String: Any] { store.subtree("outputs") ?? [:] }
    private var outputsDict: [String: [String]] { ConfigOutputsMatrix.normalizedOutputs(from: rawOutputs) }
    private var customFormatKeys: [String] { Array((store.subtree("outputFormats") ?? [:]).keys).sorted() }
    private var columns: [String] { ConfigOutputsMatrix.columns(customFormatKeys: customFormatKeys) }

    var body: some View {
        let _ = store.version // observation leaf, same contract as ConfigFieldView

        Section {
            ScrollView(.horizontal, showsIndicators: true) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        Text("")
                            .frame(width: 80, alignment: .leading)
                        ForEach(columns, id: \.self) { format in
                            Text(format)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .frame(width: 64, alignment: .leading)
                        }
                    }
                    ForEach(ConfigOutputsMatrix.kinds, id: \.self) { kind in
                        GridRow {
                            Text(kind.capitalized)
                                .frame(width: 80, alignment: .leading)
                            ForEach(columns, id: \.self) { format in
                                Toggle("", isOn: Binding(
                                    get: { isChecked(kind: kind, format: format) },
                                    set: { toggle(kind: kind, format: format, isOn: $0) }
                                ))
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                                .opacity(isDimmed(kind: kind) ? 0.55 : 1.0)
                                .frame(width: 64, alignment: .leading)
                                .accessibilityLabel("\(format) for \(kind)")
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Output Formats")
        } footer: {
            Text("Dimmed rows use Hugo's built-in defaults and aren't written to the file until changed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func isChecked(kind: String, format: String) -> Bool {
        ConfigOutputsMatrix.checkedFormats(for: kind, outputs: outputsDict).formats
            .contains { $0.caseInsensitiveCompare(format) == .orderedSame }
    }

    private func isDimmed(kind: String) -> Bool {
        !ConfigOutputsMatrix.checkedFormats(for: kind, outputs: outputsDict).isPresent
    }

    private func toggle(kind: String, format: String, isOn: Bool) {
        let updated = ConfigOutputsMatrix.applyToggle(kind: kind, format: format, isOn: isOn, in: outputsDict)
        if let value = ConfigOutputsMatrix.storageValue(for: updated) {
            store.replaceSubtree("outputs", with: value)
        } else {
            store.remove(at: "outputs")
        }
        commit()
    }
}
