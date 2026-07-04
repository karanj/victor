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

| 2.2 | Real Quick Look (.quickLookPreview) in asset panel/grid/list + sidebar file list (Space, non-editable files only, .ignored fall-through for editable); ShareLink in asset panel. NSWorkspace.open fake deleted | victor-qlk | **done** | this commit |

| 2.1 | Folder document type (info: plist merge w/ INFOPLIST_KEY_*, versions pinned to build settings, LSHandlerRank Alternate); onOpenURL + application(_:open:) routing to single window; restore-race fix (initialSiteRestoreTask) + filteredNodes render-loop fix (pre-existing, exposed). Discoveries: entitlements empty → sandbox OFF (victor-sbx filed); agent claims SC6 baseline may undercount (~24) — RE-VERIFY AT GATE (conflicts with orchestrator's clean-build 103=103 measurement) | victor-doc | **done** | this commit |

| 2.4 | NotificationService (@MainActor class, NSObjectProtocol forces non-actor; nonisolated delegate methods); background build-failure notification on error empty→non-empty transition, coalesced per burst; provisional auth on first background failure; notifyOnBuildFailure setting + Preferences row + tests (16/16). Deep-link to Build Issues popover deliberately skipped (would need new cross-view plumbing; idea documented in service doc comment) | victor-ntf | **done** | this commit |

| 2.3 | Two-way DnD: sidebar folder drops (node insert, no reload) + editor image drops (ImageDropPathResolver: page bundle vs static/, UTF-16-safe insertion) + asset drag-out (real file provider). importFile via the one FileCoordinator copy path, sync by design (avoids new sending-self warnings). 9 new tests, 142/142 targeted | victor-dnd | **done** | this commit |

| 2.i | Orchestrator integration: File-menu Share…/Share Preview URL (ShareLink; render-check on manual list). SC6 baseline re-verified: 102 unique ≤ 103 baseline, zero new warning files — WP2.1 agent's "~24 extra" was duplicate-instance counting in raw build logs, baseline stands | — | **done** | gate commit |

| 2.R | Opus review: 1 P0 (ShareLink dead in CommandGroup, Apple FB13281955 — orchestrator's own edit; replaced with NSSharingServicePicker helper) + 4 P1s all fixed: multi-URL Dock-drop race (first-URL-only + loadSite serialization guard covering ALL open paths), drop-during-search node orphaning (SiteViewModel.importDroppedFile resolving canonical node by URL + 2 tests), silent editor-drop failures (errorMessage), non-file URLs entering image branch (isFileURL + fileURLsOnly). Flaky test noted: testAutoSaveUsesCorrectContentAfterFileSwitchDuringDebounce failed once in an agent run, passed at gate — watch it | — | **done** | this commit |

**Phase 2 COMPLETE** (pending user manual smoke). Tickets closed: victor-doc, victor-qlk, victor-dnd, victor-ntf (30 open).

| 3.1 | Haiku inventories: ~60 color sites (judgment calls made by orchestrator), 7 files missing reduce-motion, 2 uncancellable timers, 1 vibrancy offender (InspectorPanel) | victor-vis | **done** | tables in WP3.2 work order |
| 3.3 | Pane traversal (@FocusState AppPane + observable trigger, ⌥⌘←/→), sidebar filter → ⌥⌘J, Help > Keyboard Shortcuts window + design-doc appendix. Agent survived session-limit kill mid-work (resumed, finished). ORCHESTRATOR CORRECTION: original W5.2 decision misattributed ⌥⌘F as Xcode's filter chord; agent's first resolution displaced Find-and-Replace to ⇧⌘R; corrected to filter=⌥⌘J, Find-and-Replace stays ⌥⌘F (platform standard). Known tradeoff: focusable() adds one Tab stop per pane | victor-kbd | **done** | this commit |

**Next up:** WP3.2 report (audit-fix agent to resume for verify+report; its edits are in-tree) → commit 3.2 → WP3.4 (Opus Sendable memo) → WP3.5 (sc6 burn-down + AsyncStream) → WP3.6 (Task.detached + M4) → WP3.7 (Swift 6 flip) → 3.R.

**USER manual smoke — Phase 2 additions** (Phase 1 list above still stands):
7. Drag a site folder onto the Dock icon → opens (with confirm if dirty); drag TWO folders at once → only the first opens, no hang. Finder "Open With ▸ Victor" on a site folder works. A non-Hugo folder shows an error without disturbing the current site.
8. Quick Look: Space on an asset (panel, grid, list) and on an image in the sidebar → real QL panel; Space on a markdown file in the sidebar → nothing (typing unaffected).
9. Asset panel Share button → share sheet; File > Share… on a selected file → share sheet appears (NSSharingServicePicker path — this specifically was the Apple-bug fix); with server running, File > Share Preview URL.
10. Drag image from Finder → sidebar folder row (accent stroke, file appears, no full reload; try during an active sidebar search — the file must still appear); → editor over a page-bundle file (copies next to index.md, inserts ![](name)); → editor over a non-bundle file (copies to static/, inserts ![](/name)); drag an image from a web page into the editor → URL inserted as text (not a broken import).
11. Drag an asset out to Finder desktop → real file copy.
12. Notifications: with Victor in background, break a template save → one notification (provisional, no prompt); click → Victor activates; Preferences > Server toggle off → no notification.

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
