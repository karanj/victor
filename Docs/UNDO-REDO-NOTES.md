# File-operation undo/redo (victor-und)

Implementation notes for the rename / move / duplicate / trash undo chains in
`SiteViewModel`. Extracted from inline comments 2026-07-27.

Four operations register named inverses on the window's `UndoManager`:
`renameFile`, `moveNode`, `duplicateFile`, `moveToTrash(nodes:)`. All four go
through `registerFileOpUndo`, and all four share one FIFO task queue
(`lastFileOpUndoTask`).

## Rule 1 — register the inverse synchronously, before any async work

`UndoManager` decides which stack (`undo` vs `redo`) a `registerUndo` call
lands on by checking `isUndoing` / `isRedoing` **at the moment `registerUndo`
is called**, synchronously — not when the work it registers for finishes.

`registerUndo`'s handler is synchronous, but every file operation here is
`async`. So each handler must register the opposite action *inside itself,
before* spawning the `Task` that does the work. By the time that `Task`
finishes, `isUndoing`/`isRedoing` has already reverted to `false`, and a
registration made then always lands on the undo stack — the redo stack never
gets populated.

The first cut of this feature re-registered from inside the `Task`, at the end
of each operation. Redo silently never worked.

## Rule 2 — serialize the async work through a FIFO queue

`UndoManager` considers an action complete the instant its synchronous handler
returns: `canUndo`/`canRedo` and the Edit menu re-enable immediately, while the
actual file operation is still in flight.

A second Cmd-Z / Cmd-Shift-Z before that `Task` finishes would, with a bare
`Task { }` per handler, spawn a second concurrent `Task` mutating the same
`fileNodes` / `parent.children` — and, for the trash chain, racing reads and
writes of `TrashRecordBox.state`.

`enqueueFileOpUndoWork` makes each closure await the previous one, so the chain
runs strictly in the order the user triggered it. One queue for all four
operation types; correctness doesn't need per-chain parallelism.

## Rule 3 — read `TrashRecordBox.state` at run time, not at fire time

Each re-trash produces a *new* trashed URL per node (macOS uniquifies Trash
filenames on collision), so the state the next chain step needs is only known
once the current step's async work finishes. But by Rule 1, the next step has
to be registered before that work starts. `TrashRecordBox` is a class so every
handler in the chain closes over the same box.

That makes read timing load-bearing: `box.state` must be read **inside** the
closure passed to `enqueueFileOpUndoWork` — i.e. when the queue actually runs
that step — never synchronously in the handler. A handler-time read can observe
a stale generation under rapid undo/redo, because the handler fires before the
previous step's enqueued work has necessarily completed. Rule 2's FIFO ordering
is what makes a run-time read correct.

## Naming

`registerTrashChainUndo` takes an `actionName` and applies it to both sides of
the chain for as long as the chain lives. Without it, a chain built for
`duplicateFile`'s inverse would flip-flop to "Move to Trash" — the name of the
underlying operation — instead of staying "Duplicate".

## Stale references

Node and parent IDs are fixed when a chain is created but re-resolved via
`findNode(id:)` at fire time, since the target may have been renamed, moved or
trashed in the meantime. A failed resolution degrades to `errorMessage` rather
than operating on a stale reference. (Same C.1 note as
`Docs/SELECTION-MODEL-MEMO.md`.)
