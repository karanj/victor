import SwiftUI

/// Essentials tab for Hugo configuration editor
/// Handles basic site identity, theme, and copyright settings
///
/// Phase 1d (CONFIG-SCHEMA-SPEC §2.6/§2.8): fields render via
/// `ConfigFieldView`, driven off `config.store` directly. This body reads
/// `config.store` (a plain `let`, not observed) and never a computed
/// accessor (`config.baseURL` etc.) or `store.version` — that's
/// `ConfigFieldView`'s job as the sole observation leaf, so a keystroke in
/// one field invalidates only that field's row, not this tab body.
struct ConfigEssentialsTab: View {
    let config: HugoConfig
    /// Site root, for the `theme` field's `themeExists` validator (checks
    /// `themes/<name>` on disk). `nil` when no site is open (tests, or a
    /// config with no known root) — the validator no-ops in that case.
    var siteRootURL: URL? = nil

    private var validationContext: ValidationContext {
        ValidationContext(siteURL: siteRootURL, store: config.store)
    }

    var body: some View {
        Form {
            Section("Site Identity") {
                ConfigFieldView(spec: ConfigSchema.spec(for: "baseURL")!, store: config.store, context: validationContext)
                ConfigFieldView(spec: ConfigSchema.spec(for: "title")!, store: config.store, context: validationContext)
                ConfigFieldView(spec: ConfigSchema.spec(for: "languageCode")!, store: config.store, context: validationContext)
            }

            Section("Theme") {
                ConfigFieldView(spec: ConfigSchema.spec(for: "theme")!, store: config.store, context: validationContext)
            }

            Section("Copyright") {
                ConfigFieldView(spec: ConfigSchema.spec(for: "copyright")!, store: config.store, context: validationContext)
            }
        }
        .formStyle(.grouped)
    }
}
