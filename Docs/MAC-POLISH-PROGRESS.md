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

**Next up:** WP1.4 (Go menu, Open Recent submenu + noteNewRecentDocumentURL, Dock menu — same menus agent) → 1.R Opus review → Phase 1 gate: full suite + USER manual smoke (proxy-icon drag, edited-dot, Customize Toolbar drag + relaunch persistence, toolbar with no site open, File-menu walkthrough from WP1.3 report) → push.

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
