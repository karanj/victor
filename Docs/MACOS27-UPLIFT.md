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

- [ ] Push branches + tags, merge to `main` (needs approval).
- [ ] `scripts/release.sh` for 1.1.0 → signed, notarized zip on a GitHub release.
- [ ] Smoke-test the 1.1.0 binary on a real macOS 14 or 15 machine/VM — everything above was built and tested on 27.
- [ ] Human check on 27: does `ShareLink` inside a `CommandGroup` now work? If so, delete `SharingHelper` (`VictorApp.swift`).

## Next: Liquid Glass branch

Branch off `claude/macos27-baseline` once merged. Already building against the 27 SDK, the app gets the system Liquid Glass chrome (toolbar, sidebar, menus) for free; the branch is about removing custom surfaces that fight it. APIs confirmed present in the 27 SDK: `glassEffect(_:in:)`, `GlassEffectContainer`, `glassEffectID`, `.buttonStyle(.glass)`, `ToolbarSpacer`, `sharedBackgroundVisibility`, `backgroundExtensionEffect`, `scrollEdgeEffectStyle`.

Starting inventory:
- `InspectorPanel.swift:62` — `.background(.ultraThinMaterial)` on a panel that sits beside the system sidebar/inspector glass.
- ~45 `.cornerRadius(n)` + filled-background badges/chips (sidebar, file list, asset browser, search, editors) — candidates for `glassEffect` or plain system styles; also soft-deprecated in favour of `clipShape`.
- Toolbar items in `ContentView` — grouping with `ToolbarSpacer` / `sharedBackgroundVisibility`.
- Two `WKWebView` wrappers (`PreviewWebView`, `LivePreviewPanel`) — evaluate SwiftUI `WebView`/`WebPage` alongside, since edge-to-edge content under glass toolbars is where `scrollEdgeEffectStyle` matters.

Keep the per-keystroke invalidation contract (`CLAUDE.md`) in view: glass effects in toolbar/menu scopes must not read per-keystroke state.
