# Mac Polish Design — Making Victor a Mac-assed Mac App

**Date:** 2026-07-03 · **Status:** Proposed · **Target:** macOS 14.0+ (current deployment target)

## Goal

Make Victor behave like software built *for* the Mac, not a cross-platform app
that happens to run on one. Concretely: platform conventions users expect
(proxy icons, Open Recent, drag-and-drop, Quick Look, complete menus), a
keyboard-first workflow, and system integration (Dock, Notifications,
menu bar) — all within what SwiftUI on macOS 14 allows, bridging to AppKit
only where SwiftUI has no API.

### In scope
Window chrome, menu bar completeness, Dock integration, drag-and-drop, Quick
Look, notifications, keyboard navigation, visual/motion polish, and the
document-like behaviors a folder-based CMS can honestly support.

### Out of scope (deliberate)
- **iCloud/sync, Handoff, Spotlight indexing** — Hugo sites are git repos; sync is git's job.
- **NSDocument architecture** — Victor is a folder-based site editor, not a document app. We borrow document *conventions* (proxy icon, edited dot) without adopting NSDocument.
- **Sparkle/updates, notarized distribution pipeline** — release engineering, separate effort.
- **Editor feature work** — tabs (victor-tab), breadcrumbs (victor-bcr), quick open (victor-qop), line numbers (victor-lnr), session restore (victor-trs), cursor restore (victor-csr), themes (victor-thm) are already ticketed. This doc references them for sequencing but does not respecify them.
- **Localization** — English-only until the UI stabilizes.

## Current state audit (what exists today)

| Area | State |
|------|-------|
| Window | `WindowGroup` + `Window("Server Logs")`, min/default sizes set, title = site name only |
| Toolbar | Static `.toolbar` in ContentView; not user-customizable; no `.toolbar(id:)` |
| Menus | Find/Format/View commands wired via `@FocusedValue`; File menu has only "Open Hugo Site…"; no Open Recent, no New Post, no Save/Save All, no Go menu, no Dock menu |
| Proxy icon / edited dot | None. Title doesn't show the selected file; no `navigationDocument`, no `isDocumentEdited` |
| Recents | `recentSitePaths` (max 5) and `recentFiles` (max 10) tracked in-model; recents surfaced only inside app UI, not in File menu or Dock |
| Quick Look | Asset panel "Quick Look" button actually calls `NSWorkspace.open` — opens the default app, mislabeled |
| Drag & drop | Editor accepts string/fileURL drops; no drop on sidebar/window/Dock icon; no drag *out* of asset browser to Finder |
| Document types | None declared (`GENERATE_INFOPLIST_FILE` with no `CFBundleDocumentTypes`); can't drop a site folder on the Dock icon or "Open With Victor" |
| Notifications | None; build errors only visible in-app |
| Settings | SwiftUI `Settings` scene with TabView (native style on 14+) — fine as-is until victor-stn |
| Accessibility | Icon-only buttons labeled (victor-0qe done); VoiceOver audit pending (victor-3l6) |
| Motion | `reduceMotion` respected in App commands; not audited app-wide |
| Sandbox | App Sandbox + security-scoped bookmarks — all integrations below must stay sandbox-compatible |

## Workstreams

### W0 — Settings foundation (revises victor-stn)

Prerequisite for W2/W3, which add new settings (notification opt-out, menu bar
extra gate) and menu bindings. The 2026-07-03 analysis fixed five readers of
`isAutoSaveEnabled` disagreeing on defaults across three access patterns
(`@AppStorage`, raw `UserDefaults` reads, `didSet`-persisted properties) with
no cross-pattern observation — that whole bug class dies here.

**Departure from victor-stn as originally ticketed:** no JSON file. The
CodeEdit-style settings.json + custom property wrapper solves problems Victor
doesn't have (nested settings, importable themes) and creates ones it would
(rebuild SwiftUI observation, file I/O + debounce + corruption handling, key
migration — while window restoration and the site bookmark stay in
UserDefaults regardless). Revisit JSON only if/when victor-thm ships
user-editable themes.

**Design:**
- `@MainActor @Observable final class AppSettings`, singleton, UserDefaults-backed.
  One explicit property per preference with `didSet` persistence; key and
  default defined exactly once. ~15 properties: auto-save (enabled, delay),
  editor (font name/size, highlight line, layout mode), inspector visibility,
  badge colors, Hugo server defaults (port, drafts, future, expired).
- Views use `@Bindable var settings = AppSettings.shared` — replaces every
  `@AppStorage` in VictorApp, PreferencesView; the File-menu toggle and
  Preferences finally observe each other.
- ViewModels read/write the same instance; `SiteViewModel`'s settings
  properties and their `didSet` writers are deleted.
- Non-MainActor readers (AutoSaveService actor) get `nonisolated static`
  helpers (e.g. `AppSettings.currentAutoSaveDelay()`) — same single
  key/default definition, thread-safe UserDefaults read underneath.
- Explicitly *not* preferences (stay where they are): security-scoped
  bookmark, recentSitePaths, lastSelectedFilePath — app state, not settings.
- Migration: none. Same keys, same store; `defaults write` debugging intact.
- Tests: one round-trip test per property group + a defaults-coherence test
  asserting AppSettings and any remaining direct readers agree (replaces the
  AppConstants.Defaults discipline added 2026-07-03).

*Estimate: 4–6h including view migration. No dependencies; do first.*

### W1 — Window chrome and document conventions

**W1.1 Titlebar proxy icon + file path title.**
Use `.navigationDocument(url)` (macOS 14 SwiftUI API) on ContentView, driven by
`selectedNode?.url`, falling back to the site root when nothing is selected.
This gives the standard draggable proxy icon and Cmd-click path menu for free.
Pair with `.navigationTitle(selectedFile)` + `.navigationSubtitle(siteName)` so
the window reads "my-post.md — My Blog" like every Mac editor.

**W1.2 Edited-dot in the close button.**
`NSWindow.isDocumentEdited` has no SwiftUI equivalent. Add a small
`WindowAccessor: NSViewRepresentable` (grabs `view.window` in
`viewDidMoveToWindow`) — we keep exactly one such accessor and hang all
NSWindow needs off it. Drive `isDocumentEdited` from
`siteViewModel.hasUnsavedChanges`. With auto-save on this rarely shows, which
is correct behavior.

**W1.3 Customizable toolbar.**
Convert ContentView's toolbar to `.toolbar(id:)` with `ToolbarItem(id:)` per
control so users get "Customize Toolbar…" and placement persistence for free.
Audit items: layout-mode picker, inspector toggle, server start/stop, new
post. Keep destructive/rare actions out of the default set.

**W1.4 Window restoration audit.**
Frame restoration comes free with WindowGroup; verify sidebar width and
inspector state restore (inspector visibility already persisted). Selected
file already restores. Full session restore (tabs, scroll) stays in
victor-trs.

*Estimate: W1 total 1–1.5d. No dependencies.*

### W2 — Menu bar completeness

The menu bar is the contract with the user; today it's ~40% of a Mac editor's.

**W2.1 File menu.**
- **New Post… (Cmd+N)** — invokes the existing NewContentView flow for the selected folder (or content/ root).
- **New Folder (Cmd+Shift+N)**.
- **Open Hugo Site… (Cmd+O)** — exists.
- **Open Recent ▸** — build the submenu from `recentSitePaths` with a Clear Menu item. Also call `NSDocumentController.shared.noteNewRecentDocumentURL(_:)` on site open so the sites appear in the Dock icon's right-click menu and App Exposé, even though we render our own submenu.
- **Close Site (Cmd+Shift+W)** — wraps `closeSite()` with unsaved-changes check.
- **Save (Cmd+S) / Save All (Cmd+Option+S)** — Save routes through the focused editor (`@FocusedValue`), Save All calls `saveAllModifiedFiles()`.
- **Revert to Saved** — wraps `reloadFromDisk()` with confirmation, enabled only when the selected file is modified.
- **Reveal in Finder (Cmd+Option+R)** — for the selected node.

**W2.2 Go menu (new top-level menu).**
Back/Forward through `recentFiles` history (Cmd+Ctrl+Left/Right), "Go to
content/ | static/ | layouts/ | data/" jump items, and Quick Open once
victor-qop lands. Cheap to build — everything reads existing SiteViewModel
state.

**W2.3 Menu validation.**
Every item `.disabled()` against real state (no site open, no selection, no
unsaved changes). SwiftUI commands re-evaluate automatically; the work is
supplying the right `@FocusedValue`s. Define one `EditorActions` focused-value
struct instead of growing per-action keys (two already exist: formatting,
shortcode picker).

**W2.4 Dock menu.**
`applicationDockMenu(_:)` in the existing AppDelegate: Start/Stop Hugo Server,
recent sites. ~30 lines.

*Estimate: W2 total 1.5–2d. No dependencies; W2.2 partially blocked by victor-qop for one item.*

### W3 — System integration

**W3.1 Site folders as openable documents.**
Declare `public.folder` in `CFBundleDocumentTypes` (via `INFOPLIST_KEY_`/plist
fragment in project.yml) and handle `onOpenURL` + `application(_:open:)`:
validate it's a Hugo site, then `loadSite`. Enables: drag a site folder onto
the Dock icon, "Open With ▸ Victor" in Finder, `open -a Victor ~/blog`.
Sandbox note: URLs arriving this way carry implicit access; still mint our
security-scoped bookmark as `loadSite` already does.

**W3.2 Real Quick Look.**
Replace the asset panel's `NSWorkspace.open` with the SwiftUI
`.quickLookPreview($url)` modifier (macOS 14). Bind Space in the asset browser
grid and the sidebar file list to it. Delete the misleading fallback.

**W3.3 Drag & drop, both directions.**
- *In:* accept image/file drops on the **sidebar** (copy into the dropped-on folder, static/, or page bundle — reuse AssetService import path) and on the **editor** for images (copy asset + insert markdown link at drop point; editor currently only inserts the path string).
- *Out:* make asset browser items draggable to Finder/other apps via `.draggable(asset.url)` / `NSItemProvider`.

**W3.4 Build-error notifications.**
`UNUserNotificationCenter` notification when a Hugo build fails **while the
app is inactive** (foreground failures already show in the BuildErrorOverlay).
Clicking focuses the app and opens the Build Issues popover. Request
provisional authorization; expose an off switch in Settings ▸ Server.

**W3.5 Menu bar extra (optional, Settings-gated, default off).**
`MenuBarExtra` showing server status dot + start/stop + open-in-browser.
Writers leave Victor running; controlling the preview server without window
focus is genuinely useful. Ship last; cut first if the phase runs long.

**W3.6 Share.**
`ShareLink` on the selected file and on the running server's localhost URL
(asset detail panel + File menu). Small, do alongside W3.2.

*Estimate: W3 total 2–3d. W3.1 independent; W3.3 builds on AssetService.*

### W4 — Appearance, motion, and feel

**W4.1 Materials audit.** NavigationSplitView sidebar gets vibrancy for free —
verify no opaque backgrounds fight it (FileListView row backgrounds,
EmptyStateView). Inspector should use `.ultraThinMaterial` consistent with the
system inspector idiom.

**W4.2 Color audit.** Replace any hardcoded colors with semantic ones
(Color+Semantic.swift exists — finish adoption). Verify accent-color
followership (controls, selection highlight, badge tints) and full dark-mode
pass, including the markdown preview CSS (preview currently ships its own
palette; key it off `prefers-color-scheme`).

**W4.3 SF Symbols pass.** Symbols.swift exists; audit for correct weights,
`symbolRenderingMode(.hierarchical)` where multi-layer symbols exist, and
`symbolEffect(.bounce)` for save-confirmation feedback (respecting
reduceMotion via existing AnimationModifiers).

**W4.4 Animation audit.** Timing lives in AppConstants.Animation; sweep for
raw `withAnimation` calls with ad-hoc durations, and confirm every animation
honors reduce-motion (currently only App-level commands do).

**W4.5 App icon.** Current logo assets need a proper macOS 14-style icon
(single rounded-rect, no hardware chrome). External design task; ticket it.

*Estimate: W4 total 1.5–2d, parallelizable with anything.*

### W5 — Keyboard and accessibility

**W5.1 Full keyboard traversal.** Verify Tab/arrow traversal:
sidebar → editor → inspector. `focusSection()` on the three panes;
Cmd+Option+← /→ to move focus between panes (Xcode convention).

**W5.2 Shortcut coherence pass.** One table of all shortcuts (doc appendix +
Help menu item "Keyboard Shortcuts"). **Decided 2026-07-04:** Cmd+P goes to
Quick Open (editor convention) when victor-qop ships; until then it keeps
focusing sidebar search. Sidebar filter focus moves to Cmd+Option+F (Xcode's
filter-in-navigator idiom). Cmd+Shift+F stays Find in Files.

**W5.3 VoiceOver.** Execute victor-3l6 (already ticketed, P4) as part of this
phase rather than "later" — polish that ignores VoiceOver isn't polish.

*Estimate: W5 total 1–1.5d plus victor-3l6's 3–4h.*

## Modernisation track (M-series — code-wide, not Mac-specific)

Filed as tickets (unlike the W-series proposals below, these are in
ISSUES.yaml now). Grounded in a probe run 2026-07-03: compiling with
`SWIFT_STRICT_CONCURRENCY=complete` on Swift 5.9 produces **103 unique
warnings**, every one an error in Swift 6 language mode. The codebase is
already modern at its core (@Observable throughout, zero Combine/
ObservableObject, actors for stateful services) — this track is the next
ring out.

### M1 — Swift 6 strict concurrency burn-down (victor-sc6)

Warning profile from the probe:
- ~46 "sending non-Sendable value" — class models (ContentFile, FileNode,
  Template) crossing actor boundaries. Hotspots: EditorTextView (15),
  AssetService (9), SiteViewModel (8), LivePreviewPanel (7).
- ~27 main-actor isolation violations from nonisolated contexts — latent
  races of exactly the class fixed in the 2026-07-03 analysis.
- 8 non-Sendable `static let shared` singletons (Logger, parsers).

Staged:
1. Set `SWIFT_STRICT_CONCURRENCY: complete` in project.yml now (warnings in
   Swift 5 mode) so no new debt lands.
2. Burn down file-by-file. Non-Sendable sends: prefer snapshot structs at
   actor boundaries (the existing FrontmatterSnapshot pattern), then
   @MainActor annotation, then Sendable conformance for immutable types —
   in that order. Do NOT rewrite the model layer as structs; CLAUDE.md's
   class rationale (bindings, tree identity) stands.
3. Flip `SWIFT_VERSION` to 6.0; races become compile errors permanently.

*Estimate: 3–5d cumulative, fully incremental. Stage 1 is 10 minutes and
should happen the same week as W0 (which itself deletes several
static-shared warnings).*

### M2 — Structured observation: AsyncStream + bytes.lines (victor-str)

Replace pre-async observation plumbing:
- HugoServerService's three UUID-keyed callback dictionaries (+ the legacy
  `setOn*` single-callback shims) → `AsyncStream` properties; observers
  consume with `for await` in a task, and cancellation replaces manual
  callback deregistration. `SiteViewModel.setupHugoServerObservers` becomes
  a pair of observation tasks owned by the view model.
- LiveReloadClient's stored `onNavigate`/`onReload` closures → one event
  stream (`enum LiveReloadEvent { case navigate(String), reload }`).
- `Pipe.readabilityHandler` → `fileHandleForReading.bytes.lines` consumed in
  a child task. Structurally removes the "forgot to nil the handler" bug
  class patched 2026-07-03, and deletes ~15 Sendability warnings from M1's
  count as a side effect.

*Estimate: 1d. Fold into the M1 burn-down when those files come up.*

### M3 — Task.detached audit (victor-tdt)

19 uses across 12 files, most meaning "get off the main actor for file
I/O". Default replacement: `nonisolated` async functions (keep priority
inheritance, task-locals, cancellation). Keep `Task.detached` only where
detachment is the point; justify each survivor with a comment.

*Estimate: 0.5d, mechanical.*

### M4 — Small modernisation wins (victor-mod, grab-bag)

Individually droppable; do opportunistically when touching the file:
- Logger.swift: swap the `os_log` engine for `os.Logger` (categories,
  privacy annotations); keep the facade and call sites.
- `DateFormatter` → `Date.FormatStyle` (7 files; also fixes
  formatter-per-call in `createMarkdownFile`).
- One async `NSFileCoordinator` helper replacing the three duplicated
  `didResume` continuation dances (AutoSaveService, FileSystemService ×2).
- `DispatchQueue.asyncAfter` → cancellable `Task.sleep` (AssetDetailPanel
  copy feedback, ContentPathAutocompleteField suggestion hide). The other
  DispatchQueue.main.async uses are justified AppKit/WebKit re-entrancy
  deferrals — leave them.
- `@Entry` macro for FocusedValues/EnvironmentKeys once the Xcode 16 SDK is
  adopted; folds into W2.3's EditorActions consolidation.
- New tests in Swift Testing (`@Test`) where convenient; do not migrate the
  existing XCTest suite.

*Estimate: ~1d total across all items.*

### Re-scoped: victor-zw4 (dependency injection)

The original ticket protocol-izes all services (16 `static let shared`,
212 call sites) — 2022-era ceremony. Re-scoped to: inject the three
services tests actually need to fake (FileSystemService, AutoSaveService,
HugoServerService) as @Observable/actor references via Environment or
initializer; stateless parsers stay as they are.

### Modernisation non-goals
SwiftData (nothing is persistence-shaped), value-type model rewrite
(boundary snapshots solve the Sendable pressure), custom macros, wholesale
XCTest→Swift Testing migration.

## SwiftUI limits — the complete AppKit bridge inventory

Everything below is the *entire* expected AppKit surface for this effort; if an
item grows beyond this list, flag it in review.

| Need | Bridge |
|------|--------|
| `isDocumentEdited`, window field access | One shared `WindowAccessor` NSViewRepresentable (W1.2) |
| Dock menu | `applicationDockMenu` on existing AppDelegate (W2.4) |
| Recent documents for Dock | `NSDocumentController.noteNewRecentDocumentURL` (W2.1) |
| Notifications | UserNotifications framework (W3.4) — not AppKit but non-SwiftUI |
| Everything else | Pure SwiftUI: `navigationDocument`, `navigationSubtitle`, `toolbar(id:)`, `quickLookPreview`, `MenuBarExtra`, `ShareLink`, `draggable`, `onOpenURL`, `focusSection` |

Already-bridged AppKit (NSTextView editor, NSOpenPanel, find bar) is untouched.

## Phasing

| Phase | Contents | Exit criterion | Est. |
|-------|----------|----------------|------|
| 0. Foundation | W0 (settings layer) + M1 stage 1 (strict-concurrency warnings on) | All `@AppStorage`/raw-key access replaced by AppSettings; coherence test green; no new concurrency debt can land | ~0.5–1d |
| 1. Conventions | W1 (chrome) + W2 (menus) | Window has proxy icon/subtitle/edited-dot; File and Go menus complete with validation | ~3d |
| 2. Integration | W3.1–W3.4, W3.6 | Folder opens via Dock/Finder; real Quick Look; two-way drag & drop; background build-failure notifications | ~2.5d |
| 3. Feel | W4 + W5.1–W5.2 | Audits done; shortcut table published in Help | ~2.5d |
| 4. Optional | W3.5 MenuBarExtra, W4.5 icon, victor-3l6 | Gated/off-by-default extras shipped or consciously cut | ~1.5d |

Phases 1–2 are the highest leverage. Editor-UX tickets (tabs, quick open,
breadcrumbs) slot naturally after Phase 1 since the Go menu and shortcut
table reference them.

The M-series burn-down (M1 stages 2–3, M2, M3) runs *alongside* the phases
rather than as one: fix strict-concurrency warnings in whichever files the
current phase touches, plus one dedicated half-day per phase for files the
polish work won't visit. M4 items land opportunistically. Target: flip to
Swift 6 language mode by the end of Phase 3.

## Tickets

All filed in ISSUES.yaml (doc approved 2026-07-04): W-series — `victor-wc1`
(W1 chrome), `victor-mnu` (W2 menus), `victor-doc` (W3.1 folder document
type), `victor-qlk` (W3.2 Quick Look + W3.6 ShareLink), `victor-dnd` (W3.3),
`victor-ntf` (W3.4), `victor-mbe` (W3.5), `victor-vis` (W4 audits),
`victor-kbd` (W5.1–2), `victor-icn` (W4.5). M-series — `victor-sc6`,
`victor-str`, `victor-tdt`, `victor-mod`, plus the `victor-stn`/`victor-zw4`
revisions. Execution sequencing lives in
`Docs/MAC-POLISH-IMPLEMENTATION-PLAN.md`.

## Risks / open questions

1. **`navigationDocument` + folder-based model:** **Decided 2026-07-04:** file-level proxy icon (matches editor conventions: BBEdit, Nova), falling back to site root when nothing is selected. Revisit only if proxy-icon drag confuses in practice.
2. **Cmd+P conflict** (W5.2): **decided 2026-07-04** — Cmd+P = Quick Open; see W5.2.
3. **Toolbar customization** (`toolbar(id:)`) historically had SwiftUI quirks with conditional items (items that appear only when a site is open). Prototype with the server controls first; if placement persistence misbehaves, fall back to a static toolbar and drop W1.3 rather than fighting it.
4. **Notification permission prompts** annoy users if mistimed — request only on first *background* build failure, not at launch.
5. **Sandbox + dropped folders:** verify security-scoped bookmark minting works for Dock-dropped URLs on a clean install (no prior grant).
