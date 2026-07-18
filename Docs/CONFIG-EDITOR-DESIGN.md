# Config Editor v2 — Coverage Review & Design

**Status**: Draft for review | **Date**: 2026-07-19 | **Hugo baseline**: v0.164.0 (docs reviewed 2026-07-19)

Review of Victor's Hugo config GUI (`ConfigEditorView` + 4 tabs, `HugoConfig`, `HugoConfigParser`) against Hugo's current configuration surface, plus a phased plan to close the gap.

---

## 1. Current Coverage

### What Hugo has (v0.164.0)

- **~70 root settings** (`gohugo.io/configuration/all/`)
- **29 nested sections**: build, caches, cascade, deployment, frontmatter, HTTPCache, imaging, languages, markup, mediaTypes, menus, minify, module, outputFormats, outputs, page, pagination, params, permalinks, privacy, related, roles, security, segments, server, services, sitemap, taxonomies, versions

### What Victor exposes

| Category | Settings | Where | Quality |
|---|---|---|---|
| Editable root scalars (13) | baseURL, title, languageCode, theme, copyright, buildDrafts, buildFuture, buildExpired, enableRobotsTXT, summaryLength, defaultContentLanguage, timeZone | Essentials / Content / Advanced tabs | Plain text fields; no validation except non-empty |
| taxonomies | add/remove singular→plural pairs | Taxonomies tab | No edit-in-place, no validation |
| permalinks | add/edit/remove per-section patterns | Content tab | **Good** — token menu, `PermalinkResolver` validation. The reference standard for the rest |
| menus | — | none | Parsed into `HugoConfig.menus` + serialized, but **no UI**. (`MenusTab.swift` is frontmatter menus, unrelated) |
| params | read-only rows | Advanced tab | Collapsed to `{1 fields}` / `[2 items]` — the complaint this doc exists for |
| customFields (everything else) | read-only rows | Advanced tab | Same collapsed formatting |

**Coverage: 13 of ~70 root settings editable; 3 of 29 nested sections.** Everything else round-trips through `customFields` invisibly — the user must switch to Raw mode to even *see* it.

### Notable absences, weighted by real-world use

High-frequency (nearly every non-trivial site touches these):

- **`markup`** — `goldmark.renderer.unsafe` is the single most hand-edited Hugo setting (raw HTML in Markdown); also code highlighting (`highlight.style`, `lineNos`, `tabWidth`), TOC levels (`tableOfContents.startLevel/endLevel`)
- **`pagination`** — `pagerSize` (replaced root `paginate`, which Hugo removed)
- **`menus`** — model exists, UI missing
- **`services`** — `googleAnalytics.ID`, `disqus.shortname`
- **`outputs`** — per-kind output formats (RSS/JSON feeds)
- **Root**: `enableGitInfo`, `enableEmoji`, `mainSections`, `hasCJKLanguage`, `canonifyURLs`/`relativeURLs`, `disableKinds`, `titleCaseStyle`, `pluralizeListTitles`/`capitalizeListTitles`

Medium: `sitemap`, `privacy`, `related`, `frontmatter`, `imaging`, `minify`, `server`, `module` (imports/mounts), `languages` (multilingual). Low (leave to Raw mode): caches, security, mediaTypes, outputFormats, deployment, segments, HTTPCache, roles, versions, build.

### Validation gaps

- `baseURL`: not checked as absolute URL with trailing slash
- `languageCode`: free text; also **deprecated since Hugo v0.158** in favor of `locale` — the Essentials tab presents a deprecated key as core
- `timeZone`: free text; `TimeZone.knownTimeZoneIdentifiers` gives us a native picker for free
- `theme`: free text; not checked against `themes/` directory contents
- `taxonomies`: no duplicate/format checks
- Only `permalinks` has real validation

---

## 2. Correctness Issues in the Existing Round-Trip

These predate this feature but the redesign must fix them; they are why "just add more fields" isn't safe today.

1. **Serialization injects keys the user never set.** `HugoConfigParser.serialize()` unconditionally writes `buildDrafts`, `buildFuture`, `buildExpired`, `enableRobotsTXT`, `summaryLength`, `defaultContentLanguage`. Open a minimal 3-line `hugo.toml`, change the title, save → 6 extra keys appear in the file.
2. **Explicit default taxonomies get deleted.** `serialize()` drops `taxonomies` when it equals `{category: categories, tag: tags}` — even when the user's file declared them explicitly.
3. **`menus` → `menu` normalization.** Both spellings parse, but we always serialize `menu`, silently renaming the user's key.
4. **YAML `menus` parsing is fragile (verify).** `HugoConfig.init(from:)` casts `dictionary["menus"] as? [String: [[String: Any]]]`; Yams produces `[AnyHashable: Any]` nesting, which the permalinks parser special-cases but menus does not. Needs a failing test to confirm.
5. **No config-directory support.** `findConfigFile()` only handles root-level `hugo.*`/`config.*`. Sites using `config/_default/*.toml` (+ environment overlays) get no config GUI at all.
6. **Comments and key order are destroyed on save** (full-file regenerate). Inherent to the current approach; called out in §5 as an accepted limitation with a future option.

---

## 3. Design

### 3.1 Core decision: schema-driven, sparse-by-default

Hardcoding ~70 more `var` fields on `HugoConfig` + bespoke tab views does not scale and reproduces issue #1 at 5× the size. Instead:

**A declarative `ConfigSchema`** — one table describing every known setting:

```swift
struct ConfigSettingSpec {
    let key: String                 // "enableGitInfo", "markup.goldmark.renderer.unsafe"
    let type: ConfigValueType       // .bool, .string, .int, .stringArray, .duration, .enum([...])
    let defaultValue: Any?          // Hugo's default — shown as placeholder, never written
    let label: String
    let help: String                // one-liner from Hugo docs
    let group: ConfigGroup          // which tab/section it renders in
    let validator: ConfigValidator? // url, languageTag, timezone, positiveInt, chromaStyle…
    let deprecation: String?        // "Use locale instead (Hugo 0.158+)"
}
```

**A sparse value store instead of typed fields.** `HugoConfig` keeps the parsed `[String: Any]` (with key-path access for nested sections) and tracks *presence*: a setting the file doesn't define renders its Hugo default as grayed placeholder text and is **never written on save**. Setting a value inserts the key; a "reset to default" affordance removes it. This kills issue #1 structurally and makes the form honest about what's actually in the file.

**Generic renderer.** `ConfigFieldView(spec:store:)` maps `ConfigValueType` → control (Toggle, TextField with format, Stepper, Picker for enums, token list for string arrays). Tabs become mostly declarative lists of specs. Bespoke views remain only where interaction is genuinely custom: permalinks (exists), taxonomies (exists), menus, outputs matrix, languages.

**Typed fields on `HugoConfig` shrink, not grow.** Existing 13 fields migrate onto the store behind computed accessors so current tests/views keep working during the transition; new settings never get dedicated stored properties.

### 3.2 Tab layout (form mode)

| Tab | Contents |
|---|---|
| **Essentials** | baseURL (URL-validated), title, theme (picker populated from `themes/` + free text for modules), copyright, locale (with languageCode deprecation note), defaultContentLanguage, timeZone (picker) |
| **Content & Build** | build drafts/future/expired, enableGitInfo, enableEmoji, hasCJKLanguage, summaryLength, mainSections, titleCaseStyle (enum picker: ap/chicago/go/firstupper/none), pluralizeListTitles, capitalizeListTitles, timeout, disableKinds (multi-token) |
| **URLs & Taxonomies** | permalinks (existing), taxonomies (existing, + edit-in-place), pagination (pagerSize/path/disableAliases), canonifyURLs, relativeURLs, uglyURLs, disablePathToLower, removePathAccents, enableRobotsTXT |
| **Menus** *(new)* | Per-menu item list: name, url/pageRef, weight, identifier, parent (nesting), drag-reorder; adapt patterns from frontmatter `MenusTab` |
| **Markup** *(new)* | goldmark: renderer.unsafe (with security note), extensions toggles (typographer, linkify, strikethrough, table, taskList); highlight: style (chroma enum picker), lineNos, lineNumbersInTable, tabWidth, noClasses; tableOfContents: startLevel/endLevel/ordered |
| **Integrations** *(new)* | services (googleAnalytics.ID, disqus.shortname, x/instagram/youtube) side-by-side with matching privacy toggles; sitemap (changeFreq/priority/filename); outputs per-kind format checkboxes |
| **Advanced** | (a) **Site Params: full recursive editor** — reuse the `DataDictionaryEditor`/`DataArrayEditor`/`DataValueEditor` family from the data-file editor, extracted to a shared component. No more `{1 fields}`. (b) **All Settings**: searchable flat list of every schema entry not surfaced on other tabs, typed editors, defaults as placeholders (about:config style). (c) Unknown keys: same recursive editor as params |

Sections intentionally left Raw-only: caches, security, mediaTypes, outputFormats, deployment, build, segments, HTTPCache, module mounts, roles/versions. They appear in the Advanced list read-only with an "Edit in Raw" affordance rather than silently hidden.

### 3.3 Validation model

- Validators run per-field, render as inline warnings (permalinks pattern today) — **warning, not blocking**: Hugo itself is tolerant, and we must never refuse to save a file Hugo would accept.
- Deprecation warnings from schema: `languageCode` → `locale`; root `paginate` → `pagination.pagerSize`; root `googleAnalytics` → `services.googleAnalytics.ID`.
- Cross-cutting: warn (not block) when a key Hugo removed/renamed appears in `customFields` — the schema doubles as the lint table.

---

## 4. Implementation Phases

TDD throughout; each phase lands green and shippable. Test files: extend `HugoConfigParserTests`, new `ConfigSchemaTests`, `ConfigValueStoreTests`.

**Phase 0 — Round-trip correctness (no UI change)**
Sparse serialization (write only keys present-in-file or user-set); preserve explicit default taxonomies; preserve `menu` vs `menus` spelling; failing test for YAML menus → fix; tests asserting a minimal config round-trips byte-identical in key set.
*This is a prerequisite: every later phase multiplies the blast radius of issue #1 if unfixed.*

**Phase 1 — Schema infrastructure**
`ConfigSettingSpec`/`ConfigValueType`/`ConfigValidator`, key-path get/set over the sparse store, `ConfigFieldView` renderer, presence tracking + placeholder rendering + reset-to-default. Migrate the existing 13 fields and 4 tabs onto it (UI looks ~identical after; behavior now sparse).

**Phase 2 — Advanced tab done right** *(the stated pain point)*
Extract `DataDictionaryEditor` family into `Views/Components/`; wire recursive editing for `params` and unknown fields; add searchable All Settings list from the schema.

**Phase 3 — Menus tab** (model already exists; UI + reorder + parent nesting).

**Phase 4 — Markup tab** (goldmark/highlight/TOC specs + chroma style list).

**Phase 5 — URLs additions, Integrations tab** (pagination, services+privacy, sitemap, outputs matrix), theme/timezone pickers, deprecation lints.

**Phase 6 — Deferred, separate specs when wanted**
Config directory (`config/_default` + environments) — touches site loading, merge semantics, and "which file does a form edit write to"; multilingual `languages` editor; module imports/mounts GUI.

Rough sizing: P0 small; P1 the big architectural lift; P2–P5 each a focused view-layer chunk once P1 exists.

---

## 5. Accepted Limitations / Open Questions

- **Comment & ordering loss on form-mode save** stays (full regenerate via Yams/TOMLKit). Sparse writing shrinks the diff but doesn't preserve comments. Future option: surgical text edits keyed off the parsed AST — out of scope; note in UI copy ("form saves rewrite the file").
- **Schema drift vs Hugo releases**: schema is a static table pinned to a Hugo version; unknown keys still round-trip safely, so drift degrades to "shows in Advanced" not data loss. Revisit per Hugo minor.
- **Open**: should Essentials show `locale` or keep `languageCode` primary while most themes still document the latter? Current lean: show both, deprecation note on languageCode.
