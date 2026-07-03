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
| 0.2 | AppSettings class + tests (TDD) | victor-stn | **in progress** (Sonnet agent) | — |
| 0.3 | Migrate all readers; delete SiteViewModel settings props | victor-stn | **in progress** (same agent) | — |
| 0.4 | SWIFT_STRICT_CONCURRENCY=complete + baseline snapshot | victor-sc6 s1 | **done** (verified: touched file emits warnings; null-build shows none — expected) | this commit |
| 0.G | Phase 0 gate: full suite, ticket flip, push | — | pending | — |
| 1.x | W1 chrome + W2 menus | victor-wc1, victor-mnu | pending | — |
| 2.x | W3 integration | victor-doc/qlk/dnd/ntf | pending | — |
| 3.x | W4/W5 + M-series burn-down + Swift 6 flip | victor-vis/kbd/sc6/str/tdt/mod | pending | — |
| 4.x | Optional: mbe, 3l6, icn | — | pending | — |

**Next up:** WP0.2/0.3 agent returns → orchestrator runs Phase 0 gate (0.G).

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
