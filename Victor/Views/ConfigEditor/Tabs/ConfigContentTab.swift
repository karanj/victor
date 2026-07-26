import SwiftUI

/// Content tab: build options and content-summary settings, rendered via `ConfigFieldView`
/// off `config.store`.
///
/// Permalinks and `enableRobotsTXT` live on `ConfigURLsTaxonomiesTab` per
/// CONFIG-SCHEMA-SPEC §3.3, not here.
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
