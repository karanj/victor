import Foundation

/// Resolution result for the single bespoke "Locale" row on the Essentials
/// tab (CONFIG-SCHEMA-SPEC §7.1). One row serves both `locale` and the
/// deprecated `languageCode` key, matching Hugo's own read-side migration
/// (if `languageCode` is set and `locale` is empty, Hugo copies the value
/// into `locale` in memory and ignores `languageCode`).
struct ConfigLocaleResolution: Equatable {
    /// The value to display/edit in the row's text field. Empty when neither
    /// key is present.
    let value: String
    /// Which key an edit from this row should write to — "whichever key the
    /// file has" (no silent renames): `locale` when present, `languageCode`
    /// when only it is present, `locale` when neither is present yet.
    let writeKey: String
    /// True when `value` was sourced from `languageCode` (locale absent) —
    /// drives the "from languageCode (deprecated)" badge + one-click rename.
    let displayedFromDeprecatedKey: Bool
    /// Non-nil only when *both* keys are present: `locale` wins (Hugo ignores
    /// `languageCode` in that case), and this carries the inline lint text
    /// suggesting the user remove the now-redundant `languageCode`.
    let bothPresentLintMessage: String?
}

/// Pure resolver — no `ConfigValueStore`/view dependency — so the
/// locale/languageCode precedence rules (CONFIG-SCHEMA-SPEC §7.1) are
/// directly unit-testable.
enum ConfigLocaleResolver {
    static func resolve(localeValue: String?, languageCodeValue: String?) -> ConfigLocaleResolution {
        let localePresent = localeValue != nil
        let languageCodePresent = languageCodeValue != nil

        switch (localePresent, languageCodePresent) {
        case (true, true):
            return ConfigLocaleResolution(
                value: localeValue ?? "",
                writeKey: "locale",
                displayedFromDeprecatedKey: false,
                bothPresentLintMessage: "Both locale and languageCode are set — languageCode is ignored. Consider removing it."
            )
        case (true, false):
            return ConfigLocaleResolution(
                value: localeValue ?? "",
                writeKey: "locale",
                displayedFromDeprecatedKey: false,
                bothPresentLintMessage: nil
            )
        case (false, true):
            return ConfigLocaleResolution(
                value: languageCodeValue ?? "",
                writeKey: "languageCode",
                displayedFromDeprecatedKey: true,
                bothPresentLintMessage: nil
            )
        case (false, false):
            return ConfigLocaleResolution(
                value: "",
                writeKey: "locale",
                displayedFromDeprecatedKey: false,
                bothPresentLintMessage: nil
            )
        }
    }
}
