# Config Editor v2 Phase 6 — Config Directories, Languages, Modules

**Status**: Design only, not yet implementable as written — each area needs a Hugo-source verification pass (see §0) before a schema/architecture doc like `CONFIG-SCHEMA-SPEC.md` can be written for it | **Date**: 2026-07-20 | **Companion to**: `CONFIG-EDITOR-DESIGN.md` (§4 names this "Phase 6 — Deferred, separate specs when wanted"), `CONFIG-SCHEMA-SPEC.md` (the shipped Phases 0–5 architecture this design extends)

**Tracking issues**: [#52](https://github.com/karanj/victor/issues/52) (§1, config directories/environments) · [#53](https://github.com/karanj/victor/issues/53) (§2, languages editor) · [#54](https://github.com/karanj/victor/issues/54) (§3, module GUI)

Phases 0–5 shipped a schema-driven editor (`ConfigValueStore`, `ConfigSchema`, `ConfigFieldView`) for **one config file**: parse it, edit it, serialize it back to the same file. That assumption is load-bearing — presence tracking, the single write path, sparse serialization all depend on "the file" being singular. The three areas below each break that assumption differently, which is why they were deferred rather than folded into Phase 5: each needs its own design decision before it can become a schema table, not just more view code.

This doc breaks them out, names the concrete design question each one hinges on, and proposes a phased approach. It does not commit to field-level schemas — that's the next doc, per-area, once §0's research is done.

---

## 0. Required before any implementation: source verification

Every prior spec in this program (`CONFIG-SCHEMA-SPEC.md` §1) was verified against Hugo's actual source via the Go module proxy, not docs prose — that's why Phases 0–5 shipped without a single "we assumed wrong" bug. This doc does **not** do that yet. Where a mechanism below is stated as fact, it's my best recollection of Hugo's behavior and should be treated as a hypothesis to verify, not a spec to build against. Flagged inline as **[VERIFY]**.

The three areas need different source packages:
- Config directories/environments: `config/configLoader.go`, `config/loadConfig` merge logic, `hugoinfo`/`environment` resolution
- Languages: `langs/`, `config/allconfig` per-language decoding, how `languages.<code>.*` overlays root keys during effective-config resolution
- Modules: `modules/` (module graph, mounts, imports), `hugofs/` (mount resolution), the `hugo mod *` command implementations in `commands/`

---

## 1. Config Directories & Environment Overlays

### 1.1 What Hugo does (as I understand it — verify before building)

Hugo supports two mutually-exclusive config shapes: a single root file (`hugo.toml`/`.yaml`/`.json`, what Victor edits today) or a `config/` directory (name configurable via `--configDir`, default `config`). **[VERIFY]** whether a root file and a `config/` directory can coexist, or whether the directory's presence makes Hugo ignore the root file entirely — this determines whether Victor's existing `findConfigFile` needs to *also* check for a config directory or needs to prefer one over the other.

Inside `config/`:
- `config/_default/` — the base layer. Can be one file (`config/_default/hugo.toml`) or split across many (`hugo.toml`, `params.toml`, `menus.toml`, …) — **[VERIFY]** the exact split convention and whether Hugo cares which basename holds which section, or whether it just merges every file in the directory regardless of name.
- `config/<environment>/` — an overlay layer, environment resolved from `--environment`/`HUGO_ENVIRONMENT`, defaulting to `production` for `hugo build` and `development` for `hugo server`. **[VERIFY]** the merge algorithm precisely: my recollection is deep-merge for map-typed sections (`params`, nested tables) — overlay keys win, non-overlapping base keys survive — and outright replacement for scalars and arrays, but Hugo may use `mergo` transformers that special-case specific sections (e.g. `params`) differently from others. This is the single fact this whole area's design depends on, and I do not have high confidence in it.
- **[VERIFY]** whether there's also a per-language split inside the directory shape (`config/_default/languages/en.toml` or similar) — if so it interacts with Area 2 below.

### 1.2 Why this is hard for Victor, specifically

Not the reading — the **writing**. Today, "edit `buildDrafts`" means "there is exactly one file, and the key goes in it." Under directory-mode config, the *effective* value of `buildDrafts` the user sees while running `hugo server` might come from `_default/hugo.toml`, be overridden by `production/hugo.toml`, and the form has no way to say which of those the user means to change. Silently picking one is how you get an editor that "saves" but doesn't affect the running site, or that pollutes an environment overlay with a value that belonged in `_default`. This is a correctness question, not a UI one — get it wrong and Victor becomes the thing CLAUDE.md's round-trip-correctness section (design doc §2) was written to prevent, just at file-selection granularity instead of key granularity.

Sites using this shape get **no config GUI today** (`findConfigFile` returns nil, they fall through to whatever Victor does for "no config found" — worth confirming that fallback is graceful). That's the honest current state: not wrong, just absent.

### 1.3 The read side is nearly free — use it

Victor already resolves and spawns a `hugo` binary (`HugoServerService.swift`) for the live-preview server. Hugo has a `hugo config` command that dumps the fully-merged effective configuration. **[VERIFY]** exact flags (`--format json` or similar) and whether it's available as a library call vs. requiring a subprocess — but if it works as I expect, Victor gets correct effective-value display **without reimplementing Hugo's merge algorithm at all**. That's a meaningfully different, much lower-risk design than "Victor re-derives what Hugo would compute."

This suggests splitting the problem cleanly:
- **Read (effective view)**: shell out to `hugo config`, display the merged result read-only, exactly like Hugo sees it. Low risk, no merge-logic reimplementation, reuses existing subprocess infrastructure.
- **Write (edit target)**: never edited implicitly. The user explicitly picks which physical file a change goes into.

### 1.4 Design options for the write-target question

None of these are chosen yet — this needs a product decision, not just an engineering one, since it changes what the feature *is*.

**Option A — File picker, no merge-awareness.** Sidebar or menu shows every config file (`_default/*`, `<environment>/*`) as its own editable document, using the existing single-file `ConfigValueStore`/`ConfigFieldView` machinery unchanged — each file IS one store, same as today. No new architecture; the only gap is a UI to switch between files and (via §1.3) a read-only "effective value" hint next to each field showing what wins after merge. Cheapest to build, least magical, most honest about what's actually happening — matches this program's general bias (§2.7's "sparse honesty" principle) toward showing users the truth rather than a synthesized view.

**Option B — Unified form, explicit per-field target.** One form (today's tabs), but each field gets a "which file" selector when directory-mode is active, defaulting to `_default` unless the field already has an environment-specific override. Requires `ConfigValueStore` to become multi-file-aware (or requires N stores + a field-level router in front of `ConfigFieldView`) — meaningfully more architecture, but closer to "one config editor" as a mental model.

**Option C — Environment-scoped editing session.** User picks an environment to "edit as" (default: production); the form shows/writes that environment's overlay file only, with effective-value hints for inherited fields. A middle ground between A and B — one file per session instead of one file per field, but still requires surfacing "this write creates a new environment-overlay key" clearly (writing to an overlay file for a key that previously only existed in `_default` is a meaningfully different action than editing an existing key, and the sparse-serialization principle says that distinction must stay visible, not be hidden behind convenience).

My inclination is **A first** — it's a straight application of what's already built (Phase 0–5's single-file store, N times), ships the "sites in this shape finally get *a* GUI" value fastest, and the effective-value hint (§1.3) covers most of what B/C would add, without B/C's new failure mode of writing to the wrong file by mistake. B/C become worth it only if user feedback says switching files by hand is the actual pain point, not merge visibility.

### 1.5 Phased approach (once source-verified)

1. **Discovery**: extend `findConfigFile`-equivalent logic to detect directory-mode; list every file in `_default/` + all environment subdirectories.
2. **Read-only effective view**: `hugo config` subprocess call + display (§1.3) — ships value with zero write-path risk, de-risks the merge-semantics uncertainty since Victor never has to get it right itself.
3. **Option A file picker**: each file opens in the existing form/raw editor unchanged. This is the "sites in this shape get a GUI" milestone.
4. Revisit B/C only if A proves insufficient in practice.

### 1.6 Open questions for whoever picks this up

- Root file + directory coexistence — resolves whether `findConfigFile` needs an either/or or an and.
- Exact merge algorithm per section type — resolves what the "effective value" hint can promise to be accurate about.
- Whether `hugo config`'s output is stable/parseable enough to trust for the hint, or whether it needs to be treated as best-effort/advisory only.

---

## 2. Multilingual `languages` Editor

### 2.1 What Hugo does (as I understand it — verify before building)

A `languages` config section, keyed by language code, where each language can override — via `languages.<code>.*` — a large fraction of the root schema: `title`, `params`, `menus`, `taxonomies`, `weight`, `label` (formerly `languageName`, per `CONFIG-SCHEMA-SPEC.md` §1.2's already-verified finding on that rename), `direction`, and more. **[VERIFY]** the precise set of overridable keys and whether it's "any root key" or an enumerated subset — this directly determines whether the Phase 6 languages editor can be schema-driven at all, or needs its own allowlist.

Root-level keys `defaultContentLanguage`, `defaultContentLanguageInSubdir`, `disableLanguages` are already in `ConfigSchema` (Phase 1b, Advanced-list-only) and don't need new work.

### 2.2 Why this is hard

It isn't a new tab's worth of new fields — it's most of the *existing* tabs' fields, again, N times, under a language scope. A naive build would duplicate every `ConfigFieldView` row already on Essentials/Content/Markup/Menus under a `languages.<code>.` prefix, which both bloats the UI and — worse — drifts from the single-tab versions as the schema evolves, since the same 30+ fields would exist in two places.

### 2.3 Design direction worth prototyping first: a scoped store, not new UI

`ConfigValueStore`'s key-path API (`value(at:)`, `set(_:at:)`) already takes a dotted path string — nothing about `ConfigFieldView` cares whether that path is `"buildDrafts"` or `"languages.de.buildDrafts"`. That suggests a **`ScopedConfigValueStore`** (name provisional): wraps the real store, prefixes every path with `languages.<code>.` on write, and on *read* falls back to the unprefixed root key when the scoped key is absent (matching Hugo's own override-not-replace semantics — **[VERIFY]** that root-level fallback is actually how Hugo resolves an unset per-language key, versus the per-language value being required/defaulted independently).

If that read/write contract holds, the existing tabs become reusable almost unchanged: a language picker sets which store instance flows into the same `ConfigEssentialsTab`/`ConfigContentTab`/etc., and `ConfigFieldView` doesn't need to know it's operating on an overlay. This is the single biggest leverage point in this whole document — worth a small spike (build `ScopedConfigValueStore`, point one existing tab at it, confirm it round-trips) before committing to the phased plan below, because if it doesn't hold up, the alternative is a second, parallel field-rendering system.

Two things this direction does NOT solve and need separate design: per-language **menus** (Menus tab's `commitMenus()` single-write-path assumes one `menus` dict — a language-scoped menu needs either a second typed materialization or a scope parameter threaded through `HugoConfig`), and per-language **taxonomies** (similarly bespoke, similarly not store-driven yet).

### 2.4 Phased approach (once §2.3's spike is validated)

1. Spike: `ScopedConfigValueStore`, prove it against one field on one existing tab.
2. Language list management: add/remove/reorder languages (`weight`), each with its own `label`/`direction`/`defaultContentLanguage` wiring.
3. Wire the scoped store into Essentials/Content tabs per selected language — reuses existing `ConfigFieldView` rows.
4. Markup tab, same pattern, once 3 is proven.
5. Menus and Taxonomies: bespoke, scoped versions of the existing bespoke editors — separate design needed, not a mechanical extension of 3.

### 2.5 Open questions

- Exact overridable-key set (§2.1) — determines whether step 3/4 can iterate "every schema entry" or need an allowlist.
- Fallback semantics (§2.3) — determines whether the scoped-store idea is even correct, not just convenient.
- UX for "this field's language-scoped value is unset, showing the root value" vs. "this field has no per-language override *concept* at all" — these need to look different, or users will try to override things Hugo doesn't let vary per language.

---

## 3. Module Imports/Mounts GUI

### 3.1 What Hugo does (as I understand it — verify before building)

The `module` config section: `module.imports` (a list of imported modules — theme components, each with a `path` and optional per-import `mounts` overrides and a `disable` flag), `module.mounts` (this site's own source→target directory mounts), and version-constraint fields under `module.hugoVersion`. **[VERIFY]** the exact field names/nesting — the spec's Phase 1 schema deliberately left `module` as a `rawOnly` section (`CONFIG-SCHEMA-SPEC.md` §3.7) precisely because this wasn't verified, and `themeExists`'s validator already special-cases skipping its check when `module` is present, since module-sourced themes aren't sitting in `themes/` on disk.

Hugo Modules are Go-modules-backed (`go.mod`/`go.sum` at the site root when modules are in use), with CLI subcommands `hugo mod get`, `hugo mod tidy`, `hugo mod vendor`, `hugo mod graph`. **[VERIFY]** which of these are pure-local (editing `go.mod`/config only) versus network-fetching.

### 3.2 Why this is hard — and different in kind from Areas 1–2

Areas 1 and 2 are both "more of the same store/schema architecture, applied to a trickier shape." Modules is different: **editing `module.imports` in config is often not sufficient by itself** — adding an import typically implies running `hugo mod get` to fetch it and update the lockfile-equivalent state, which is a network operation with real side effects (fetching arbitrary remote code, per Hugo's Go-modules design) outside the config file entirely. That crosses from "form-edits-a-file" into "form-triggers-a-subprocess-with-external-effects," which is a materially different risk profile — this needs explicit user confirmation before any such command runs, consistent with this codebase's general instruction to confirm before hard-to-reverse or outward-facing actions, and is *not* comparable to the read-only `hugo config` call proposed in §1.3.

### 3.3 Design direction

Split by risk, same instinct as §1.3:

- **Mounts** (`module.mounts`, this site's own source/target directories) are pure local config — no network implication, no subprocess needed. This is schema-and-form work like any Phase 1–5 tab: add it to `ConfigSchema`, build a bespoke mounts-list editor (add/remove/reorder source→target pairs), done. Lowest risk, ships first.
- **Imports** (`module.imports`, pulling in remote modules) split further:
  - *Editing/removing/reordering an existing import*, or toggling its `disable` flag — pure config edit, no network call needed (the module is already fetched/resolved; you're just changing whether/how it's used).
  - *Adding a new import* — very likely needs `hugo mod get` (or the user needs to be told to run it themselves) to actually resolve and fetch the thing before the site will build. This should probably not be silent: either Victor shells out with an explicit confirm-first prompt naming exactly what will be fetched, or Victor writes the config change and tells the user to run `hugo mod get` themselves, matching how it already treats other consequential file operations.
- **Version constraints / graph inspection** — read-only display (`hugo mod graph`) is safe and useful; no write path needed initially.

### 3.4 Phased approach (once source-verified)

1. `module.mounts` editor — pure config, no subprocess risk, schema-driven like existing tabs.
2. Existing-import list: view/reorder/disable/remove, still pure config.
3. Read-only `hugo mod graph` display for diagnostics — "what's actually resolved right now."
4. New-import flow — the one piece with a network/subprocess decision to make; do this last, and treat the confirm-before-fetch UX as its own design question, not an afterthought.

### 3.5 Open questions

- Exact schema (§3.1) — blocks even step 1 until verified.
- Whether `hugo mod get`/`tidy` can target a single import surgically or always operates site-wide (affects how granular a "confirm this fetch" prompt can be).
- Whether Victor should ever run `hugo mod get` itself, versus always deferring the actual fetch to the user running it in a terminal (config-only edit + instructions) — this is a product risk-appetite question, not an engineering one.

---

## 4. Sequencing recommendation across the three

Independent of each other technically (no area blocks another), but the effort-to-value ratio differs:

1. **Config Directories §1**, Option A — the read-only `hugo config` view alone (§1.3, step 2 of §1.5) is low-risk and unblocks sites that currently have *zero* config GUI, which is the sharpest gap of the three.
2. **Languages §2** — highest leverage *if* the `ScopedConfigValueStore` spike (§2.3) pans out, since it reuses nearly all existing tab code; do the spike before committing to a full phased plan.
3. **Modules §3, mounts only** — cheap, schema-driven, no new risk class; the imports/fetch piece is the most product-judgment-dependent item in this whole document and should be scoped separately once mounts ships and the confirm-before-fetch UX has been thought through on its own.

## 5. Non-goals (explicitly out of scope for all three areas, this round)

- Reimplementing Hugo's config-merge algorithm in Swift (§1.3's whole point is not doing this)
- Any write path that runs a Hugo subprocess without an explicit, named, confirm-first user action (§3.2)
- Comment/formatting preservation across any of these (already an accepted limitation for the single-file case per `CONFIG-SCHEMA-SPEC.md` §7.2, doesn't get harder here, doesn't get solved here either)
