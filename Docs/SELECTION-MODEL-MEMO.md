# Selection Model Design Memo (B.2, victor-sel)

**Author:** B.2 design pass · **Status:** Approved work order for B.3/B.4 ·
**Scope:** `SiteViewModel.swift`, `FileListView.swift` only. No code changes
in this pass.

This memo is B.3's implementation order. Every decision below is meant to be
followed literally, not re-derived. Where a decision has a file:line anchor,
that is the exact site to change; where it says "new", the name is final —
don't rename mid-implementation.

---

## 1. Data model: where the Set lives, how the lead is derived

**DECISION:** Add `var selectedFileIDs: Set<FileNode.ID> = []` to
`SiteViewModel` (near `selectedNode`/`selectedFileID`, SiteViewModel.swift:63-77).
The List binds to `selectedFileIDs` directly. `selectedNode`/`selectedFileID`
become the *derived lead*, written only by a new canonical method
`applySelectionChange(_ newIDs: Set<FileNode.ID>)` that owns lead derivation.
No parallel "ordered selection" array — SwiftUI gives us a `Set` and nothing
else from `List(selection:)`, so lead tracking has to be reconstructed by
diffing old vs. new on every change, not preserved as a data structure.

**Rationale:** `SiteViewModel` is already the single owner of selection state
(navigation history, recent files, cache eviction all key off it) — putting
the Set anywhere else (e.g. a separate `SelectionModel`) would split the
diffing logic from the ~25 lead readers that live in the same file's
neighborhood and would need its own Observable wiring for no benefit. Keeping
`selectedNode`/`selectedFileID` as the derived lead (rather than deleting them
and rewriting 25 call sites) is what makes this a bounded change instead of a
rewrite — see §2.

**Lead-derivation algorithm** (implemented inside `applySelectionChange`,
called from `selectedFileIDs`'s `didSet`):

```
oldIDs = selectedFileIDs before this change (captured before didSet mutates in place — see note)
newIDs = selectedFileIDs after this change
currentLead = selectedNode?.id

1. If newIDs.isEmpty:
   lead = nil                                   // nothing selected

2. Else if newIDs == oldIDs:
   return without recomputing lead               // no-op guard, see §3

3. Else if let currentLead, newIDs.contains(currentLead):
   // Existing lead is still in the set (pure removal of OTHER members,
   // or a select-all/range-extend that happens to keep it) -> keep it.
   lead = currentLead

4. Else:
   let added = newIDs.subtracting(oldIDs)
   if added.count == 1 {
       // Single new element added (click, cmd-click add, arrow-key move) -> it's the new lead.
       lead = added.first!
   } else if added.count > 1 {
       // Multi-add with no surviving old lead (e.g. shift-click range that
       // doesn't include the old lead, or select-all after nothing was
       // selected). Deterministic fallback: the tree-order-first element of
       // `added`, using the existing filteredNodes flatten order (the same
       // order the List renders rows in) so the fallback is visually the
       // top-most newly-selected row, not hash-order-random.
       lead = firstInTreeOrder(of: added)
   } else {
       // added is empty and old lead is gone -> pure removal that dropped
       // the lead (e.g. cmd-click to deselect the lead row itself, or
       // Delete-key trash of the lead — see §5). Deterministic fallback:
       // tree-order-first element of the SURVIVING set.
       lead = newIDs.isEmpty ? nil : firstInTreeOrder(of: newIDs)
   }
```

`firstInTreeOrder(of:)` is a new private helper: flattens `filteredNodes` in
display order (same traversal `FileListView` uses to render — top-level
array order, then each directory's `children` in order, matching the
existing `DisclosureGroup`/`FileTreeRow` recursion) and returns the first ID
in that order that's a member of the given set. This makes fallback selection
land on a predictable, visually-adjacent row instead of whatever order
`Set` happens to iterate in — important because Swift's `Set` iteration
order is not stable across runs and picking a random survivor after a batch
trash would look buggy (selection jumping to an arbitrary row far from where
the user was working).

**Select-all case:** covered by rule 3 above — if the user does Cmd+A while
an existing lead is selected, `newIDs` (everything) contains `currentLead`,
so the lead doesn't move. If Cmd+A happens with nothing selected, rule 4's
multi-add branch fires and the lead becomes the first node in tree order
(top of the sidebar) — acceptable, matches Finder's Cmd+A-then-arrow-key
behavior of starting from the top.

**Implementation note on capturing `oldIDs`:** `@Observable`'s `didSet` runs
*after* the stored property has already changed, so `oldValue` (the standard
Swift `didSet` parameter) is what supplies `oldIDs` — do NOT try to read
`selectedFileIDs` again inside `didSet` expecting the pre-change value.

---

## 2. Compatibility contract: one canonical write path

**DECISION:** `selectedFileIDs` (Set) is the *source of truth* for what's
selected. `selectedNode` and `selectedFileID` remain stored properties (not
computed) — converting them to computed properties over the Set would fire
Observation on every read-site re-evaluation instead of only on actual lead
changes, which is the opposite of what the invalidation contract wants (see
§3). Instead, exactly one method — `applySelectionChange(_:)` — is the
canonical write path that keeps all three in sync. Every existing mutator
that currently assigns `selectedNode`/`selectedFileID` directly must route
through it or through `selectNode(_:)` (which itself now calls it).

**`selectNode(_:)` becomes a thin wrapper for the single-selection case:**
at the end of `selectNode(_:)` (SiteViewModel.swift:750-832), after the
existing `selectedNode = actualNode` / `selectedFileID = actualNode?.id`
lines (:765, :780-782), add:

```swift
selectedFileIDs = actualNode != nil ? [actualNode!.id] : []
```

This makes every current single-target call site (FileContextMenu "Open",
BreadcrumbBar, FolderContentsView taps, GlobalSearchView, post-create sheet
callbacks, `selectAndRevealNode`, navigation history replay) collapse the
Set to a single member for free — none of those 15+ call sites need to
change.

**Every direct assignment must be converted to route through the canonical
path:**

| Site | Current | New |
|---|---|---|
| `closeSite` (SiteViewModel.swift:682-683) | `selectedNode = nil; selectedFileID = nil` | `selectedNode = nil; selectedFileID = nil; selectedFileIDs = []` |
| `moveToTrash` (SiteViewModel.swift:1509-1512), single-node version | `selectedNode = nil; selectedFileID = nil` | Superseded by §5's batch-aware `moveToTrash(nodes:)` — see there. The single-node `moveToTrash(node:)` overload, if kept as a thin wrapper for the 15+ single-target call sites (FileContextMenu, etc.), must also clear `selectedFileIDs` of that node's id (not blanket-clear — another member of the set may still be validly selected if this path is ever called while multi-select is active, though today it never is) |
| `reloadFile` (SiteViewModel.swift:1360-1361) | `selectedNode = node` (same id, object identity poke) | No Set change needed — this doesn't change *which* id is selected, only refreshes the object graph. Leave as-is. |

**Why not "Set is source of truth, `selectedFileID` is a computed lead-view"
for the List binding too:** SwiftUI's `List(selection:)` needs a **stored**
`Binding<Set<FileNode.ID>>` — it writes to it directly on click, and that
write must not be silently overridden by a computed getter deriving from
something else, or clicks would appear to not register. So `selectedFileIDs`
must be the real stored/bound property, and `selectedNode`/`selectedFileID`
must NOT be bound to the List — only `selectedFileIDs` is. This is already
implied by decision 1 but stated explicitly here because it's the thing most
likely to get "simplified" into a bug (e.g. someone binding the List to a
computed `Binding` wrapping `selectedFileID` — don't).

**Invariant to hold at all times (post any canonical-path call):**
`selectedNode?.id == selectedFileID` and (`selectedFileID == nil` iff
`selectedFileIDs.isEmpty`) and (`selectedFileID != nil` implies
`selectedFileIDs.contains(selectedFileID!)`). This is the assertion helper
in §8.

---

## 3. State tier: transition-only, leaf-vs-container reads

**DECISION:** `selectedFileIDs` is **transition-only** state (parallel to
`modifiedFileIDs`), not per-keystroke. It mutates on click/keyboard
selection events, never inside a typing path. Guard the `didSet` the same
way `markFileModified`/`clearFileModified` guard `modifiedFileIDs` — no-op
early-return when `newValue == oldValue` (SwiftUI can and does re-deliver an
identical Set on some List internals; without the guard this would fire
Observation redundantly, same class of bug the CLAUDE.md contract calls
out).

**Rationale:** selection changes are user-gesture-rate (clicks, arrow keys),
not per-character. It belongs in the same tier as `modifiedFileIDs` — an
`@Observable` property whose *transitions* matter, whose *identical
re-assignment* must not fire Observation. It categorically does not belong
in the per-keystroke tier (`localContent`, `editedContentVersion`, etc.) and
must never be read from a body that only per-keystroke leaf views should
read from.

**Who may read `selectedFileIDs` (the Set) vs. `selectedNode`/`selectedFileID`
(the lead):**

- **`FileListView`'s `List` container itself** must read `selectedFileIDs`
  (it's the binding — unavoidable, and this is fine: List's internal diffing
  on a `Set<FileNode.ID>` binding is exactly the SwiftUI-native selection
  mechanism, not a leaked per-keystroke read).
- **Row-level visuals** (highlight background) come **free from `List`** —
  SwiftUI's `List(selection:)` renders selection highlighting itself for
  any tagged row; `FileRowView`/`FileRowViewModel` need no new selection
  field and `.equatable()` (FileListView.swift:494-495, :667-668) is
  **unaffected**. Do not add a `isSelected: Bool` to `FileRowViewModel` —
  that would make every row's Equatable comparison depend on membership in
  a Set that changes on every click, i.e. it would re-diff and potentially
  re-render every row's `FileRowView` body on every selection change instead
  of letting List's native selection rendering (which operates below
  SwiftUI's view-body layer, via the row's `.tag` and NSTableView/NSOutlineView-
  backed selection state on macOS) handle it for free. Confirmed: nothing in
  `FileRowView`/`FileRowViewModel` currently reads selection state, and
  nothing should.
- **Menu bar / App body / ContentView body / toolbar**: per Rule 1 of the
  existing contract, these may depend only on transition-only state — reading
  `selectedFileIDs.count` (e.g. for a "3 items selected" window subtitle, if
  ever added) is legal under the contract precisely because it's
  transition-only, but no such read exists yet and none is being added in
  this phase. `ContentView`'s existing `selectedNode` reads (window
  title/subtitle/navigationDocument/layout/`.id(selectedNode.id)`/inspector,
  ContentView.swift:41-275) are unaffected — they keep reading the lead,
  which is exactly as transition-frequency as before (it doesn't update more
  often just because a Set now backs it — a single click still produces one
  lead transition, same as today).
- **Batch-aware surfaces** (context menu title, Delete confirmation text —
  §5) read `selectedFileIDs.count` directly; these are leaf-level (a
  `.contextMenu`/`.alert` closure, not a parent body), so no blast-radius
  concern.

**Conclusion: nothing about this design widens per-keystroke blast radius.**
Selection was already transition-only-adjacent state before this change
(`selectedNode` reads already sit in ContentView's body per Rule 1, which the
contract already permits); the Set addition is the same tier, with its own
guarded no-op-on-identical-value contract.

---

## 4. Context menu migration

**DECISION:** Replace both per-row `.contextMenu` modifiers
(`FolderRowWithSheets` at FileListView.swift:518-528,
`FileRowWithSheets` at FileListView.swift:669-671) with a single
`.contextMenu(forSelectionType: FileNode.ID.self)` on the `List` in
`FileListView.body` (FileListView.swift:15-71), placed after
`.listStyle(.sidebar)` (:41).

**Sheet-state migration:** Add one `@State` enum at `FileListView` level:

```swift
private enum SheetTarget: Identifiable {
    case rename(FileNode)
    case newContent(FileNode)      // "New Content from Archetype..." target folder
    case newDataFile(FileNode)
    case newTranslation(FileNode)
    case newArchetype(FileNode)

    var id: String {
        switch self {
        case .rename(let n): return "rename-\(n.id)"
        case .newContent(let n): return "newContent-\(n.id)"
        case .newDataFile(let n): return "newDataFile-\(n.id)"
        case .newTranslation(let n): return "newTranslation-\(n.id)"
        case .newArchetype(let n): return "newArchetype-\(n.id)"
        }
    }
}
```

`FileListView` holds `@State private var sheetTarget: SheetTarget?` and a
single `.sheet(item: $sheetTarget) { target in switch target { ... } }` that
dispatches to `RenameSheet`/`NewContentView`/`NewDataFileView`/
`NewTranslationFileView`/`NewArchetypeView` with the wrapped node, mirroring
the bodies currently inside `FolderRowWithSheets`
(FileListView.swift:529-586). This replaces `FolderRowWithSheets`'s five
separate `@State` booleans (:486-490) and `FileRowWithSheets`'s one
(:664) — those two wrapper structs keep existing purely for their
`.dropDestination` (folder rows only, FileListView.swift:507-517) and
`.equatable()` row rendering, but stop owning sheet state or `.contextMenu`.
`renameTargetNode` (FileListView.swift:12, driven by the existing Return-key
handler at :62-66) folds into this same enum — Return-key rename becomes
`sheetTarget = .rename(node)` instead of its own separate `@State`.

The `forSelectionType` closure signature is
`(Set<FileNode.ID>) -> some View` (menu content) with an optional
`primaryAction: (Set<FileNode.ID>) -> Void` trailing closure. Implementation:

```swift
.contextMenu(forSelectionType: FileNode.ID.self) { ids in
    SelectionContextMenu(ids: ids, siteViewModel: siteViewModel, sheetTarget: $sheetTarget)
} primaryAction: { ids in
    // mirrors today's row-tap-to-select; List's own selection binding
    // already updates selectedFileIDs on tap, so primaryAction only needs
    // to open the file when exactly one id is targeted (double-click/Return
    // parity) - see below.
    if ids.count == 1, let node = siteViewModel.findNode(id: ids.first!) {
        siteViewModel.selectNode(node)
    }
}
```

`SelectionContextMenu` (new, replaces `FileContextMenu` +
`FolderContextMenu` with a single dispatcher) is constructed with the
`Set<FileNode.ID>` the system hands back — note this set is **not
necessarily** `selectedFileIDs`: right-clicking a row outside the current
selection replaces the selection with just that row for the menu's purposes
(standard macOS behavior, `forSelectionType` gives you exactly this for
free — no manual "am I in the selection" branching needed).

**Menu content rules for `SelectionContextMenu`:**

- `ids.count == 1`: resolve the single node, show the existing single-node
  menu (Open [files only] / New Content-from-Archetype, New Markdown File,
  New Folder [folders only] / Duplicate [files only] / Rename... / Move to
  Trash / Reveal in Finder / Copy Path), unchanged from today's
  `FileContextMenu`/`FolderContextMenu` content, driving `sheetTarget`
  instead of a local `@Binding`.
- `ids.count > 1`: **disable/omit** single-target-only items — Open,
  Duplicate, Rename..., and the "New X" folder-scoped creation items (they
  need one target directory, ambiguous over a multi-selection with mixed
  files/folders). **Show/enable** set-scoped items: Move to Trash (label
  reads "Move N Items to Trash" — see §5), Reveal in Finder (passes the
  resolved `[URL]` array to `NSWorkspace.activateFileViewerSelecting`, which
  already accepts an array — FileSystemService.swift:634-636, no service
  change needed), Copy Path (§6 — one path per line, or use the same
  multi-item pasteboard writer as Cmd+C so behavior is consistent between
  the menu item and the keyboard shortcut).
- Mixed files+folders in the multi-selection: Move to Trash and Reveal in
  Finder both operate over the resolved node/URL set regardless of type, no
  special-casing needed.

**Empty-space case:** `forSelectionType` only fires for taps on tagged rows;
right-clicking empty List space below the last row falls through to no menu
(SwiftUI default) — same as today (there was no empty-space context menu
before this change either, so no regression, and none is being added).

**`primaryAction` vs. existing tap-to-select:** `List(selection:)`'s own
click handling already updates `selectedFileIDs` on a plain click — that is
unrelated to `forSelectionType`'s `primaryAction`, which fires on
**double-click** (or Return, but Return is already claimed by the rename
accelerator at FileListView.swift:62-66, so `primaryAction` here really
only reachable via double-click). Today there is no explicit "double-click
to open" — single-click-to-select already opens the file as a side effect
of `selectNode`'s content loading. Keep `primaryAction` as a no-op-preserving
safety net (open if exactly one target) rather than removing it, since
`forSelectionType` requires the closure to be present if `primaryAction` is
supplied at all — omit the parameter entirely if you'd rather not implement
double-click semantics; it's optional in the SwiftUI API.

---

## 5. Batch operations semantics (Delete key / Move to Trash)

**DECISION:** Single confirmation naming the count, no per-file confirmation,
using the existing "trash is recoverable" argument strengthened by C.1
(victor-und) landing undo for Move to Trash right after this phase. Ancestor-
descendant pruning: **if the selection contains a folder AND one of its own
descendants, trash the ancestor only** (trashing the folder already removes
the descendant from disk — issuing a second `moveToTrash` call for the
descendant would either error on a now-missing path or (worse) silently
no-op racing the first call).

**New API on `SiteViewModel`:**

```swift
func moveToTrash(nodes: [FileNode]) async
```

Implementation:
1. Prune: build the pruned set by dropping any node that has an ancestor
   also present in `nodes`. Walk `node.parent` chain for each candidate;
   if any ancestor's `id` is in the input set, exclude it.
   (`isDescendantOf(role:)` at FileListView.swift:383-391 is a similar
   parent-walk pattern for a different purpose — don't reuse it directly
   since it walks for `HugoRole`, not node-id membership, but the walk shape
   is the same idiom.)
2. Confirm once: `.alert` (or `.confirmationDialog`) reading "Move N Items to
   Trash?" (N = pruned count, not raw selection count — the user shouldn't
   see "12 items" when 3 folders and their 9 descendants collapse to 3
   pruned operations) with Cancel/Move to Trash buttons. Singular-vs-plural
   phrasing: `pruned.count == 1 ? "Move “name” to Trash?" : "Move \(pruned.count) Items to Trash?"` — reuse whatever confirmation-copy helper the
   codebase already has for singular/plural (grep for existing patterns before
   writing a new one; if none exists, this is the first).
3. For each pruned node, call the existing single-node trash *body* (the
   part of today's `moveToTrash(node:)` at SiteViewModel.swift:1492-1518
   that does `fileOperationsService.moveToTrash` + `unregisterNode` +
   parent/fileNodes removal + `invalidateFilterCache`) — sequentially with
   `await` in a loop, not `async let`/`TaskGroup` concurrently, because
   `unregisterNode`/`fileNodes.removeAll` mutate shared `@Observable` state
   and concurrent mutation of the same array from multiple tasks is exactly
   the kind of race this codebase avoids elsewhere (see the actor-based
   services rationale in CLAUDE.md). One failure (`catch`) collects into an
   error list; report the first/aggregate error via `errorMessage` at the
   end rather than aborting the loop — a partial batch trash (7 of 10
   succeeded) should still complete the other 9, matching Finder's
   move-to-trash-with-one-locked-file behavior.
4. **Selection/editor fixup, generalized from today's single-node version
   (SiteViewModel.swift:1509-1512):** after all pruned nodes are trashed,
   if `selectedNode?.id` is among the trashed ids (pruned or descendant —
   check the *original* untrimmed `nodes` list, since a descendant that
   was pruned away is still gone from disk and must not remain "selected"):
   - Clear that node's cached content (existing `fileCacheManager.clearContent`
     call, now looped over every trashed id, not just one).
   - Recompute `selectedFileIDs` as the pre-trash `selectedFileIDs` minus
     every trashed id (pruned + their descendants). This naturally re-enters
     the `applySelectionChange` diffing logic (§1 rule 4's removal branch) —
     since this is a plain Set mutation it should go through the same
     `selectedFileIDs = ...` assignment, not a hand-rolled special case, so
     the lead-fallback logic in §1 runs uniformly. If the resulting set is
     empty, lead becomes nil (rule 1); if the old lead was trashed but other
     untouched selections remain, lead falls back to tree-order-first
     survivor (rule 4) — this is the natural generalization the ticket asks
     for, no new code path needed beyond routing through the existing
     assignment.

**`onDeleteCommand` wiring:** on the `List` (FileListView.swift, add near
the existing `.onKeyPress` modifiers at :47-66):

```swift
.onDeleteCommand {
    let nodes = siteViewModel.selectedFileIDs.compactMap { siteViewModel.findNode(id: $0) }
    guard !nodes.isEmpty else { return }
    pendingTrashNodes = nodes   // @State, drives the confirmation .alert
}
```

Keep the single-node `moveToTrash(node:)` (SiteViewModel.swift:1492) as a
thin wrapper — `moveToTrash(nodes: [node])` — so the 15+ existing
single-target call sites (FileContextMenu equivalent in
`SelectionContextMenu`, etc.) don't need individual updates; they already
go through this call.

---

## 6. Cmd+C: pasteboard representations

**DECISION:** `onCopyCommand` on the `List` (FileListView.swift, alongside
`onDeleteCommand`), writing **one `NSItemProvider` per selected file** to
satisfy `onCopyCommand`'s `() -> [NSItemProvider]` signature — SwiftUI's
`onCopyCommand` doesn't hand you a raw `NSPasteboard`, it wants providers,
which is a closer fit than reaching for `NSPasteboard.general` directly
(that would require also intercepting the *system* Cmd+C, which
`onCopyCommand` already does correctly via the responder chain — don't
duplicate with a manual pasteboard write, which is a mechanism mismatch we
should not introduce for its own sake).

```swift
.onCopyCommand {
    siteViewModel.selectedFileIDs
        .compactMap { siteViewModel.findNode(id: $0) }
        .sorted { firstInTreeOrder-consistent comparator, see below }
        .map { node in
            let provider = NSItemProvider(contentsOf: node.url) ?? NSItemProvider()
            provider.registerObject(node.url.path as NSString, visibility: .all)
            return provider
        }
}
```

- **`NSItemProvider(contentsOf:)`** registers the `public.file-url`
  representation — this is the exact pattern already validated by
  `AssetBrowserView.assetDragItemProvider` (AssetBrowserView.swift:349-353)
  for drag-out; reusing the same provider-construction idiom for copy is
  consistent, not coincidental — a paste into Finder performs a real file
  copy, matching Finder's own Cmd+C semantics for files.
- **`registerObject(_:visibility:)` with the path string** is the second
  "format" the ticket calls for (fileURL + path string) — this lets a paste
  into a plain-text context (Terminal, a text field) yield the absolute
  path, mirroring what `copyPathToClipboard`
  (FileSystemService.swift:639-640+) already does for the single-file
  "Copy Path" menu item, so behavior is consistent whether the user uses
  Cmd+C or the context-menu action, for a single-file case.
- **Ordering:** `selectedFileIDs` is an unordered `Set`; sort resolved nodes
  by the same tree-display order used for `firstInTreeOrder` (§1) before
  building providers, so a multi-file paste into Finder lands in a
  visually-predictable order (top-to-bottom as shown in the sidebar) rather
  than `Set`-iteration-random order. This reuses `firstInTreeOrder`'s
  underlying flatten helper — factor the flatten into
  `treeOrderIndex(of ids: Set<FileNode.ID>) -> [FileNode.ID]` (returns all
  members in display order) and have `firstInTreeOrder` become
  `treeOrderIndex(of:).first`, so there's one flatten implementation, not
  two.
- **`Copy Path` menu item on a multi-selection (§4):** reuse this same
  provider-building logic's path-string half (just the strings, newline-
  joined) rather than writing a second pasteboard-formatting routine —
  `copyPathToClipboard` today handles a single URL
  (FileSystemService.swift:639-640-ish); add a
  `copyPathsToClipboard(urls: [URL])` overload on `FileOperationsService`/
  `FileSystemService` that joins with `\n` writing one
  `NSPasteboard.general.setString` call, and have the single-URL version
  call it with a one-element array (DRY, don't fork the two).

---

## 7. Two row paths (flat list vs. `FileTreeRow`)

**CONFIRMED, no change needed beyond what §1/§4 already specify.** Both the
top-level `List(siteViewModel.filteredNodes, ...)` rows
(FileListView.swift:16-39) and the recursive `FileTreeRow` rows used inside
each folder's `DisclosureGroup` content (FileListView.swift:76-105) already
apply `.tag(node.id)` to every row (folder rows at :34/:98, file rows at
:38/:101) — `List(selection:)` (now bound to the `Set`) walks the entire
rendered tree including `DisclosureGroup` children and honors `.tag` at any
nesting depth, so multi-select (Shift/Cmd-click across a folder boundary,
e.g. one row inside an expanded folder plus one top-level row) works with
zero structural change to either row path.

**One thing to verify in B.3, flagged not resolved here:** `DisclosureGroup`
labels are themselves tappable for two purposes — expand/collapse (tapping
the disclosure triangle) and row selection (tapping the label text/row,
which is what `FolderRowWithSheets` renders as the label at
FileListView.swift:32). SwiftUI's default `DisclosureGroup` makes the
**entire label view** a togglable tap target for expand/collapse in some
older macOS List/DisclosureGroup interactions, which could compete with
tap-to-select — this was presumably already resolved (or benign) for
single-select today, since it's not mentioned in the B.1 inventory as a
known issue, but multi-select's Shift/Cmd-click needs the *same* label tap
to register as a selection-modifier click, not an expand/collapse toggle.
Since this is existing behavior unchanged by the Set migration (the tap
target logic doesn't change — only what the resulting `.tag`-driven
selection populates), B.3 should smoke-test Cmd-click and Shift-click
specifically on folder rows (not just file rows) before sign-off, but no
design decision is needed here unless that smoke test surfaces a real
conflict — if it does, escalate rather than deciding inline (per the plan's
cross-cutting rule).

---

## 8. Test plan

**Existing tests that change:**

- `testSelectNodeUpdatesSelection`, `testSelectNilNode`,
  `testSelectSameNodeNoOp`, `testSelectPageBundleSelectsIndexFile`,
  `testSelectAndRevealNode` (SiteViewModelTests.swift:1419-1507+): each
  needs one additional assertion — `XCTAssertEqual(viewModel.selectedFileIDs, expectedSingleton)` (or `.isEmpty` for the nil case) — since `selectNode`
  now also writes the Set (§2). Behavior of the existing assertions is
  unchanged.
- `testRenamePreservesSelectedNodeIdentityWithoutForcePoke`
  (SiteViewModelTests.swift:683): unaffected by this phase (rename doesn't
  touch selection identity, only the node's own `url`), but confirm
  `selectedFileIDs` still contains the (unchanged) id after rename as a new
  one-line addition, since this is exactly the kind of divergence bug the
  canonical-path invariant (§2) exists to catch.
- All `testNavigation*` tests (SiteViewModelTests.swift:937-1157): unaffected
  in behavior (navigation drives `selectNode`, which now also sets the
  Set), but each that asserts final selection state should gain the same
  `selectedFileIDs` singleton assertion as above. Given the volume (12
  tests), prefer adding one shared helper `assertSelection(_ viewModel:, is node: FileNode?, file:line:)` that asserts all three
  (`selectedNode`/`selectedFileID`/`selectedFileIDs`) in one call, and
  retrofit these tests to use it rather than hand-adding three assertions
  ×12 tests.
- `testFilteredNodesCacheInvalidatedOnCloseSite` (SiteViewModelTests.swift:1596):
  add `selectedFileIDs` to the post-`closeSite()` empty-state assertions
  (§2's `closeSite` row).
- `EditorViewModelTests`: the ~21 tests referencing `selectNode`/
  `selectedNode` for file-switch race guards are unaffected — those guards
  compare `selectedNode?.id == nodeID` (a lead comparison), which keeps
  working identically since the lead derivation always produces a real
  `selectedNode` for single-target flows.

**New tests B.3 must write first (TDD — before touching `FileListView.swift`
or adding the batch API):**

1. **Lead-derivation table** (new test group, `SiteViewModelSelectionTests`
   or a new `# MARK:` section in `SiteViewModelTests.swift`) — one test per
   row of §1's algorithm:
   - `testLeadDerivation_singleAdd_becomesLead`
   - `testLeadDerivation_removalKeepingLead_leadUnchanged`
   - `testLeadDerivation_removalOfLead_fallsBackToTreeOrderFirstSurvivor`
   - `testLeadDerivation_clearingSelection_leadBecomesNil`
   - `testLeadDerivation_selectAllWithExistingLead_leadUnchanged`
   - `testLeadDerivation_selectAllFromEmpty_leadBecomesTreeOrderFirst`
   - `testLeadDerivation_multiAddNoSurvivingLead_fallsBackToTreeOrderFirstOfAdded`
   Each constructs a small `FileNode` tree (3-5 nodes, mixed files/folders,
   known tree order), drives `selectedFileIDs = ...` directly (simulating
   what the List binding would do), and asserts `selectedNode`/
   `selectedFileID` land on the exact expected id.
2. **Batch trash with ancestor-descendant pruning:**
   - `testMoveToTrashBatch_prunesDescendantsOfSelectedFolder` — select a
     folder and one of its own children, call `moveToTrash(nodes:)`, assert
     `fileOperationsService`/`FileSystemService`'s trash call happened
     exactly once (for the folder), not twice — needs a fresh injected
     `FileSystemService()` (victor-zw4 seam) with a call-count-capturing
     stub or spy, since the real service hits disk.
   - `testMoveToTrashBatch_unrelatedSiblingsAllTrashed` — no pruning when
     nodes are unrelated.
   - `testMoveToTrashBatch_clearsSelectionAndFallsBackWhenLeadIsTrashed` —
     lead is among the trashed set, another untouched node remains selected
     → lead falls back per rule 4.
   - `testMoveToTrashBatch_clearsSelectionEntirelyWhenAllTrashed` → lead
     nil, `selectedFileIDs` empty.
3. **Canonical-write-path invariant** — the exact assertion helper:

   ```swift
   func assertSelectionInvariant(_ viewModel: SiteViewModel, file: StaticString = #filePath, line: UInt = #line) {
       if viewModel.selectedFileIDs.isEmpty {
           XCTAssertNil(viewModel.selectedNode, file: file, line: line)
           XCTAssertNil(viewModel.selectedFileID, file: file, line: line)
       } else {
           XCTAssertNotNil(viewModel.selectedFileID, file: file, line: line)
           XCTAssertEqual(viewModel.selectedNode?.id, viewModel.selectedFileID, file: file, line: line)
           XCTAssertTrue(viewModel.selectedFileIDs.contains(viewModel.selectedFileID!), file: file, line: line)
       }
   }
   ```

   Call this at the tail of every test in the lead-derivation table (1) and
   every batch-trash test (2) — it's the thing that catches a future change
   that mutates `selectedNode` directly without going through
   `applySelectionChange`/`selectNode`.

**Invalidation-contract test extension** (extend the mechanism from
SiteViewModelTests.swift:104-190, `withObservationTracking { _ = viewModel.X } onChange: { observedChange = true }`):

- `testSelectedFileIDsIsNoOpWhenReassignedSameSet` — mirrors
  `testMarkFileModifiedIsNoOpWhenAlreadyModified` (:123-144): assign
  `selectedFileIDs = [a]` twice (or reassign the identical Set instance),
  assert the second assignment fires no Observation on a
  `withObservationTracking { _ = viewModel.selectedFileIDs }` tracker. This
  is the direct analog proving the §3 no-op guard is real, not just
  documented.
- `testSelectedFileIDsFiresObservationOnActualTransition` — sanity check
  mirror of :104-118, proving the tracking harness itself works for this
  property (guards against a vacuously-passing no-fire test above).
- No new test is needed asserting menu/App-body *non*-dependency on
  `selectedFileIDs`, because — unlike `modifiedFileIDs`, which has existing
  `.disabled()` menu closures reading `isFileModified` that needed pinning —
  no menu/toolbar/App-body code reads `selectedFileIDs` in this design (§3):
  the only reader is the List binding itself and leaf-level batch-menu/
  alert closures. If B.3 finds itself adding a `selectedFileIDs` read to
  `ContentView`'s body or `VictorApp`'s `.commands`, that is a design
  deviation from this memo — stop and escalate rather than adding it, since
  it would need its own no-op-guard pinning test at that point.

---

## 9. Explicit non-goals

- **Type-to-select.** SwiftUI `List` has no type-ahead hook; the only path
  is an `NSOutlineView` substrate swap, which is a much larger change than
  this ticket's scope justifies (per MAC-ARSED-GAP-PLAN.md's own exclusion).
- **Rubber-band (marquee) selection.** Not exposed by SwiftUI `List` at all
  on macOS; same substrate-swap cost as type-to-select. Shift/Cmd-click plus
  Cmd+A cover the required interactions.
- **Drag-reorder within the sidebar.** Files/folders sort by name
  (`sortChildren`/the inline sort comparators at SiteViewModel.swift:1410-
  1416, :1472-1477) — there is no user-controlled ordering to drag-reorder.
  B.4's drag-to-move (moving a node to a *different folder*) is a distinct
  feature from reordering within the same list and is unaffected by this
  exclusion.

---

## Sequenced checklist for B.3

Tests first, per repo convention (Red/Green/Refactor):

1. Add `selectedFileIDs: Set<FileNode.ID>` stored property + guarded
   `didSet` calling `applySelectionChange` (§1, §3). Write §8.1's lead-
   derivation tests against it before wiring anything else — they should
   fail (no `applySelectionChange` yet), then pass once implemented.
2. Add `firstInTreeOrder`/`treeOrderIndex(of:)` helper (§1, reused by §6).
3. Wire `selectNode(_:)` to also set `selectedFileIDs` (§2). Add/retrofit
   the `assertSelection` helper (§8) and run it through the existing
   `testSelectNode*`/`testNavigation*` suites — should stay green with the
   helper added, not just unchanged.
4. Convert `closeSite`'s direct assignment (§2 table). Extend
   `testFilteredNodesCacheInvalidatedOnCloseSite` (or add a sibling test)
   asserting `selectedFileIDs` is cleared.
5. Add `moveToTrash(nodes:)` with pruning (§5), keep `moveToTrash(node:)` as
   a one-element wrapper. Write §8.2's batch-trash tests against injected
   fresh services before wiring `onDeleteCommand`.
6. Add invalidation-contract no-op tests (§8, mirroring :104-190) —
   should already pass if step 1's guard is correct; if not, fix the guard.
7. `FileListView`: switch the `List` binding to `selectedFileIDs`, add
   `.onDeleteCommand`/`.onCopyCommand` (§5, §6), add the `SheetTarget` enum
   and single `.sheet(item:)` (§4), replace per-row `.contextMenu` with
   `.contextMenu(forSelectionType:)` and the new `SelectionContextMenu`
   (§4). Fold the Return-key rename accelerator into `SheetTarget` (§4).
   This step has no new SiteViewModelTests coverage (it's view-layer) —
   manual smoke per the Phase B gate in MAC-ARSED-GAP-PLAN.md.
8. Add `copyPathsToClipboard(urls:)` (§6), route both the multi-select menu
   item and single-file path through it.
9. Full suite green, including the extended invalidation-contract tests.
   Manual smoke: Shift/Cmd-click, right-click a 3-selection and trash it,
   Cmd+C two files → paste in Finder, drag (B.4, separate work), type in
   the editor and confirm no keystroke lag.

## Risks & watch-fors

- **Observation storm regression:** the guarded no-op on identical-Set
  reassignment (§3) is the load-bearing piece — if `didSet` recomputes the
  lead unconditionally instead of early-returning on `newValue == oldValue`,
  every `List` internal re-delivery of the same selection (which happens
  more than you'd expect from mouse-drag-to-select-range gestures firing
  intermediate updates) becomes an Observation event. Pin this with §8's
  no-op test before writing anything else — this is the single highest-risk
  item in the whole design given the file's history (two prior keystroke-lag
  incidents both entered through "harmless" sidebar/state changes per
  MAC-ARSED-GAP-PLAN.md's cross-cutting rule).
- **List binding reentrancy / `didSet` loops:** `selectNode(_:)` writes
  `selectedFileIDs` (§2), and `selectedFileIDs`'s `didSet` must NOT call back
  into `selectNode(_:)` (unlike `selectedFileID`'s existing `didSet` at
  SiteViewModel.swift:67-77, which *does* call `selectNode` — that pattern
  is fine for the single-value property because `selectNode` guards on
  `actualNode?.id == selectedNode?.id` and returns early, breaking the
  cycle). For the Set, `applySelectionChange` must only update
  `selectedNode`/`selectedFileID` directly (not through `selectNode`), or
  the guard needs re-verifying carefully for the Set case — a naive
  "call `selectNode(resolvedLeadNode)` from inside `selectedFileIDs`'s
  `didSet`" would re-enter and write `selectedFileIDs` again (even if
  idempotent, this is fragile and should be avoided by construction:
  `applySelectionChange` sets `selectedNode`/`selectedFileID` as plain
  assignments, never through `selectNode`).
- **`forSelectionType` + `.tag` interplay:** confirmed conceptually correct
  (§4, §7) but not verified against the running app in this design pass — no
  build was run. B.3's step 7 is the first point this gets built; if
  `forSelectionType`'s Set doesn't line up with `.tag(node.id)` on nested
  `DisclosureGroup` rows the way expected (possible macOS-version-dependent
  List/OutlineView-bridging quirk), escalate rather than guessing a fix —
  this interplay is exactly the kind of thing that looks fine on paper and
  behaves differently once XCTest/SwiftUI previews aren't testing real
  NSOutlineView-backed selection.
- **Undo interaction (forward-looking, C.1):** §5's batch trash returns
  URLs today only through the existing single-node
  `fileOperationsService.moveToTrash` call inside the loop — C.1 (victor-und)
  will need each pruned node's trashed-URL for its own inverse-registration.
  Don't refactor `moveToTrash(nodes:)`'s loop body to discard per-node
  results just because this phase doesn't need them; keep the per-iteration
  trashed URL accessible (e.g. build a
  `[(node: FileNode, trashedURL: URL)]` locally even if unused by this
  phase) so C.1 doesn't have to re-touch this loop's shape.

---

## Addendum (2026-07-11, orchestrator): canonical path owns side effects

Implementation surfaced a contradiction between §4 and the Risks section:
with `applySelectionChange` doing plain assignments, `selectNode`'s same-id
early return suppressed content loading on click. Superseding correction, as
built:

- `selectNode(_:)` is a one-line collapse into `selectedFileIDs`; its former
  body (content load, history push, recents, inspector auto-hide,
  UserDefaults persistence) moved to private `performLeadChange(to:)`,
  invoked ONLY from `applySelectionChange` when the lead actually changes.
- A `private var isApplyingSelection` flag suppresses the didSet cascade;
  `selectedFileID.didSet` no longer calls `selectNode` — it collapses into
  the Set (legacy external-write path).
- Page-bundle redirect happens in `applySelectionChange` only when
  `selectedFileIDs.count == 1`; multi-selections never redirect.
- Consequences on record: `closeSite()` now also clears the persisted
  last-selected-file key and auto-hides the inspector (via
  `performLeadChange(nil)`) — accepted as correct.
- Runtime verdict on §3's no-op concern: the didSet-internal equality guard
  passed the `withObservationTracking` no-op test on device — no
  guard-before-write restructuring was needed.
- Selection resolution is by ID via `findNode`: only tree-resident nodes can
  become the lead. All production call sites insert before selecting; two
  test fixtures were corrected to match.
