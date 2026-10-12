# macOS 27 Baseline Uplift

Raise the deployment target from macOS 14.0 to 27.0, preserving a final tagged build for macOS 14–26. Started 2026-10-10 on Xcode 27.0 (27A266a) / macOS 27.0.

## Pre-uplift review (2026-10-10)

| Check | Result |
|-------|--------|
| Floor before | macOS 14.0 (Sonoma) — `project.yml` options + `MACOSX_DEPLOYMENT_TARGET`, README |
| `#available` / `@available` OS gates | None. Nothing to strip. |
| Deprecations at a 27.0 target | None (built with `MACOSX_DEPLOYMENT_TARGET=27.0` override) |
| Compiler warnings | 13 at both targets — Swift 6, not SDK (8 × `Selector("…")`, 2 × `newTask` mutated after capture, 3 × `#ImplicitStrongCapture`) |
| Tests on macOS 27 | 764, one intermittent failure under full-suite load |
| OS-specific workarounds | `SharingHelper` (ShareLink in `CommandGroup` broken on 14, FB13281955); `WrappingHStack` (no native flow layout — still none in the 27 SDK) |

## Execution log

### Phase 1 — clean the macOS 14 line (branch `claude/macos14-final-cleanup`)

1. **`ada55b5` Extract shared editor debounce; clear all Swift 6 warnings.** `EditorViewModel` and `TextEditorViewModel` duplicated register → sleep → fire → deregister; both warnings came from the `var newTask` self-handle. Now `AutoSaveService.startDebounce` (3 new tests, red first). Its outer closure holds `self` weakly, which fixes the doc comment that said it never captured `self` (it did, strongly, via the inner `[weak self]` callbacks). `#selector` for the Edit-menu text services. 13 → 0 warnings.
2. **`42266c8` Make rename/move debounce-cancel tests deterministic.** Three tests relied on a 0.3–0.4s debounce not firing before `cancelDebounce` ran; reproduced red by shrinking the margin to 1ms. Now a 60s delay + shared `waitForDebounceRegistration` (`VictorTests/TestSupport.swift`), asserting an empty registry instead of sleeping past the interval.
3. **`0516eb0` Don't alert for load failures of files no longer selected.** Found while running at the 27 target (`testFileOpsWorkWithoutUndoManagerAttached` failed intermittently) but present on 14 too: Duplicate selects the copy, and trashing it before the fire-and-forget load ran raised a "Failed to load file" alert. Both load catch blocks go through `reportLoadFailure`, which alerts only for the selected node. Deterministic red test first. Ordered *before* the version bump so the legacy build includes it.
4. **`c445934` Bump version to 1.1.0 (final macOS 14 build).**

Tags (annotated) on `c445934`: `v1.1.0`, `macos14-final`. Branch `macos14-maintenance` for backports.

Verification: `c445934` at the 14.0 target (clean worktree), full suite 3/3 green — 768 tests, 0 warnings.

### Phase 2 — raise the floor (branch `claude/macos27-baseline`)

- `project.yml`: `deploymentTarget.macOS`, `MACOSX_DEPLOYMENT_TARGET` → 27.0; `xcodeVersion` 15.0 → 27.0.
- README requirements, `CLAUDE.md` deployment-target note, `WrappingHStack` comment.
- `testFrontmatterEditedDuringDebounceWindowReachesDisk`: failed once while a second suite ran concurrently (150ms + 1s fixed sleeps around a 0.5s debounce). Now edits synchronously after scheduling (MainActor test, Task can't have run) and polls the disk. Mutation-checked: a schedule-time frontmatter snapshot still fails it. Test-only, so left off the frozen 1.1.0 line.
- `LiveReloadClientTests`: dropped `await` on the synchronous `resolveAuthChallenge` (flagged at 27 only).
- `MARKETING_VERSION` 1.1.0 → 1.2.0: a compatibility jump, not a major — the 27 line is functionally the 1.1.0 app on a new floor.

## Pending (not done in session)

- [x] Pushed `claude/macos27-baseline`, `macos14-maintenance`, tags `v1.1.0` + `macos14-final`; PR #57 (merge commit, not squash, so the tags stay on `main`'s history).
- [x] `scripts/release.sh` for 1.1.0 → signed, notarized zip on a GitHub release (https://github.com/karanj/victor/releases/tag/v1.1.0).
- [ ] Smoke-test the 1.1.0 binary on a real macOS 14 or 15 machine/VM — everything above was built and tested on 27.
- [ ] Human check on 27: does `ShareLink` inside a `CommandGroup` now work? If so, delete `SharingHelper` (`VictorApp.swift`). (2026-10-10: Share via the existing `SharingHelper` path confirmed working on 27 — doesn't answer the `ShareLink` question.)

## Next: Liquid Glass branch

Branch off `claude/macos27-baseline` once merged. Already building against the 27 SDK, the app gets the system Liquid Glass chrome (toolbar, sidebar, menus) for free; the branch is about removing custom surfaces that fight it. APIs confirmed present in the 27 SDK: `glassEffect(_:in:)`, `GlassEffectContainer`, `glassEffectID`, `.buttonStyle(.glass)`, `ToolbarSpacer`, `sharedBackgroundVisibility`, `backgroundExtensionEffect`, `scrollEdgeEffectStyle`.

Starting inventory:
- `InspectorPanel.swift:62` — `.background(.ultraThinMaterial)` on a panel that sits beside the system sidebar/inspector glass.
- ~45 `.cornerRadius(n)` + filled-background badges/chips (sidebar, file list, asset browser, search, editors) — candidates for `glassEffect` or plain system styles; also soft-deprecated in favour of `clipShape`.
- Toolbar items in `ContentView` — grouping with `ToolbarSpacer` / `sharedBackgroundVisibility`.
- Two `WKWebView` wrappers (`PreviewWebView`, `LivePreviewPanel`) — evaluate SwiftUI `WebView`/`WebPage` alongside, since edge-to-edge content under glass toolbars is where `scrollEdgeEffectStyle` matters.

Keep the per-keystroke invalidation contract (`CLAUDE.md`) in view: glass effects in toolbar/menu scopes must not read per-keystroke state.

### Liquid Glass audit — screenshots on macOS 27 (2026-10-10)

Debug build on 27.0, throwaway demo site, driven through the Accessibility API. Light mode only. Findings:

**Glass / structure**
1. **Inspector is a hand-rolled `HSplitView` column** (`ContentView` detail → `InspectorPanel`), not `.inspector(isPresented:)`. Result: an opaque grey band, and the toolbar's glass capsule (server controls + inspector toggle) sits over the inspector's top edge instead of the toolbar extending across it. Move to `.inspector` — biggest single win.
2. **Sidebar renders flush and opaque**, not as the inset floating glass sidebar. `FileListView` uses `.listStyle(.sidebar)`; suspects are the opaque header block (site name + search field with `.background(controlBackgroundColor)`, `SidebarView.swift:292`) and the hard divider under it. Needs a probe.
3. **Secondary bars under the toolbar** — layout mode (Editor/Preview/Split) + preview source pickers (`TabBarView`), and each viewer's own header (config/data "View Form|Raw", asset/template browser filter/sort/view rows) — each a flat strip with a hairline divider. Candidates for toolbar items (`ToolbarSpacer` grouping) or a `GlassEffectContainer` over content.
4. **Formatting toolbar** (bold/italic/heading/lists/…/Live Preview/Save) — row of individually bordered buttons; a natural `GlassEffectContainer` + `.buttonStyle(.glass)` group.
5. Toolbar groups server status + play + gear + inspector toggle into one capsule; the inspector toggle wants its own group (`ToolbarSpacer`).
6. Settings window is stock Form/TabView — already fine.

**Layout bugs found along the way (not glass-specific; likely pre-existing, not checked on 1.1)**
- Split mode + inspector: the formatting toolbar clips its leading edge ("eadi…" — heading picker cut off). Needs to scroll or overflow, not clip.
- Template browser header: `Picker("View")` label wraps to "Vie / w" (`TemplateBrowserView.swift:97`).
- Empty asset browser (`assets/`): the header bar is vertically centred in the pane, with blank space above (empty state not top-aligned).
- Sidebar: "Draft" badge wraps under `post-3.md` instead of trailing it like `bundle`/`config`.
- Config editor: the Locale and Theme fields render without a text-field border, unlike Base URL/Title above them.

**Sidebar drag-collapse (user report)** — reproduced: dragging the divider below the 200pt min collapses the sidebar; dragging from the window's left edge then resizes the *window* — there is no drag-back affordance. Only View ▸ Toggle Sidebar / the toolbar button restore it. Standard `NavigationSplitView` behaviour; fix options: block collapse-on-drag (AppKit `NSSplitViewItem.canCollapse` via the window's split view controller) or accept and keep the toggle.

Screenshots: session scratchpad `shots/01..14-*.png` (not committed).

### Liquid Glass pass 1 — inspector, sidebar lock (2026-10-10, branch `liquid-glass`)

- **Inspector → system `.inspector(isPresented:)`** on the `NavigationSplitView` (was an `HSplitView` column with `.frame(width: 260)` + `.ultraThinMaterial`). Width via `AppConstants.Inspector` (220/260/360). Drag-to-close writes back through `AppSettings.isInspectorVisible`.
- **Sidebar can't be drag-collapsed** (user call). `SidebarCollapseLock` sets `canCollapse = false` on the sidebar `NSSplitViewItem` (SwiftUI has no API); re-applied when the window attaches and when a site opens/closes (`mainContent` swaps split-view branches). View ▸ Toggle Sidebar still works — `canCollapse` gates user collapse only (pinned by `SidebarCollapseLockTests`, 4 tests, red first).
- `ToolbarSpacer(.fixed)` separates the inspector toggle from the server-controls group.

**macOS 27 framework bug found doing this.** An `HSplitView` inside a `NavigationSplitView` detail column, beside a *visible* `.inspector`, crashes with `NSGenericException: …more Update Constraints in Window passes than there are views in the window` when a pane has a minimum width ≳150pt (100% reproducible in a 40-line standalone app; `inspectorColumnWidth` doesn't help, pane min ≤50pt or none is fine). Victor's Split mode hit it twice: the panes' `minWidth: 300`, and `EditorToolbar`'s ~600pt intrinsic minimum (AppKit-backed buttons). Workarounds:
  - Split panes: no `minWidth` (`panelMinWidth` removed); the detail column's `Content.minWidth` still bounds the pair.
  - `EditorToolbar`: `ViewThatFits` — full row, else the same controls in a horizontal `ScrollView` (no minimum). Also fixes the audit's "eadi…" clipping.
  - Inspector auto-hide now keys on `contentFile == nil` (the toggle's own enablement) instead of `!isMarkdownFile`: archetype `.md` files kept an open inspector beside `ArchetypeEditorView`'s `HSplitView` (2 tests, red first). Template/asset browsers already hid it.
  - Repro to file as Feedback: `Window` + `NavigationSplitView { List } detail: { HSplitView { Text.frame(minWidth: 150); Text.frame(minWidth: 150) } }.inspector(isPresented: .constant(true)) { Text("x") }`.

Verified: full suite 784 tests green ×2 (one earlier run hit the known intermittent `testRenameCancelsStillSleepingDebounce…` — its new diagnostics show the rename itself failed with `FileError.accessDenied`, not via the path-traversal guard log; lead for that flake). Launch + inspector shown in Split/Editor/Preview modes: no crash.

**Not yet verified by eye** — my Accessibility driver lost its TCC grant mid-session (rebuilding the binary changes its signature), so the post-fix screenshots of the inspector with a file selected and the drag-collapse lock in the running app still need a human pass:
- [ ] Inspector column with a post selected: glass/toolbar extends over it, Metadata/Statistics readable at 220–360pt.
- [ ] Sidebar divider dragged left stops at 200pt, never collapses; Toggle Sidebar still hides/shows it.
- [ ] Split mode + inspector at the 1000pt minimum window width: editor toolbar scrolls, nothing clips.

Debugging note: while bisecting, the "launch crashes" were really the restored `post-1.md` in Split mode — Victor restores the last selection, so the editor was always on screen.

### Liquid Glass pass 2 — code-only items while the Mac was locked (2026-10-12, branch `liquid-glass`)

Session ran with the screen locked: AX trust and Screen Recording were both granted (the pass-1 "lost TCC grant" was the rebuilt helper binary, not a revoked permission), but a locked session returns black screenshots, `screencapture -l` fails, and AX child walks loop. Nothing below has been seen on screen. Suite 784 green after each commit.

- `3b60959` audit layout bugs: `EmptyStateView` fills its container (asset browser header no longer floats mid-pane; 12 callers); fixed-width segmented "View" pickers `.labelsHidden()` (template browser "Vie/w"; also Form|Raw, folder, asset view pickers); sidebar status badges inline after the name; config Locale/Theme use the shared bordered `configTextFieldStyle()`.
- `a084d7b` `.cornerRadius` → `clipShape(RoundedRectangle)` (0 left); 9 duplicated grey chips → `secondaryBadgeStyle()`; `FileTagBadge` shared by sidebar + folder view.
- Formatting toolbar → glass capsules per group in one `GlassEffectContainer`, borderless buttons, Live Preview `.glass`, Save `.glassProminent`; opaque strip removed.

Human checks (in addition to pass 1's three):
- [ ] Formatting toolbar: capsules read as groups, icons not cramped (22pt hit area), Heading menu looks right borderless, Save prominent only when dirty. Light + dark.
- [ ] Toolbar without the grey strip: still separated from the editor text? (Revert the background line in `EditorToolbar.body` if not.)
- [ ] Split + inspector at 1000pt: toolbar falls back to scrolling, no constraint-loop crash.
- [ ] Sidebar: Draft/Scheduled badges inline; long names truncate before badges.
- [ ] Template browser / Form|Raw / asset + folder view pickers: no label, widths look right (constants were sized with the label; may want trimming).
- [ ] Empty `assets/` folder: header at top, empty state centred below.
- [ ] Config ▸ Essentials: Locale and Theme bordered like Base URL/Title.

### Pass 3 — inspector back to a fixed panel (2026-10-13, branch `liquid-glass`)

Pass 1's switch to SwiftUI `.inspector` introduced a crash, found on the pass-2 visual check: focus any text field in the inspector (Title, Description), then shrink the window → `NSGenericException: …more Update Constraints in Window passes than there are views in the window`. Bisected with scripted repros (AX + CGEvent, demo site in the scratchpad): `main` survives, `a7d2281` (pass 1) crashes, pass-2 commits irrelevant. Not fixed by dropping the inspector's focus section, pinning `inspectorColumnWidth`, or lowering `Content.minWidth` to 300.

It's a framework bug: a standalone app — `NavigationSplitView` + `.inspector { Text("x") }` + detail `.frame(minWidth: 400)` + window `minWidth: 1000` — throws the same exception **at launch** (detail min 0–300 fine, ≥400 crashes; no window min fine). File as Feedback with that repro.

Decision (user, 2026-10-13): don't fight it. Inspector is a fixed 260pt panel beside the content in an `HStack` (`AppConstants.Inspector.width`), Pages-style — no drag-resize, no split view, toolbar toggle unchanged. Lost vs pass 1: drag-to-resize and drag-to-close. All four crash repros now survive (inspector toggled at runtime, Title/Description focused, Editor and Split, resize to the 1000pt min).

Still open:
- [x] Split mode: Live Preview/Save hidden off the end of the scrolling toolbar → fixed: only the formatting groups scroll; Live Preview/Save stay pinned (labelled, then icon-only). Not moved to the window toolbar — Save's enabled state is per-keystroke, which CLAUDE.md keeps out of toolbar scopes. Same pass: the tab bar's "Preview:" caption drops out when narrow instead of wrapping a letter per line. Verified by screenshot at 1200pt (with/without inspector) and 1000pt.
- [ ] Inspector Description `TextEditor` has a hard 1pt border and visible scroller — restyle to match the other inspector fields.
- [ ] Revisit `.inspector` when a macOS 27.x SDK fixes the standalone repro.
