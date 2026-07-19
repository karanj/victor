# Config Editor v2 — Schema Specification & Architecture

**Status**: Vetted, ready for implementation | **Date**: 2026-07-19 | **Companion to**: `CONFIG-EDITOR-DESIGN.md`

**Research method**: The design doc's coverage review was written against the Hugo docs site. This spec was verified against the **Hugo v0.164.0 source code** (fetched from the Go module proxy): `config/allconfig/allconfig.go` (`RootConfig` + `newDefaultConfig()`), `config/allconfig/alldecoders.go` (per-section decoders and their defaults), and each section package (`markup_config`, `highlight`, `goldmark_config`, `tableofcontents`, `services`, `privacy`, `navigation`, `related`, `config.Pagination/SitemapConfig/PageConfig`, `resources/images`, `minifiers`). Every default and deprecation below is from source, not docs prose. Highlight style names are from chroma v2.27.0 (the version pinned in Hugo v0.164.0's `go.mod`).

---

## 1. Research Findings — Corrections & Additions to the Design Doc

### 1.1 New correctness issues (append to design doc §2)

7. **`.yml` config files are never discovered.** Hugo accepts basenames `hugo`/`config` with extensions `toml`/`yaml`/`yml`/`json` (`config/configLoader.go: DefaultConfigNames`, `ValidConfigFileExtensions`). Victor's `findConfigFile` list omits `hugo.yml`/`config.yml`, so those sites get no config GUI at all — even though `ConfigFormat.init(filename:)` already maps `.yml` → `.yaml` correctly. One-line fix; belongs in Phase 0.
8. **Menu items silently drop fields on save.** `HugoMenuItem` round-trips only `name/url/pageRef/weight/identifier/parent`. Hugo's `navigation.MenuConfig` also has `title`, `pre`, `post`, and `params` (arbitrary user map). A config with `[[menus.main]] … title = "…"` loses `title` on any form-mode save. Fix in Phase 0 by carrying an `extra: [String: Any]` passthrough on `HugoMenuItem`; the Menus tab (Phase 3) can then choose to expose `title` and leave `pre/post/params` as preserved-but-uneditied.
9. **Victor's permalink token menu offers a deprecated token.** `:filename` was deprecated in Hugo v0.144 (→ `:contentbasename`), as was `:slugorfilename` (→ `:slugorcontentbasename`). `PermalinkResolver.validTokens` lists `:filename`. Add the two new tokens, keep the old ones recognized-but-flagged (schema deprecation lint), and stop offering the old ones in the insert menu.

### 1.2 Facts that shape the design (all verified in source)

- **`languageCode` → `locale`**: deprecated v0.158.0. Hugo's own migration: if `languageCode` set and `locale` empty, the value is copied into `locale` and `languageCode` is cleared *in memory* (the file is untouched). Per-language keys were renamed at the same time: `languageName`→`label`, `languageDirection`→`direction`. Resolution of design-doc §5's open question is in §7.1 below.
- **Legacy root keys still honored as fallbacks**: root `googleAnalytics` (→ `services.googleAnalytics.ID`) and root `disqusShortname` (→ `services.disqus.shortname`) are read by `services.DecodeConfig` when the nested key is empty. Root `paginate`/`paginatePath` were **removed** (not just deprecated) in favor of `pagination.pagerSize`/`pagination.path`. All four go in the lint table.
- **Twitter → X rename (v0.141)**: `privacy.twitter.*` → `privacy.x.*`, `services.twitter.disableInlineCSS` → `services.x.disableInlineCSS`. `services.instagram.*` is dead config (the embedded shortcode no longer uses it) — do not surface.
- **`privacy.googleAnalytics.respectDoNotTrack` defaults to `true`** (set before decode in `privacy.DecodeConfig`) — the one privacy field whose default isn't `false`.
- **Sentinel defaults**: `sitemap.priority` default is `-1` meaning "omit from the sitemap output" (not 0.5); `services.rss.limit` default `-1` meaning unlimited. Placeholder rendering must show these as "not written", not as numbers users should copy.
- **`timeout` is a duration string** (`"60s"`, `"30m"`); a bare integer is interpreted as seconds. Default `60s`.
- **`theme` is `[]string` in Hugo** — a plain string in config is weak-decoded into a one-element array. Victor's string-or-array preservation is correct; schema type is `.stringOrStringArray`.
- **`uglyURLs` is `bool` or `map[string]bool`** (per-section). Schema type `.boolOrSectionMap`; GUI renders the bool, shows "per-section map — edit in Raw" when it's a map.
- **`markup.highlight.lineNos` is `bool` or `"inline"`/`"table"`** (validated in `toHTMLOptions`). Schema type `.boolOrEnum(["inline","table"])`.
- **Goldmark config migrations Hugo performs on read** (schema lints, low priority): `goldmark.extensions.typographer` bool→struct (v0.112), `…extensions.footnote` bool→struct (v0.151), `goldmark.parser.attribute` bool→struct (v0.81), `parser.autoHeadingIDType`→`parser.autoIDType` (v0.144), `renderHooks.{image,link}.enableDefault`→`.useEmbedded` (v0.148).
- **New in the v0.16x line, present in v0.164**: site dimensions `roles`/`versions` with root keys `defaultContentRole(-InSubdir)`, `defaultContentVersion(-InSubdir)`, `disableDefaultSiteRedirect`, `renderSegments`. These go in the schema (Advanced list) so they don't degrade to "unknown key", but get no dedicated UI.
- **`environment` default** is `production` (build) / `development` (server) — informational placeholder only; not a field users should normally write.
- **Author/Social root sections are deprecated** (`author` → taxonomies, `social` → params) — lint only.
- Hugo's file-discovery precedence is **basename-major** (`hugo.*` all extensions, then `config.*`), matching Victor's existing order. Only the missing `yml` entries need adding.

---

## 2. Architecture

### 2.1 Components

```
ConfigSchema (static table)          ConfigValueStore (per open config)
  [ConfigSettingSpec]  ──describes──▶  sparse [String: Any] + presence
        │                                    │        ▲
        │ renders via                        │ get/set│ single write path
        ▼                                    ▼        │
  ConfigFieldView(spec:store:) ──────▶ leaf row views (commit-on-blur)
        │
        ▼
  HugoConfig (@Observable, EditableFile)
    - owns the store; 13 legacy typed fields become computed accessors
    - serialize() walks the store, writes only present keys
```

New files (Phase 1):

| File | Contents |
|---|---|
| `Models/ConfigSchema.swift` | `ConfigSettingSpec`, `ConfigValueType`, `ConfigGroup`, the static spec table |
| `Models/ConfigValueStore.swift` | Sparse store, key-path access, presence, version counter |
| `Services/ConfigValidators.swift` | `ConfigValidator` catalog + `ValidationContext` |
| `Views/ConfigEditor/ConfigFieldView.swift` | Generic type→control renderer |
| `VictorTests/ConfigSchemaTests.swift`, `ConfigValueStoreTests.swift` | See §5 |

### 2.2 `ConfigValueStore`

```swift
@Observable
final class ConfigValueStore {
    // The raw parsed config. NOT observable — mirrors FileCacheManager's rule
    // that big mutable blobs must never be observation dependencies.
    @ObservationIgnored private var root: [String: Any]

    // The only observable signal. Bumped by every mutation.
    private(set) var version: Int = 0

    init(root: [String: Any])            // normalized at the boundary (§2.7)

    // Key paths are dot-joined string segments: "markup.goldmark.renderer.unsafe".
    // Segments never contain dots for schema-known keys (Hugo guarantees this);
    // params/customFields subtrees are handed out as whole values, not paths.
    func value(at path: String) -> Any?
    func isPresent(_ path: String) -> Bool
    func set(_ value: Any, at path: String)    // creates intermediate dicts
    func remove(at path: String)               // prunes now-empty intermediates
    func subtree(_ path: String) -> [String: Any]?   // for recursive editors
    func replaceSubtree(_ path: String, with: [String: Any])
    func snapshotRoot() -> [String: Any]       // for serialization
}
```

Decisions:

- **Presence is "key exists in `root`"** — nothing else. No shadow "user touched this" set: after `set`, the key is present; after `remove`, absent. The file's key set *is* the model. This is what makes sparse serialization structurally correct rather than policed by convention.
- **`remove` prunes empty parents** so clearing the last markup override doesn't leave `markup = {}` / `[markup]` stubs in the file.
- **Lenient reads, strict writes.** Hugo weak-decodes (`"true"`, `"10"` accepted). `value(at:)` returns the raw stored value; typed accessors on `ConfigSettingSpec` (§2.3) coerce for display (`boolValue(in:)` accepts Bool/"true"/1…). Writes always store the schema's canonical Swift type, so a save normalizes sloppy types the same direction Hugo would read them.
- **Yams normalization happens once, at store construction**: `[AnyHashable: Any]` → `[String: Any]` recursively (extending `SerializationHelper.normalizeForSerialization`), so key-path code and every editor above the store only ever sees `[String: Any]`. This kills the class of bug in design-doc issue #4 for **all** sections at once, not just menus — with the store in place, the menus/permalinks special-casing in `HugoConfig.init(from:)` disappears.

### 2.3 `ConfigSettingSpec` (final shape)

```swift
struct ConfigSettingSpec: Identifiable, Sendable {
    var id: String { key }
    let key: String                    // full dotted path
    let type: ConfigValueType
    let defaultValue: ConfigDefault    // .value(Any), .none, .sentinel(Any, meaning: String)
    let label: String
    let help: String                   // one line, sourced from Hugo source doc comments
    let group: ConfigGroup             // tab/section placement (§3)
    let validator: ConfigValidator?    // §2.4
    let deprecation: ConfigDeprecation?  // §2.5
}

enum ConfigValueType: Sendable {
    case bool
    case string
    case int
    case double
    case duration                      // string like "60s"; bare int = seconds
    case stringArray                   // token field
    case stringMap                     // flat [String: String] (taxonomies-like)
    case choice([String])              // exclusive enum, Picker
    case boolOrEnum([String])          // lineNos
    case stringOrStringArray           // theme
    case boolOrSectionMap              // uglyURLs
    case dictionary                    // recursive editor subtree (params)
    case rawOnly                       // shown read-only + "Edit in Raw"
}

enum ConfigGroup: String, CaseIterable {
    case essentials, contentBuild, urlsTaxonomies, menus, markup,
         integrations, advanced      // .advanced = All Settings list only
    // rawOnly sections carry .advanced + type .rawOnly
}
```

- `ConfigDefault.sentinel` exists for `sitemap.priority = -1` / `rss.limit = -1`: the placeholder renders the *meaning* ("omitted from sitemap", "unlimited"), never the sentinel number.
- The table is a `static let all: [ConfigSettingSpec]` array. **Tests enforce table invariants** (§5) — unique keys, labels non-empty, enums non-empty, groups consistent — so drift is caught at test time, not review time.
- Union types (`boolOrEnum`, `stringOrStringArray`, `boolOrSectionMap`) are deliberate: Hugo genuinely accepts both shapes, and a schema that lies about that either destroys data or blocks valid configs. Renderer behavior per type is in §2.6.

### 2.4 Validators

```swift
struct ValidationContext {
    let siteURL: URL?          // for theme-directory lookup
    let store: ConfigValueStore // for cross-field checks
}

struct ConfigValidator: Sendable {
    let validate: @Sendable (Any, ValidationContext) -> String?  // nil = OK, else warning text
}
```

Catalog (all **warnings, never blocking** — design doc §3.3 stands):

| Validator | Rule | Used by |
|---|---|---|
| `absoluteURL` | parses as URL with scheme+host; warn if no trailing `/` | baseURL |
| `bcp47ish` | `xx` / `xx-YY` shape (lenient regex, not a registry lookup) | locale, defaultContentLanguage |
| `timezone` | member of `TimeZone.knownTimeZoneIdentifiers` (also powers the picker) | timeZone |
| `themeExists` | each name is a directory in `themes/` — *skipped* (info note, not warning) when `module` section present, since module themes aren't on disk | theme |
| `intRange(min:max:)` | bounds | summaryLength (1…), pagination.pagerSize (1…), tabWidth (1…16), TOC levels (1…6 or -1), rss.limit (-1…) |
| `duration` | parses as int (seconds) or Go-style duration suffix s/m/h | timeout |
| `memberOf(enum)` | value in list (case-insensitive, matching Hugo) | every `.choice` |
| `kindsList` | each element ∈ page kinds enum (§4.3) | disableKinds |
| `outputFormatsKnown` | each format name ∈ §4.4 ∪ keys of user's `outputFormats` section | outputs.* |
| `sectionName` | reuse `PermalinkResolver.validateSectionName` | taxonomies keys, permalinks keys |
| `taxonomyPair` | singular ≠ plural, no duplicates, lowercase recommended | taxonomies |
| `changeFreq` | ∈ sitemap frequency enum (§4.6) or empty | sitemap.changeFreq |
| `priorityRange` | -1 or 0.0…1.0 | sitemap.priority |
| `hexColor` | `#rgb`/`#rrggbb` | imaging.bgColor (Advanced list) |

### 2.5 Deprecations & migrations

```swift
struct ConfigDeprecation: Sendable {
    let since: String                  // "0.158.0"
    let message: String                // "Use locale instead."
    let replacementKey: String?        // enables the one-click "Rename key" affordance
}
```

Two distinct mechanisms:

1. **Spec-attached deprecation** — the key is in the schema (it still round-trips): renders an inline badge + message on its field, plus optional `[Use <new key>]` button that moves the value (`remove(old); set(value, at: new)`) — explicit user action, never automatic. Entries: `languageCode`→`locale`, `ignoreFiles`→module mounts (no auto-move), `staticDir0…10`, `author`, `social`, `privacy.twitter.*`→`privacy.x.*`, `services.twitter.disableInlineCSS`→`services.x.disableInlineCSS`, `parser.autoHeadingIDType`→`parser.autoIDType`, `renderHooks.*.enableDefault`→`.useEmbedded`.
2. **Removed-key lint table** — keys Hugo no longer reads at all; if present anywhere in the file, the Advanced tab shows a warnings section: `paginate`→`pagination.pagerSize`, `paginatePath`→`pagination.path`, root `googleAnalytics`→`services.googleAnalytics.ID` (fallback still works — phrase as "legacy location"), root `disqusShortname`→`services.disqus.shortname`, permalink tokens `:filename`/`:slugorfilename` (scanned inside permalink values, not keys).

### 2.6 Generic renderer `ConfigFieldView`

| `ConfigValueType` | Control (present) | Placeholder (absent) |
|---|---|---|
| bool | Toggle | Toggle showing default, dimmed, "default" tag; first toggle writes the key |
| string | TextField (commit on blur/submit) | grayed `prompt:` with default |
| int / double | TextField + `.number` format, Stepper where range known | grayed default |
| duration | TextField + trailing unit hint | grayed default (`60s`) |
| choice | Picker (menu style) with extra "— default (X) —" row = not written | Picker on the default row |
| boolOrEnum | Picker: Off / On / per-enum-case | same |
| stringArray | Token-style editable chips (pattern from taxonomies tab) | "—" |
| stringMap | Existing taxonomies-style pair editor | "—" |
| stringOrStringArray | TextField; renders array joined ", "; **preserves incoming shape** on write, comma in input ⇒ array (current theme behavior, kept) | grayed default |
| boolOrSectionMap | Toggle when bool/absent; map ⇒ read-only summary + "Edit in Raw" | Toggle w/ default |
| dictionary | `DataDictionaryEditor` (extracted, §3 Advanced) | "Add …" affordance |
| rawOnly | Read-only key list + "Edit in Raw" button | hidden |

Every present field gets a trailing **reset-to-default** affordance (⌫ icon / context menu) that calls `remove(at:)` — the only way a key leaves the file besides Raw mode.

### 2.7 Serialization policy

- `serialize()` = `store.snapshotRoot()` → format writer. **No unconditional inserts, no default-suppression** — both directions of design-doc issues #1/#2 die structurally, because typed fields no longer exist as always-serialized properties.
- **Key spelling preservation**: store records `menuKeySpelling: "menu" | "menus"` at parse (issue #3); new menu sections use `menus` (Hugo's documented name). Same pattern generalizes if another aliased key appears later.
- **Key order**: capture root-level key order at parse time (`orderedRootKeys: [String]`; TOMLKit tables and Yams mappings both iterate in document order). Serializer emits known keys in that order, new keys appended alphabetically. This is best-effort (nested tables keep writer order) and **Phase 0's test asserts key-set equality, not byte equality** — comment/whitespace loss remains the accepted limitation from design-doc §5.
- **Format writers unchanged** (`TOMLHelper`, `SerializationHelper.serializeToYAMLValidated` with `width: -1`, JSON).

### 2.8 Typing-latency compliance (per-keystroke invalidation contract)

The CLAUDE.md contract applies:

- `ConfigValueStore.root` is `@ObservationIgnored` — the blob is never a dependency (rule 5, `FileCacheManager` precedent).
- Text fields **commit on blur/submit**, holding drafts in local `@State` — the established `PermalinkRowView` pattern. So `version` bumps happen per *edit*, not per keystroke, and no `.onChange(of: <text>)` appears in any non-leaf body.
- `ConfigFieldView` is the leaf; it reads `store.version` (via its typed read) so invalidation stops at the row. The tab bodies iterate `[ConfigSettingSpec]` (static) and never read store values themselves.
- `HugoConfig.hasUnsavedChanges` stays `rawContent != originalContent`, recomputed via `syncRawContentFromStructuredData()` on commit — unchanged blast radius vs. today (toolbar save button already observes it).
- Nothing here touches `EditorActions` or menu-bar state; no new `.commands` dependencies.

### 2.9 `HugoConfig` migration (Phase 1, keeps 200+ existing tests green)

- `HugoConfig` gains `let store: ConfigValueStore`; `init(from dictionary:…)` normalizes and seeds the store, then drops nearly all its bespoke field parsing.
- The 13 stored fields become **computed properties over the store** with identical names/types (`var buildDrafts: Bool { get { store.boolValue("buildDrafts") ?? false } set { store.set(newValue, at: "buildDrafts") } }`) — sites of `@Bindable`/`$config.buildDrafts` keep compiling. ⚠️ Semantics change *intentionally*: the getter's fallback is Hugo's default, and the setter now marks the key present (that's the point). Tests asserting "minimal config serializes 6 extra keys" flip polarity in Phase 0/1.
- `params` and `customFields` become subtree views (`store.subtree("params")`, and "everything not in the schema root set" respectively). `customFields` stops being storage — unknown keys simply live in the store and appear in the Advanced unknown-keys editor.
- `menus` stays a typed materialization for the Menus tab: parsed from `store.subtree(menuSpelling)` on load and after Raw→Form, written back through one `commitMenus()` path; `HugoMenuItem` gains the `extra` passthrough dict (finding #8). Reference semantics stay per the Model Type Strategy table (CLAUDE.md).
- `EditableFile` conformance, `sourceFormat`, `rawContent`/`originalContent` change detection: all unchanged.

---

## 3. Full Schema Table

Legend: **D** = Hugo default (from source). Type abbreviations match `ConfigValueType`. All entries also carry help text lifted from Hugo's source doc comments (not reproduced here — write them into the table at implementation time; keep to one line).

### 3.1 Essentials tab

| Key | Type | D | Control/Validator | Notes |
|---|---|---|---|---|
| `baseURL` | string | "" | `absoluteURL` | required-for-Hugo note when absent |
| `title` | string | "" | — | |
| `theme` | stringOrStringArray | — | `themeExists` + picker from `themes/` dir listing, free-text allowed | modules note |
| `copyright` | string | "" | — | |
| `locale` | string | "" | `bcp47ish` | see §7.1: one row serves locale/languageCode |
| `languageCode` | string | "" | `bcp47ish` | **deprecated 0.158** → `locale`; rename affordance |
| `defaultContentLanguage` | string | "en" | `bcp47ish` | |
| `timeZone` | string | "" | `timezone` + searchable picker from `TimeZone.knownTimeZoneIdentifiers` | |

### 3.2 Content & Build tab

| Key | Type | D | Control/Validator |
|---|---|---|---|
| `buildDrafts` | bool | false | Toggle |
| `buildFuture` | bool | false | Toggle |
| `buildExpired` | bool | false | Toggle |
| `enableGitInfo` | bool | false | Toggle |
| `enableEmoji` | bool | false | Toggle |
| `hasCJKLanguage` | bool | false | Toggle |
| `summaryLength` | int | 70 | Stepper 10…500 step 10 (existing) |
| `mainSections` | stringArray | [] (guessed by Hugo) | chips |
| `titleCaseStyle` | choice | "ap" | Picker §4.1 |
| `pluralizeListTitles` | bool | **true** | Toggle |
| `capitalizeListTitles` | bool | **true** | Toggle |
| `timeout` | duration | "60s" | `duration` |
| `disableKinds` | stringArray | [] | chips + `kindsList` (§4.3) |
| `environment` | string | production/development | read-mostly; Advanced-style footnote |

### 3.3 URLs & Taxonomies tab

| Key | Type | D | Control/Validator |
|---|---|---|---|
| `permalinks` | (bespoke, exists) | {} | + add `:contentbasename`, `:slugorcontentbasename` tokens; deprecate `:filename`, `:slugorfilename` (finding #9) |
| `taxonomies` | stringMap | {category: categories, tag: tags} | bespoke (exists) + edit-in-place + `taxonomyPair`; **preserve when explicitly present even if equal to default** (issue #2) |
| `pagination.pagerSize` | int | 10 | Stepper ≥1 |
| `pagination.path` | string | "page" | TextField |
| `pagination.disableAliases` | bool | false | Toggle |
| `canonifyURLs` | bool | false | Toggle |
| `relativeURLs` | bool | false | Toggle |
| `uglyURLs` | boolOrSectionMap | false | see §2.6 |
| `disablePathToLower` | bool | false | Toggle |
| `removePathAccents` | bool | false | Toggle |
| `disableAliases` | bool | false | Toggle |
| `enableRobotsTXT` | bool | false | Toggle |
| `sectionPagesMenu` | string | "" | TextField (menu name) |

### 3.4 Menus tab (bespoke, Phase 3)

Item fields (from `navigation.MenuConfig`): `name` (required in Victor's UI; Hugo can fall back to page title for pageRef entries), `url` XOR `pageRef`, `weight` int, `identifier`, `parent` (picker over sibling identifiers), `title` (tooltip text — newly editable, finding #8), preserved passthrough: `pre`, `post`, `params`. Drag-reorder writes `weight` in steps of 10. Menu names: free (main/footer typical). Spelling preservation per §2.7.

### 3.5 Markup tab

| Key | Type | D | Control/Validator |
|---|---|---|---|
| `markup.defaultMarkdownHandler` | choice | "goldmark" | goldmark/asciidocext/org/pandoc/rst — footnote that non-goldmark needs external tools |
| `markup.goldmark.renderer.unsafe` | bool | false | Toggle + security note (the #1 hand-edited key) |
| `markup.goldmark.renderer.hardWraps` | bool | false | Toggle |
| `markup.goldmark.renderer.xhtml` | bool | false | Advanced list only |
| `markup.goldmark.extensions.typographer.disable` | bool | false | Toggle (inverted label "Smart punctuation") |
| `markup.goldmark.extensions.table` | bool | true | Toggle |
| `markup.goldmark.extensions.strikethrough` | bool | true | Toggle |
| `markup.goldmark.extensions.linkify` | bool | true | Toggle |
| `markup.goldmark.extensions.linkifyProtocol` | choice | "https" | http/https |
| `markup.goldmark.extensions.taskList` | bool | true | Toggle |
| `markup.goldmark.extensions.definitionList` | bool | true | Toggle |
| `markup.goldmark.extensions.footnote.enable` | bool | true | Toggle |
| `markup.goldmark.parser.autoHeadingID` | bool | true | Toggle |
| `markup.goldmark.parser.autoIDType` | choice | "github" | §4.2 |
| `markup.goldmark.parser.attribute.title` | bool | true | Toggle |
| `markup.goldmark.parser.attribute.block` | bool | false | Toggle |
| `markup.highlight.style` | choice | "monokai" | searchable Picker, §4.5 (73 styles) |
| `markup.highlight.codeFences` | bool | true | Toggle |
| `markup.highlight.lineNos` | boolOrEnum(inline,table) | false | §2.6 |
| `markup.highlight.lineNumbersInTable` | bool | true | Toggle |
| `markup.highlight.lineNoStart` | int | 1 | Stepper ≥1 |
| `markup.highlight.noClasses` | bool | true | Toggle ("inline CSS") |
| `markup.highlight.tabWidth` | int | 4 | Stepper 1…16 |
| `markup.highlight.guessSyntax` | bool | false | Toggle |
| `markup.highlight.wrapperClass` | string | "highlight" | Advanced list only |
| `markup.tableOfContents.startLevel` | int | 2 | Stepper 1…6 |
| `markup.tableOfContents.endLevel` | int | 3 | Stepper 1…6, or -1 = all |
| `markup.tableOfContents.ordered` | bool | false | Toggle |

Schema-known but Advanced-list-only: goldmark `extensions.cjk.*`, `extensions.extras.*` (delete/insert/mark/subscript/superscript), `extensions.passthrough.*`, `renderHooks.{image,link}.useEmbedded` (choice: always/auto/fallback/never, D auto), `parser.wrapStandAloneImageWithinParagraph` (D true), `parser.autoDefinitionTermID` (D false), typographer's 10 punctuation-substitution strings, `footnote.enableAutoIDPrefix`/`backlinkHTML`, `markup.asciidocExt.*`, `markup.rst.*`.

### 3.6 Integrations tab

| Key | Type | D | Control |
|---|---|---|---|
| `services.googleAnalytics.ID` | string | "" | TextField, `G-`… hint — paired w/ privacy toggles |
| `privacy.googleAnalytics.disable` | bool | false | Toggle |
| `privacy.googleAnalytics.respectDoNotTrack` | bool | **true** | Toggle |
| `services.disqus.shortname` | string | "" | TextField |
| `privacy.disqus.disable` | bool | false | Toggle |
| `services.x.disableInlineCSS` | bool | false | Toggle |
| `privacy.x.disable` / `.enableDNT` / `.simple` | bool ×3 | false | Toggles |
| `privacy.youtube.disable` / `.privacyEnhanced` | bool ×2 | false | Toggles |
| `privacy.vimeo.disable` / `.enableDNT` / `.simple` | bool ×3 | false | Toggles |
| `privacy.instagram.disable` / `.simple` | bool ×2 | false | Toggles |
| `services.rss.limit` | int | sentinel -1 = unlimited | TextField, `intRange(-1…)` |
| `sitemap.changeFreq` | choice | "" (omit) | §4.6 |
| `sitemap.priority` | double | sentinel -1 = omit | TextField 0…1 or blank, `priorityRange` |
| `sitemap.filename` | string | "sitemap.xml" | TextField |
| `sitemap.disable` | bool | false | Toggle |
| `outputs.<kind>` | stringArray per kind | see §4.4 | bespoke matrix: rows home/section/taxonomy/term/page, checkbox per format, `outputFormatsKnown` |

### 3.7 Advanced tab

Three sections (design doc §3.2 stands):

**(a) Site Params** — recursive `DataDictionaryEditor` on `store.subtree("params")`.

**(b) All Settings** — searchable flat list of every schema entry not shown on other tabs. Root keys landing here (all verified in `RootConfig`): `defaultContentLanguageInSubdir` (D false), `defaultContentRole`, `defaultContentRoleInSubdir`, `defaultContentVersion`, `defaultContentVersionInSubdir`, `defaultOutputFormat` (D first format = html), `disableDefaultLanguageRedirect`, `disableDefaultSiteRedirect`, `disableHugoGeneratorInject`, `disableLanguages` (stringArray), `disableLiveReload`, `renderSegments` (stringArray), `enableMissingTranslationPlaceholders`, `templateMetrics`, `templateMetricsHints`, `noBuildLock`, `ignoreCache`, `ignoreLogs` (stringArray), `ignoreVendorPaths` (glob string), `panicOnWarning`, `printI18nWarnings`, `printPathWarnings`, `printUnusedTemplates`, `refLinksErrorLevel` (choice ERROR/WARNING, D ERROR), `refLinksNotFoundURL`, `newContentEditor`, `noChmod`, `noTimes`, `cleanDestinationDir`, `page.nextPrevSortOrder` + `page.nextPrevInSectionSortOrder` (choice asc/desc, D desc), `related.threshold` (D 80) / `related.includeNewer` (D false) / `related.toLower` (D false), `minify.minifyOutput` (D false) + `minify.disable{HTML,CSS,JS,JSON,SVG,XML}`, `imaging.quality` (D 75) / `imaging.resampleFilter` (D "box") / `imaging.hint` (D "photo") / `imaging.anchor` (D "smart") / `imaging.bgColor` (D "#ffffff", `hexColor`), and directory overrides `archetypeDir`/`assetDir`/`cacheDir`/`contentDir`/`dataDir`/`i18nDir`/`layoutDir`/`publishDir`/`resourceDir`/`staticDir` (stringOrStringArray)/`themesDir` with their standard defaults. Deprecated-but-schema'd: `author`, `social`, `ignoreFiles`, `staticDir0…10`, `privacy.twitter.*`, `services.twitter.*`.

**(c) Unknown keys** — anything in the store matching no schema entry and no rawOnly section: recursive editor, same as params.

**Raw-only sections** (listed read-only with "Edit in Raw", schema entries of type `rawOnly`): `build`, `caches`, `httpcache`, `cascade`, `deployment`, `frontmatter`, `languages`, `mediatypes`, `contenttypes`, `module`, `outputformats`, `related.indices`, `roles`, `security`, `segments`, `server`, `versions`, `minify.tdewolff`, `imaging.exif`.

---

## 4. Enum Catalogs

1. **titleCaseStyle** (case-insensitive; unknown ⇒ AP): `ap`, `chicago`, `go`, `firstupper`, `none`.
2. **autoIDType**: `github`, `github-ascii`, `blackfriday`.
3. **Page kinds** (for `disableKinds` / `outputs` rows): `page`, `home`, `section`, `taxonomy`, `term`, plus temporary kinds `rss`, `sitemap`, `sitemapindex`, `robotstxt`, `404`. (Pre-0.73 spellings `taxonomy`/`taxonomyTerm` swap is handled by Hugo with a deprecation — lint, don't offer.)
4. **Built-in output format names**: `html`, `rss`, `amp`, `alias`, `calendar`, `css`, `csv`, `json`, `markdown`, `robots`, `sitemap`, `sitemapindex`, `webappmanifest`. Default `outputs`: page=[html]; home/section/taxonomy/term=[html, rss].
5. **Chroma styles** (v2.27.0, 73): abap, algol, algol_nu, arduino, ashen, aura-theme-dark, aura-theme-dark-soft, autumn, average, base16-snazzy, borland, bw, catppuccin-frappe, catppuccin-latte, catppuccin-macchiato, catppuccin-mocha, colorful, darcula, doom-one, doom-one2, dracula, emacs, evergarden, friendly, fruity, github, github-dark, gruvbox, gruvbox-light, hr_high_contrast, hrdark, igor, kanagawa-dragon, kanagawa-lotus, kanagawa-wave, lovelace, manni, modus-operandi, modus-vivendi, monokai, monokailight, murphy, native, nord, nordic, onedark, onesenterprise, paraiso-dark, paraiso-light, pastie, perldoc, pygments, rainbow_dash, rose-pine, rose-pine-dawn, rose-pine-moon, rpgle, rrt, solarized-dark, solarized-dark256, solarized-light, swapoff, tango, tokyonight-day, tokyonight-moon, tokyonight-night, tokyonight-storm, trac, vim, vs, vulcan, witchhazel, xcode, xcode-dark.
6. **sitemap.changeFreq**: "", `always`, `hourly`, `daily`, `weekly`, `monthly`, `yearly`, `never`.
7. **renderHooks useEmbedded**: `always`, `auto`, `fallback`, `never` (D `auto`).
8. **lineNos**: `false`, `true`, `"inline"`, `"table"`.
9. **page sort orders**: `asc`, `desc`.

---

## 5. Test Plan

**Phase 0 (extend `HugoConfigParserTests`)** — all TDD, red first:
- Minimal 3-line TOML config: change title → save → key set is exactly {baseURL, title, +changed}. Same for YAML and JSON. (Kills issue #1.)
- Config explicitly declaring default taxonomies round-trips them. (Issue #2.)
- `menus`-spelled config keeps `menus`; `menu`-spelled keeps `menu`. (Issue #3.)
- YAML config with menus → parse yields items (currently-failing test for issue #4; fixed structurally by store normalization or, if Phase 0 lands before the store, by a targeted normalize in menus parsing).
- Menu item with `title`/`pre`/`post`/`params` round-trips all fields. (Finding #8.)
- `findConfigFile` discovers `hugo.yml` and `config.yml`; precedence hugo.* > config.*. (Finding #7.)

**Phase 1 — `ConfigValueStoreTests`**: key-path get/set/remove incl. intermediate-dict creation and empty-parent pruning; presence semantics; lenient-read coercions ("true"/1/true); Yams `[AnyHashable: Any]` normalization at construction; snapshot round-trip through all three formats; root key-order preservation.

**Phase 1 — `ConfigSchemaTests`** (table invariants): keys unique + non-empty; every `.choice` non-empty; every group renders somewhere; defaults type-match their declared `ConfigValueType`; deprecated entries have messages; no schema key collides with a rawOnly section prefix; spot-check ~10 known defaults against this spec (guards accidental edits).

**Phase 1 — `HugoConfigTests` additions**: computed-accessor compatibility (set `buildDrafts` → present in store → serialized; absent key reads Hugo default); `hasUnsavedChanges` transitions still fire exactly on commit (typing-latency contract, mirrors `EditableEditorTests` style).

**Phases 2–5**: per-tab logic tests only where there's logic (outputs matrix set/unset, menus weight rewrite on reorder, deprecation rename affordance moves value) — view plumbing is covered by the existing UI-test-free convention.

## 6. Phase Mapping (deltas vs. design doc §4)

- **Phase 0 grows two items**: `.yml` discovery (finding #7) and menu-item field passthrough (finding #8) — both small, both round-trip correctness, both testable without UI. Permalink token additions (finding #9) can ride along (token list + resolver + lint), or slip to Phase 5 with the other lints; recommend Phase 0 since `PermalinkResolver` changes are isolated.
- **Phase 1 order of work**: store + normalization → schema table (§3, mechanical) → `HugoConfig` computed-accessor migration (tests green checkpoint) → `ConfigFieldView` → re-plumb existing 4 tabs. The schema table is big but is data entry against this spec — good candidate to draft off-Mac; everything after needs the build.
- Phases 2–5 unchanged. Phase 6 (config dir, languages, modules) unchanged — note `config/_default` discovery will also want `configLoader.go`'s rule that *any* `hugo.*`/`config.*` in `config/_default/` wins over root files.

## 7. Resolved Questions

### 7.1 locale vs languageCode (design doc §5, resolved)

One **"Locale"** row in Essentials, not two fields:
- Displays `locale` if present, else `languageCode` (matching Hugo's read-side migration), with a "from languageCode (deprecated)" badge in the latter case + one-click `[Rename key to locale]`.
- Edits write back to **whichever key the file has** (respecting sparse honesty — no silent renames, same principle as menus spelling); files with neither write `locale`.
- If *both* are present, `locale` wins (Hugo ignores `languageCode` then); show a lint suggesting removal of `languageCode`.
- Rationale: themes' README-driven `languageCode` usage doesn't need Victor to *offer* the deprecated key — it needs Victor not to break files that have it. This does both.

### 7.2 Still open (unchanged, non-blocking)

- Comment/ordering loss on form save: accepted limitation; §2.7 narrows it (root key order kept, diff minimized by sparseness). UI copy: "form saves rewrite the file".
- Schema drift across Hugo releases: static table pinned to v0.164.0; unknown keys degrade to Advanced editor, never data loss. Re-verify per Hugo minor by re-running the source diff (the research method above is repeatable: pull the new version from the Go module proxy, diff `RootConfig`, `newDefaultConfig`, section defaults).
