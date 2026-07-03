# Mac Polish & Modernisation — Implementation Plan (Subagent Orchestration)

**Date:** 2026-07-04 · **Status:** Approved design (MAC-POLISH-DESIGN.md) → execution plan
**Delivery model:** Fable orchestrates; subagents implement; every work
package gates through build + tests before the next dependent package starts.

## Orchestration model

**The orchestrator (main session) owns:** work-order authoring, `xcodegen`,
builds, test runs, cross-package integration, commits/pushes, the session
diary, and all tracker/doc updates. Subagents never build-and-commit their
own work — one integrator prevents both duplicate build tokens and
half-merged states.

**Subagents own:** implementation of exactly one work package each, scoped
by a work order containing: the ticket ID, the design-doc section, an
explicit file list, the API shape to implement, tests to write *first*
(red/green), and a "do not touch" list. Precise work orders are the main
token lever — a well-scoped Sonnet agent beats a wandering Opus agent on
both cost and quality.

**Model policy** (per global subagent rules):

| Tier | Used for | Examples in this plan |
|------|----------|----------------------|
| Haiku | Inventories, call-site lists, single-file lookups | @AppStorage census, DateFormatter sites, hardcoded-color sweep |
| Sonnet (default) | Well-specified implementation with a written API shape and test list | AppSettings class, menu wiring, Quick Look swap, notification service, audit fixes |
| Opus | Judgment: concurrency boundary design, API redesign, phase-end review | Sendable strategy for the sc6 hotspots, AsyncStream API shape, phase-end diff reviews |

**Token-efficiency rules:**
1. Scout with Haiku (or reuse this session's findings) → write the work
   order → spawn Sonnet. Implementers never re-explore the codebase.
2. Revisions go back to the *same* agent via SendMessage (context intact),
   never a fresh spawn.
3. Opus reviews diffs at phase ends only, not per-package; per-package
   verification is the orchestrator running the test suite.
4. Parallelize only packages with disjoint file sets (marked ∥ below);
   everything else is sequential to avoid merge arbitration overhead.
5. Design-then-implement splits (Opus designs ~30 min, Sonnet executes)
   only where flagged; everywhere else the design doc *is* the design.

## Phase 0 — Foundation (~1d)

| WP | Scope | Ticket | Agent | Notes |
|----|-------|--------|-------|-------|
| 0.1 | Census: every UserDefaults/@AppStorage read-write with key + default | victor-stn | Haiku | Output: table for the 0.2 work order |
| 0.2 | `AppSettings` class + round-trip & coherence tests (TDD) | victor-stn | Sonnet | API shape in design doc W0 |
| 0.3 | Migrate views/ViewModels to AppSettings; delete SiteViewModel settings props + dead AppConstants fallbacks | victor-stn | Sonnet | Same agent as 0.2 (SendMessage) |
| 0.4 | `SWIFT_STRICT_CONCURRENCY: complete` in project.yml; snapshot warning baseline to Docs/ | victor-sc6 stage 1 | Orchestrator | 10 min; baseline = burn-down scoreboard |

**Gate:** full suite green; warning baseline recorded; commit.

## Phase 1 — Conventions (~3d)

| WP | Scope | Ticket | Agent | Notes |
|----|-------|--------|-------|-------|
| 1.1 ∥ | navigationDocument/title/subtitle + WindowAccessor + isDocumentEdited | victor-wc1 | Sonnet | |
| 1.2 | toolbar(id:) conversion — *prototype first* | victor-wc1 | Sonnet | Design risk 3: if placement persistence misbehaves, report back, orchestrator decides fallback |
| 1.3 ∥ | EditorActions focused-value consolidation + File menu items | victor-mnu | Sonnet | Blocked by Phase 0 (menu bindings) |
| 1.4 | Go menu, Open Recent submenu + noteNewRecentDocumentURL, Dock menu, validation pass | victor-mnu | Sonnet | Same agent as 1.3 |
| 1.R | Phase review: menus/focus/chrome diff | — | Opus (code-reviewer) | Findings fixed by original agents via SendMessage |

**Gate:** suite green; manual smoke (proxy icon drag, menu validation with
no site open); sc6 warnings fixed in all touched files; commit + push.

## Phase 2 — Integration (~2.5d)

| WP | Scope | Ticket | Agent | Notes |
|----|-------|--------|-------|-------|
| 2.1 ∥ | Folder document type + onOpenURL; sandbox bookmark check on clean install | victor-doc | Sonnet | |
| 2.2 ∥ | Quick Look fix + Space bindings + ShareLink | victor-qlk | Sonnet | Small; closes the mislabeled button |
| 2.3 | Drag & drop in (sidebar, editor) and out (asset browser) | victor-dnd | Sonnet | Largest P2 package; work order includes AssetService import-path reuse map |
| 2.4 ∥ | NotificationService + build-failure wiring + AppSettings toggle | victor-ntf | Sonnet | Auth request on first background failure only |
| 2.R | Phase review, emphasis on drop-handler edge cases & sandbox | — | Opus | |

**Gate:** suite green; drop/drag manual smoke; commit + push.

## Phase 3 — Feel + burn-down (~3d)

| WP | Scope | Ticket | Agent | Notes |
|----|-------|--------|-------|-------|
| 3.1 | Audit inventories: hardcoded colors, ad-hoc withAnimation, symbol usage, opaque backgrounds | victor-vis | Haiku | Three parallel narrow sweeps |
| 3.2 | Apply W4 audit fixes incl. preview CSS prefers-color-scheme | victor-vis | Sonnet | Work order = 3.1's tables |
| 3.3 ∥ | focusSection traversal + shortcut table + Help menu item | victor-kbd | Sonnet | Cmd+P/Cmd+Option+F decisions are final |
| 3.4 | Sendable strategy memo for hotspots (EditorTextView, AssetService, SiteViewModel, LivePreviewPanel): snapshot vs @MainActor vs Sendable per type | victor-sc6 | **Opus** | Design only, ~1h; becomes 3.5's work order |
| 3.5 | Execute burn-down per memo + AsyncStream conversion + bytes.lines | victor-sc6, victor-str | Sonnet | str's API shape comes from 3.4's memo |
| 3.6 | Task.detached audit + M4 grab-bag items | victor-tdt, victor-mod | Sonnet | Mechanical |
| 3.7 | Flip SWIFT_VERSION 6; fix stragglers | victor-sc6 stage 3 | Sonnet, escalate odd cases to Opus | |
| 3.R | Phase review: concurrency-focused | — | Opus | |

**Gate:** Swift 6 language mode builds clean; suite green; commit + push.

## Phase 4 — Optional (~1.5d, cut-first candidates)

| WP | Scope | Ticket | Agent |
|----|-------|--------|-------|
| 4.1 | MenuBarExtra (settings-gated) | victor-mbe | Sonnet |
| 4.2 | VoiceOver audit + fixes | victor-3l6 | Sonnet |
| 4.3 | App icon integration when asset delivered | victor-icn | Orchestrator |

## Cross-cutting rules

- **TDD everywhere testable** (red → green; UI-chrome work verified by
  build + manual smoke where XCTest can't reach).
- **Commit per work package**, push per phase gate (gh credential helper).
- **Diary:** session log appended per phase to Docs/ (CODE-ANALYSIS pattern).
- **Tracker:** ticket status flipped as packages complete; blocked_by
  edges already encode Phase 0 dependencies (stn → mnu, ntf, mbe).
- **Escalation:** any agent hitting an unexpected design decision stops and
  reports; the orchestrator decides or escalates to Opus. Agents do not
  make architecture calls inline.

## Estimated totals

~11d serial work, compressed by the ∥ packages to roughly 8–9 elapsed days
of sessions. Token profile: the bulk of implementation tokens land on
Sonnet; Opus appears in exactly five slots (four phase reviews + one
design memo); Haiku handles all inventory work.
