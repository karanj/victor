import SwiftUI

/// Advanced tab for Hugo configuration editor
/// Handles localization settings and displays custom fields and params
///
/// Phase 1d: defaultContentLanguage/timeZone render via `ConfigFieldView`
/// off `config.store`, fixing the per-keystroke `$config`/`.onChange`
/// binding that was here before. Their schema group is `.essentials`
/// (§3.1), but they stay on this tab — "keep today's placement" (Phase 1d
/// scope note) defers the essentials/locale reshuffle to a later phase.
/// The customFields/params sections stay bespoke read-only rows (Phase 2
/// replaces them with `DataDictionaryEditor`); they already read
/// `config.customFields`/`config.params` today and are unchanged here.
struct ConfigAdvancedTab: View {
    @Bindable var config: HugoConfig

    /// No validator on this tab's migrated fields needs `siteURL` (bcp47ish
    /// / timezone are pure string checks), so it's `nil` rather than
    /// threaded from `SiteViewModel` for no benefit.
    private var validationContext: ValidationContext {
        ValidationContext(siteURL: nil, store: config.store)
    }

    var body: some View {
        Form {
            Section("Localization") {
                ConfigFieldView(spec: ConfigSchema.spec(for: "defaultContentLanguage")!, store: config.store, context: validationContext)
                ConfigFieldView(spec: ConfigSchema.spec(for: "timeZone")!, store: config.store, context: validationContext)
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
