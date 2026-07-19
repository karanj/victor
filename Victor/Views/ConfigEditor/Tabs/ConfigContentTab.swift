import SwiftUI

/// Content tab for Hugo configuration editor
/// Handles build options and content-summary settings.
///
/// Phase 1d: buildDrafts/buildFuture/buildExpired/summaryLength render via
/// `ConfigFieldView` off `config.store`.
///
/// Phase 5 (CONFIG-SCHEMA-SPEC §3.3): the Permalinks section and
/// `enableRobotsTXT` moved wholesale to `ConfigURLsTaxonomiesTab` — the spec
/// places both under "URLs & Taxonomies", not Content. This tab keeps only
/// the build flags + summaryLength it already had (no other §3.2 fields were
/// wired up here before this phase, so none are added now — see the task
/// brief's "Content tab keeps build flags + summaryLength + the §3.2 fields
/// it has").
struct ConfigContentTab: View {
    let config: HugoConfig

    /// No validator on this tab's migrated fields needs `siteURL`.
    private var validationContext: ValidationContext {
        ValidationContext(siteURL: nil, store: config.store)
    }

    var body: some View {
        Form {
            Section("Build Options") {
                ConfigFieldView(spec: ConfigSchema.spec(for: "buildDrafts")!, store: config.store, context: validationContext)
                ConfigFieldView(spec: ConfigSchema.spec(for: "buildFuture")!, store: config.store, context: validationContext)
                ConfigFieldView(spec: ConfigSchema.spec(for: "buildExpired")!, store: config.store, context: validationContext)
            }

            Section("Output") {
                ConfigFieldView(spec: ConfigSchema.spec(for: "summaryLength")!, store: config.store, context: validationContext)
            }
        }
        .formStyle(.grouped)
    }
}
