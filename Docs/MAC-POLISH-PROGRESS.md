# Mac Polish & Modernisation — Progress Ledger

Durable, committed-per-work-package record so any session can resume.
Plan: `MAC-POLISH-IMPLEMENTATION-PLAN.md` · Design: `MAC-POLISH-DESIGN.md`

## Resume protocol (for a fresh session)
1. Read this ledger top to bottom; the first non-`done` WP is the live one.
2. `git log --oneline -10` — per-WP commits are prefixed `WP<n>:`; the ledger
   entry for a WP is updated in the same commit that completes it.
3. Rebuild the session task list from the "Next up" line.
4. Subagent work orders live in the plan doc §phases; decisions live in the
   design doc (all marked "Decided").
5. Warning scoreboard: compare a fresh strict-concurrency build against
   `SC6-BASELINE-2026-07-04.txt` (103 warnings at baseline).

## Status

| WP | Scope | Ticket | Status | Commit |
|----|-------|--------|--------|--------|
| 0.1 | Haiku census of UserDefaults/@AppStorage (52 sites, 2 keys newly surfaced: frontmatterPanelHeight, per-view editorFontSize/Name copies) | victor-stn | **done** | census table embedded in WP0.2 work order; summary below |
| 0.2 | AppSettings class + 15 tests (TDD; DEBUG-only makeForTesting factory — documented in design doc W0) | victor-stn | **done** | this commit |
| 0.3 | All 52 census sites migrated (18 files); SiteViewModel settings props deleted; ContentView/TabBarView repointed; Color.Badge made @MainActor (census-missed site, agent-caught); warning count unchanged vs baseline | victor-stn | **done** | this commit |
| 0.4 | SWIFT_STRICT_CONCURRENCY=complete + baseline snapshot | victor-sc6 s1 | **done** | f718683 |
| 0.G | Phase 0 gate: full suite green, victor-stn → done, push | — | **done** | this commit |
| 1.x | W1 chrome + W2 menus | victor-wc1, victor-mnu | pending | — |
| 2.x | W3 integration | victor-doc/qlk/dnd/ntf | pending | — |
| 3.x | W4/W5 + M-series burn-down + Swift 6 flip | victor-vis/kbd/sc6/str/tdt/mod | pending | — |
| 4.x | Optional: mbe, 3l6, icn | — | pending | — |

| 1.1 | Chrome: navigationDocument proxy (file-level), title/subtitle, WindowAccessor + edited-dot via onChange(hasUnsavedChanges). Audit: sidebar width does NOT persist (no SwiftUI hook) — filed as follow-up | victor-wc1 | **done** | this commit |

| 1.2 | toolbar(id:) customization, 3 items, stable-identity workaround for conditional items. Verdict: works-with-workaround; interactive persistence check deferred to phase-gate manual list (agent had no TCC perms) | victor-wc1 | **done** | this commit |

| 1.3 | EditorActions focused-value struct (formatting/shortcode optional, save/revert/hasUnsavedChanges) published by EditorPanelView + TextEditorPanel; full File menu (New Post ⌘N, New Folder ⇧⌘N, Close Site ⇧⌘W w/ confirm, Save ⌘S single-owner, Save All ⌥⌘S, Revert w/ confirm, Reveal ⌥⌘R) with validation; sheet/dialogs attached at WindowGroup call site (no ContentView edit). Gap filed: victor-ea5 (5 specialized editors keep local ⌘S) | victor-mnu | **done** | this commit |

| 1.4 | Open Recent submenu + noteNewRecentDocumentURL; Go menu with ID-based nav history (50-entry, branch-truncating, re-entrancy-guarded, 12 tests) + role-folder jumps; Dock menu on AppDelegate (server toggle + recents) | victor-mnu | **done** | this commit |

| 1.R | Opus review found 2 P0s (nav history dies on reloadSite; TextFile edits invisible to modifiedFileIDs → Cmd+Q data loss) + 1 P1 (recentSitePaths invisible to Observation) — all fixed test-first (19 new tests) by the WP1.3/1.4 agent. Finding #4 (WindowAccessor warning) empirically cleared: 103 = 103, zero from the file. #5 (shared dialog state across windows) pinned to victor-doc. New tickets: victor-lsi (init side-effect test hazard) | — | **done** | this commit |

**Phase 1 COMPLETE** (pending user manual smoke, below).

**Next up:** Phase 2 — WP2.1 (folder document type, victor-doc) ∥ WP2.2 (Quick Look + ShareLink, victor-qlk) ∥ WP2.4 (notifications, victor-ntf), then WP2.3 (drag & drop, victor-dnd), 2.R review.

**USER manual smoke for Phase 1** (agents can't do these headlessly):
1. Proxy icon: select a file → titlebar "file.md — Site"; Cmd-click title → path menu; drag proxy icon to Finder.
2. Edited-dot: auto-save off, type → red dot in close button; save → clears. Same for a .css/.js file (TextEditorPanel).
3. Toolbar: right-click → Customize Toolbar… → drag an item, quit, relaunch → order held; toolbar sane with no site open.
4. File menu: New Post ⌘N, New Folder ⇧⌘N, Open Recent (+ Clear Menu refreshes immediately), Close Site ⇧⌘W confirm, Save/Save All/Revert, Reveal ⌥⌘R.
5. Go menu: A→B→C, Back×2 lands A; branch discards forward; delete B → Back skips it in one press; reload site → Back/Forward disabled; Go-to folder jumps.
6. Dock: right-click icon → server toggle + recents; Cmd+Q with dirty text file → alert; "Save and Quit" actually writes it.

## Census summary (WP0.1, full table in git history of this file if needed)

Preference keys going into AppSettings (15): isAutoSaveEnabled, autoSaveDelay,
highlightCurrentLine, editorFontSize, editorFontName, editorLayoutMode,
isInspectorVisible, badgeColorDraft/Scheduled/Expired (hex),
hugoServerPort, hugoServerBuildDrafts/Future/Expired, frontmatterPanelHeight.
Staying OUT (app state, untouched): hugoSiteBookmark, recentSitePaths,
lastSelectedFilePath. No inconsistent defaults remain (fixed 2026-07-03).
Tests touching keys: AutoSaveServiceTests, EditorViewModelTests (raw string
literal — to be fixed in WP0.3), SiteViewModelTests.

## Session log
- **2026-07-03:** critical analysis, 10 fixes shipped (`3c55f84`); design doc drafted.
- **2026-07-04:** decisions locked, tickets filed, plan committed (`ee9d6de`);
  Phase 0 started: census done, strict-concurrency warnings enabled + 103-warning
  baseline saved, AppSettings agent dispatched.
