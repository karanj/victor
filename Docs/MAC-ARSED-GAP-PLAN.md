# Mac-Arsed Gap Closure — Implementation Plan

**Date:** 2026-07-11 · **Status:** Approved plan
**Source:** Audit against the mac-arsed-mac-app skill
(github.com/bartreardon/skills), run 2026-07-11 after Phases 0–3 of the Mac
polish program shipped.
**Tickets:** victor-spl, victor-rnm, victor-sel, victor-und (new), victor-3l6
(pulled forward P4→P3).
**Delivery model:** same as MAC-POLISH-IMPLEMENTATION-PLAN.md — orchestrator
owns work orders, builds, tests, commits; subagents implement one work
package each; TDD where XCTest can reach, build + manual smoke where it
can't (menus, drag, VoiceOver).

## Where the audit landed

Rubric score ~25/36 ("solid with gaps"). The three weakest categories and the
gaps behind them:

| Rubric category | Score | Gap |
|---|---|---|
| Text handling | 2/3 | G1: Edit menu lost Spelling/Substitutions/Transformations/Speech; spell check off with no way on |
| Selection | 1/3 | G3: single-select sidebar, no Delete key, no multi-select |
| Copy/paste + drag out | 1/3 | G3: Cmd+C dead in sidebar, rows not drag sources |
| (cross-cutting) | — | G2: no rename UI; G4: no undo for file ops |
| Accessibility | 1/3 | victor-3l6 audit never ran |

Target after this plan: selection 1→3, copy/paste 1→2, text 2→3,
accessibility 1→2 ⇒ ~31–33/36 ("strong Mac app" band starts at 32).

**Explicitly not in this plan** (tracked elsewhere or excluded with reason):

- State restoration — victor-trs (blocked by victor-tab) and victor-csr stay
  on the editor track; sequencing them here would drag the tab-bar feature in.
- App Sandbox — victor-sbx, release-engineering shaped, separate effort.
- Shortcuts/App Intents ("New Post", "Build Site") — idiomatic but new
  surface area, not a convention regression. Ticket it only if user demand
  shows up.
- Type-to-select in the sidebar — SwiftUI `List` doesn't support it; the fix
  is an NSOutlineView substrate swap, which is not worth it for this alone.
- Frontmatter whole-form undo — fields already get field-local text undo;
  form-level undo is a separate design problem.

## Phase A — Regressions and quick wins (G1 + G2, ~1.5d)

| WP | Scope | Ticket | Agent | Notes |
|----|-------|--------|-------|-------|
| A.1 | **Spike, decision gate:** delete `CommandGroup(replacing: .textEditing)` on a branch; check whether the system Edit menu's default Find items drive the NSTextView find bar via responder chain | victor-spl | Orchestrator | ~30 min. Outcome A: they work → A.2 deletes the replacement, moves Find in Files to `CommandGroup(after: .textEditing)`, deletes FindPanelHelper's now-dead paths. Outcome B: they don't → A.2 keeps the replacement and re-adds Spelling and Grammar / Substitutions / Transformations / Speech submenus via responder-chain selectors (extend the FindPanelHelper `NSApp.sendAction` pattern) |
| A.2 | Implement A.1's outcome + `AppSettings.checkSpellingWhileTyping` (default **true**) driving `isContinuousSpellCheckingEnabled` in EditorTextView; Preferences checkbox; keep smart quotes/dashes off (markdown — add a code comment saying so) | victor-spl | Sonnet | TDD on the AppSettings property round-trip and the EditorTextView config read; menu presence is manual smoke. Toggle state must reflect in both the menu item and Preferences (both bind AppSettings — same pattern as existing toggles) |
| A.3 ∥ | Rename UI: "Rename…" in FileContextMenu → validation sheet (reuse the FolderRowWithSheets sheet pattern); Return key on focused sidebar row as accelerator | victor-rnm | Sonnet | Disjoint files from A.2 → parallel. TDD at SiteViewModel level first: rename must update `editedContentByFile` keys, `recentFiles` paths, open-editor binding, frontmatter panel. Clean up `renameFile`'s selectedNode nil-then-set force-update while there. Return-key handling must not swallow Return when the sidebar filter field has focus |

**Gate:** suite green; manual smoke = Edit menu shows all system submenus,
spell check toggles live in an open markdown file and persists relaunch,
rename an open dirty file and confirm no content loss; commit per WP, push.

## Phase B — Selection model (G3, ~2d)

The riskiest phase: `selectedFileID` feeds the per-keystroke invalidation
contract (CLAUDE.md), and the Phase-1-review note on victor-doc warns that
some App-level state assumes a single window. Design before code.

| WP | Scope | Ticket | Agent | Notes |
|----|-------|--------|-------|-------|
| B.1 | Inventory: every reader/writer of `selectedFileID`/`selectedNode`, plus every `.contextMenu` and `.tag` in the sidebar tree | victor-sel | Haiku | Output: table feeding B.2 |
| B.2 | Design memo: selection becomes `Set<UUID>` + derived single "lead" driving the editor. Decide: where the set lives (SiteViewModel), how lead is derived (last-changed member), which state tier it belongs to (transition-only — selection never mutates per keystroke), and the multi-select behaviour of every existing single-selection consumer from B.1 | victor-sel | **Opus** | ~1h, design only; becomes B.3's work order. Must state how the invalidation-contract tests get extended |
| B.3 | Implement: `List(selection: Set<UUID>)`; per-row `.contextMenu` → `.contextMenu(forSelectionType: UUID.self)` (right-click acts on full selection); `onDeleteCommand` → moveToTrash over selection with a single confirmation naming the count; `onCopyCommand` → pasteboard gets fileURL + path-string representations | victor-sel | Sonnet | TDD on the SiteViewModel selection API (lead derivation, batch trash); menu/keyboard behaviour manual smoke. Context-menu items that only make sense single-target (Open, Rename) disable on multi |
| B.4 | Drag out + move: extract `AssetBrowserView.assetDragItemProvider` into a shared helper (DRY); sidebar rows become drag sources (full selection drags); folder rows accept internal drops as a real `FileSystemService` move with the same post-move state fixups as rename | victor-sel | Sonnet (same agent as B.3, SendMessage) | Move must be distinguishable from the existing copy-in drop path (internal drag = move, external = copy — Finder convention). Reuse A.3's state-fixup code for moved-file bookkeeping, don't duplicate it |

**Gate:** suite green including extended invalidation-contract tests
(SiteViewModelTests); manual smoke = Shift/Cmd-click, right-click a
3-selection and trash it, Cmd+C two files → paste in Finder copies them,
drag a row to Finder, drag a file between sidebar folders, then type in the
editor and confirm no keystroke lag (Instruments spot-check if in doubt);
commit per WP, push.

## Phase C — Undo for file operations (G4, ~1d)

| WP | Scope | Ticket | Agent | Notes |
|----|-------|--------|-------|-------|
| C.1 | `FileSystemService.moveToTrash` returns the trashed URL (it already gets it from `trashItem(resultingItemURL:)` and drops it); thread through FileOperationsService; SiteViewModel registers inverses on `@Environment(\.undoManager)` with `setActionName`: Rename↔rename back, Duplicate↔trash the copy, Move to Trash↔put back, Move↔move back | victor-und | Sonnet | TDD with injected fresh `FileSystemService()` (victor-zw4 seams). Undo of a trashed *open* file must also restore selection and editor state — reuse the A.3/B.4 fixup path. Redo comes free from UndoManager if inverses re-register; test one full undo→redo cycle per op |

**Gate:** suite green; manual smoke = Cmd+Z after each of the four ops, Edit
menu shows "Undo Move to Trash" etc.; commit, push.

## Phase D — Accessibility pull-forward (victor-3l6, ~1d)

| WP | Scope | Ticket | Agent | Notes |
|----|-------|--------|-------|-------|
| D.1 | VoiceOver audit + fixes, new surfaces first (multi-selection announcements, rename sheet, drag affordances), then the backlog (labels/hints/traits on remaining controls) | victor-3l6 | Sonnet | Manual VoiceOver pass is the verification; record findings-then-fixed as the audit artifact in Docs/ |
| D.R | Program review: whole-diff review of Phases A–D, emphasis on selection-state races and undo re-entrancy | — | Opus (code-reviewer) | Findings fixed by original agents via SendMessage |

**Gate:** review findings closed; suite green; re-score the rubric in this
doc; commit + push; flip tickets (remove per the done-tickets-are-removed
policy) and update CLAUDE.md.

## Cross-cutting rules

Same as the parent plan: TDD where testable, commit per WP, push per gate,
diary per phase, agents escalate design surprises instead of deciding
inline. One addition: **any WP touching FileListView/SiteViewModel must run
the invalidation-contract tests before hand-back** — the two 2026-07-05/06
keystroke-lag incidents both entered through "harmless" sidebar/state
changes.

## Sequencing and estimate

A (1.5d) → B (2d) → C (1d) → D (1d) ≈ 5.5d serial; A.2∥A.3 and nothing else
parallelizes (B and C intentionally serialize on the same files). C depends
on A.3 + B.4's fixup helpers; D.1 depends on B's new surfaces existing.
