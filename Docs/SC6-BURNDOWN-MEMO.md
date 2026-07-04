# WP3.5 Burndown Memo — victor-sc6 (M1) + victor-str (M2)

**Date:** 2026-07-04 · **Baseline:** `Docs/SC6-BASELINE-2026-07-04.txt`, 103 lines captured
2026-07-04 with `SWIFT_STRICT_CONCURRENCY=complete`, `SWIFT_VERSION=5.9`.

Two lines in the baseline are not warnings to fix: line 1 is a macro-expanded
`#Preview` file (`ServerLogView`'s preview calling `setOnOutputChange` —
tracked under Cluster 9, fixed when the preview block is updated), and line
103 is `appintentsmetadataprocessor` build-tool noise, not a diagnostic.
**Actual diagnostic count: 102.** This memo's cluster counts sum to 101; the
1-line discrepancy is rounding across a few multi-message lines (several
baseline lines carry two independent messages at the same location) and is
not worth chasing further — verify against a live `xcodebuild` count at each
checkpoint in Section 3, not against this document.

Read alongside: `Docs/MAC-POLISH-DESIGN.md` §M1/M2, `CLAUDE.md`'s model-type
and service-concurrency tables, `Victor/Models/Frontmatter.swift`'s
`FrontmatterSnapshot` (the in-repo boundary-snapshot exemplar).

---

## 1. Warning clusters

### Cluster 1 — `ContentFile` crossing the FileSystemService/SiteViewModel boundary
**Covers:** 7 warnings — `FileSystemService.swift:316:19`, `:316:24`, `:333:11`
("type 'ContentFile' does not conform to 'Sendable'" ×3); `SiteViewModel.swift`
lines in `saveAllModifiedFiles`/`saveFile` region (~926, ~934, ~991, plus the
adjacent "sending closure" at ~1008) — "sending 'contentFile'" / "sending
'self.fileSystemService'".
**Files:** `Victor/Services/FileSystemService.swift`, `Victor/ViewModels/SiteViewModel.swift`.
**Strategy: boundary snapshot (design-doc priority 1).** `ContentFile` holds a
mutable `Frontmatter` reference and is shared with `FileNode.contentFile`
(CLAUDE.md: must stay a class). It must never cross an `await` as a whole
object. `readContentFile`/`saveContentFile` only ever need `URL` + `String` +
`Date` on the wire — both already Sendable.
**Implementation:**
- `FileSystemService.readContentFile(at:)`: keep the `Task.detached` (or drop
  it per Cluster 2's finding that it's redundant once `FileSystemService` is
  `nonisolated`/Sendable — verify at implementation time), but change its
  *return type* to a private `Sendable` tuple/struct
  `(content: String, modificationDate: Date)`. Parse frontmatter and
  construct the `ContentFile` class instance *after* the value has crossed
  back, in the caller's isolation domain.
- `FileSystemService.saveContentFile(_ file: ContentFile)` → change signature
  to `saveContentFile(url: URL, content: String) async throws`, forwarding to
  the existing `writeFile(to:content:)`. This is a pure snapshot-at-signature
  change — no new struct type needed since the two primitives are already
  Sendable.
- Call sites in `SiteViewModel.saveAllModifiedFiles()` / `saveFile(node:content:)`:
  extract `let url = contentFile.url; let content = contentFile.fullContent`
  **after** any pending edited-content sync (`contentFile.markdownContent = editedContent`)
  and **before** the `await` — see Risk Notes §5, this ordering is
  safety-critical, not cosmetic.

### Cluster 2 — Non-Sendable `static let shared` service singletons
**Covers:** 8 warnings — `ArchetypeManager.swift:5:16`, `DataFileParser.swift:7:16`,
`FileSystemService.swift:6:16`, `FrontmatterParser.swift:34:16`,
`HugoConfigParser.swift:7:16`, `Logger.swift:18:16`, `MarkdownRenderer.swift:8:16`,
`TemplateParser.swift:5:16`.
**Files:** the 8 listed above.
**Strategy: Sendable conformance (priority 3), not @MainActor.** Verified by
reading every one of these classes: none has mutable stored instance state
except `Logger.minLevel` (a `var`, but assigned once via `#if DEBUG` and never
reassigned elsewhere — change to `let`). Every other class holds only
`private init()` + methods with local `var`s. `FrontmatterParser` in
particular is called from inside `FileSystemService.readContentFile`'s
background block — it **must** stay callable off the main actor, so
`@MainActor` is disqualified for this cluster; that's a real, not merely
mechanical, reason to depart from applying priority 2 here.
**Implementation:** `final class Foo: @unchecked Sendable` for all 8 (plain
`Sendable` for `Logger` once `minLevel` is `let`, since `OSLog` is itself
Sendable). Do not touch `DataFile`/`Template`/`Archetype`/`ContentFile`
returned or consumed by these parsers — those stay non-Sendable classes
(Cluster 13 handles the higher-level model-touching methods separately).

### Cluster 3 — Cascade: `self.fileSystemService` sends
**Covers:** 9 warnings — `FileOperationsService.swift:29,36,48,55,63` (all
"sending 'self.fileSystemService'"); `SiteViewModel.swift` ~1075, plus two
more folded into Cluster 1's count above (`:934`, `:991` also mention
`fileSystemService`).
**Files:** `Victor/Services/FileOperationsService.swift`, `Victor/ViewModels/SiteViewModel.swift`.
**Strategy:** no work required beyond Cluster 2. Once `FileSystemService`
conforms to `Sendable`, every one of these disappears automatically — they
are all `try await fileSystemService.someMethod(...)` calls where the only
non-Sendable value crossing the `await` was the service reference itself.
**Verify, don't re-derive:** rebuild after Cluster 2 and confirm these lines
are gone before spending time on them directly.

### Cluster 4 — `HugoSite` Sendable/Task.detached
**Covers:** 5 warnings — `HugoSite.swift:30:15`, `:30:20`, `:47:11`, `:53:20`.
**Files:** `Victor/Models/HugoSite.swift`.
**Strategy: departure from priority order — remove the boundary, don't
annotate it.** `HugoSite` is `@Observable` with mutable `var`s
(`contentDirectory`, `configFile`, `theme`, `bookmarkData`), so Sendable
conformance is wrong (it would be a lie), and it's a model class so it stays
a class per CLAUDE.md. But `HugoSite.create(rootURL:)` and
`validateAsync()` wrap trivial, fast `FileManager.fileExists` checks in
`Task.detached` for no real reason — there is no actor to hop off of, so the
detachment itself is manufacturing the `Sendable` requirement
(`Task<Success, Failure>` requires `Success: Sendable`). This is normally
M3/victor-tdt territory, but here the *only* correct fix is exactly M3's
prescription, scoped to these two functions — see Hands-off §4 for why this
doesn't license a broader Task.detached audit.
**Implementation:** delete both `Task.detached { ... }.value` wrappers;
`create` becomes a plain nonisolated `static func create(rootURL:) async -> HugoSite`
that runs the same body directly (still off the caller's actor since neither
`HugoSite` nor the function is actor-isolated), `validateAsync()` likewise.

### Cluster 5 — `AssetService` actor ↔ `Asset` class boundary
**Covers:** 11 warnings — `AssetService.swift:92,104,111,125,126` (×9, matches
the design doc's "AssetService (9)" hotspot) + `AssetBrowserView.swift:235,240`
(actor-isolated `[Asset]` return + "sending 'initialBatch'").
**Files:** `Victor/Services/AssetService.swift`, `Victor/Views/AssetBrowser/AssetBrowserView.swift`.
**Strategy: boundary snapshot, both directions.** `Asset` is `@Observable`
with lazy mutable properties (`thumbnail`, `fileSize`, `dimensions`,
`modificationDate`, `isMetadataLoaded`) bound directly into
`AssetDetailPanel`/`AssetBrowserView` — it stays a class, full stop. Today
the actor reaches across with `await MainActor.run { asset.fileSize = ... }`,
which is the anti-pattern the design doc's priority list exists to kill.
**Implementation:**
- Add a `Sendable` `AssetMetadataSnapshot { let fileSize: Int64?; let modificationDate: Date?; let dimensions: CGSize? }`
  (thumbnail excluded — `NSImage` isn't Sendable and thumbnail generation can
  stay `@MainActor`-side, see below) plus a plain `Sendable` `AssetDescriptor { let url: URL; let relativePath: String; let isInAssetsDir: Bool }`.
- `scanAssets(in:isAssetsDir:)` returns `[AssetDescriptor]`, not `[Asset]`.
  The `@MainActor` caller (`AssetBrowserView.loadAssets()`) constructs
  `Asset` instances from the descriptors.
- `loadAssetMetadata` becomes `func metadataSnapshot(for url: URL) async -> AssetMetadataSnapshot?`
  (actor-only, reads `FileManager`/`NSImage`, no `asset` parameter, no
  `MainActor.run`). Move the `guard !asset.isMetadataLoaded` short-circuit to
  the `@MainActor` call site (before invoking the actor) — see Risk Notes §5,
  this changes where the de-dup check lives and needs a scroll-stress test.
  The caller applies the snapshot to the `Asset` instance and generates/caches
  the thumbnail (`NSImage`-based drawing) on the main actor after the actor
  call returns, using the existing `generateThumbnail`/`getThumbnail` logic
  moved or duplicated as a `@MainActor` helper — do not try to make `NSImage`
  Sendable.
- `loadMetadataForAssets`'s `withTaskGroup` becomes a group of
  `metadataSnapshot(for:)` calls keyed by URL, same batching, applied back on
  `@MainActor` in one pass.

### Cluster 6 — `GlobalSearchView` sends the live `FileNode` tree into an actor
**Covers:** 1 warning — `GlobalSearchView.swift:315:54`.
**Files:** `Victor/Views/GlobalSearch/GlobalSearchView.swift`, `Victor/Services/SearchService.swift`.
**Strategy: snapshot, not `sending` parameter.** `FileNode` has `weak var parent`
and recursive children (CLAUDE.md: must stay a class, can't be Sendable). A
`sending [FileNode]` parameter was considered but rejected: `fileNodes` is a
long-lived `SiteViewModel` property still read elsewhere after this call
returns, so the compiler can't prove exclusive transfer — `sending` would
not type-check here anyway.
**Implementation:** `SearchService.search(options:in:siteRootURL:)` changes
its second parameter from `[FileNode]` to a pre-extracted `[URL]` (markdown
file URLs, filtered by `scope` before the call, on `@MainActor`). The actor
reads files by URL and never touches a `FileNode` reference.

### Cluster 7 — `FileRowView: View, Equatable`
**Covers:** 1 warning — `FileListView.swift:150:27`.
**Files:** `Victor/Views/MainWindow/FileListView.swift`.
**Strategy: explicit `nonisolated`, a fourth tool not named in the design
doc's three.** `FileRowView` conforms to both `View` (whose `body` requirement
carries an implicit `@MainActor`) and `Equatable`. The synthesized/declared
`static func ==` inherits the type's inferred main-actor isolation, but
`Equatable`'s requirement is nonisolated by contract — that mismatch is
exactly what the warning names. `node.contentStatuses` isn't itself
actor-isolated (`FileNode` is a plain class), so there's nothing to snapshot;
the fix is annotation-only.
**Implementation:** `nonisolated static func ==(lhs: FileRowView, rhs: FileRowView) -> Bool`.

### Cluster 8 — `AutoSaveService` callback parameters missing `@Sendable`
**Covers:** 3 warnings — `EditorViewModel.swift:202:42` (×3: `@MainActor () -> ConflictResolution`,
`@MainActor (any Error) -> Void`, `@MainActor (Date) -> Void`).
**Files:** `Victor/Services/AutoSaveService.swift`, `Victor/ViewModels/EditorViewModel.swift`.
**Strategy: @MainActor is already applied (priority 2) — the missing piece is
`@Sendable` on the closure *type*.** `@MainActor` alone describes where a
closure runs; it doesn't make the closure value itself legal to hand across
the actor boundary into `AutoSaveService`'s isolated storage. This is
distinct from Cluster 9 — `AutoSaveService` isn't in M2's scope (design doc
names only `HugoServerService`/`LiveReloadClient` for the AsyncStream
conversion), and its per-call closure shape doesn't have the same
multi-consumer registry problem, so leave it as callbacks.
**Implementation:** in `AutoSaveService.scheduleAutoSave(...)`, change every
callback parameter from `@escaping @MainActor (...) -> T` to
`@escaping @Sendable @MainActor (...) -> T`. No call-site changes needed —
the closure literals in `EditorViewModel.scheduleAutoSave()` (already
`@MainActor [weak self] in ...`) already satisfy `@Sendable` since they only
capture `weak self`, `nodeID`, `nodeURL` (a `UUID`/`URL`, both Sendable) plus
`self` itself, and `@MainActor`-isolated classes are safely capturable in
`@Sendable` closures (isolation, not `Sendable` conformance, is what
provides the safety guarantee there).

### Cluster 9 — HugoServerService/LiveReloadClient callback registries → AsyncStream
**Covers:** 14 warnings — `SiteViewModel.swift` ~1375/1383 (2), `LivePreviewPanel.swift:190,197×2,227×2`
(5), `ServerControlView.swift:234,240` (2), `ServerLogView.swift:171` (1) +
its `#Preview` macro expansion (baseline line 1), `LiveReloadClient.swift:261,275,284`
(3, "sending 'callback'").
**Files:** `Victor/Services/HugoServerService.swift`, `Victor/Services/LiveReloadClient.swift`,
`Victor/ViewModels/SiteViewModel.swift`, `Victor/Views/Preview/LivePreviewPanel.swift`,
`Victor/Views/ServerControls/ServerControlView.swift`, `Victor/Views/ServerControls/ServerLogView.swift`.
**Strategy:** structural replacement, not annotation. Full design in §2.
**Note the constraint that shapes this cluster's fix:** `ServerLogView` opens
in a second SwiftUI `Window("Server Logs", id: "server-logs")` scene
(`VictorApp.swift:639`) that receives **no** `SiteViewModel` — verified by
reading `VictorApp.swift`. Any design that consolidates all four observers
into "SiteViewModel is the only actor consumer, everyone else reads
`SiteViewModel`" is a non-starter without also plumbing `SiteViewModel` into
that window scene (out of scope — see Hands-off §4). All four consumers stay
independent.

### Cluster 10 — Delegate method signatures drifted from SDK's concurrency-checked protocols
**Covers:** 3 warnings — `LiveReloadClient.swift:36:10`, `LivePreviewPanel.swift:395:14`,
`PreviewWebView.swift:71:14` ("nearly matches optional requirement").
**Files:** the three above.
**Strategy: exact signature match, case by case — no single annotation fixes
all three.** These are `URLSessionDelegate.urlSession(_:didReceive:completionHandler:)`
and `WKNavigationDelegate.webView(_:decidePolicyFor:decisionHandler:)`
overrides whose closure-parameter attributes (`@Sendable`, and possibly
isolation) no longer exactly match the SDK's concurrency-annotated protocol
requirement, so Swift treats them as non-overriding lookalikes rather than
conformances.
**Implementation:** at each site, use Xcode's "add missing conformance"
fix-it (or diff against the current `WebKit`/`Foundation` interface headers)
to copy the exact expected signature, including `@escaping @MainActor @Sendable`
on the decision/completion handler. Do not hand-guess the attribute
combination — verify each one compiles with a full rebuild, not just a
syntax-level read, since these three are easy to get subtly wrong (e.g.
`@Sendable` without `@MainActor`, or vice versa).

### Cluster 11 — NSViewRepresentable/Coordinator classes missing `@MainActor`
**Covers:** 31 warnings — `SyntaxHighlightedTextView.swift:100,102,106,95` (4);
`EditorTextView.swift:38,424×2,426×2,484,507,508,512,537,543,545,546,547,551` (15,
matches the design doc's "EditorTextView (15)" hotspot exactly);
`TextEditorPanel.swift:218,223,225` (3); `FocusModeView.swift:209×2,240` (3);
`TemplateEditorView.swift:228,233,235,242` (4); `VictorApp.swift:23×2` (2, via
`FindPanelHelper`).
**Files:** the 6 above.
**Strategy: @MainActor annotation (priority 2) — this is the textbook case
the priority order is written for.** Every one of these is a plain
`class Coordinator: NSObject, NSTextViewDelegate` (or, for `VictorApp`, a
plain `enum` with a `static func`) that calls MainActor-isolated AppKit
accessors (`textStorage`, `font`, `delegate`, `window`, `string`,
`selectedRange()`, `makeFirstResponder`, `registerForDraggedTypes`,
`NSApp.sendAction`) from methods the compiler considers nonisolated because
nothing declares otherwise. There is no boundary-crossing value here to
snapshot and no Sendable question — the fix is telling the type-checker
where these already-single-threaded classes actually run.
**Implementation:**
- Mark every `Coordinator` class `@MainActor` in: `SyntaxHighlightedTextView`,
  `EditorTextView` (also mark `HighlightingTextView: NSTextView` itself
  `@MainActor` if its drag-and-drop overrides still warn after the
  Coordinator fix — NSView subclasses inherit `@MainActor` from the SDK in
  most cases, but confirm), `TextEditorPanel`'s `TextEditorTextView.Coordinator`,
  `FocusModeView`'s `FocusModeEditor.Coordinator`, `TemplateEditorView`'s
  `TemplateTextView.Coordinator`.
- Mark `FindPanelHelper` (`VictorApp.swift`) `@MainActor` — its two static
  funcs call `NSApp.sendAction`.
- Replace every `DispatchQueue.main.async { ... }` / `RunLoop.main.perform { ... }`
  inside these files that touches MainActor state (`EditorTextView.swift`
  lines ~489, ~499; `FocusModeView.swift` line ~208) with `Task { @MainActor in ... }`
  so isolation is provable, not merely scheduled-and-hoped-for.
- **Side effect, verify don't re-derive:** once a `Coordinator` class is
  `@MainActor`, its `Timer.scheduledTimer` closures capturing `[weak self]`
  (`SyntaxHighlightedTextView.swift:95`, `TextEditorPanel.swift:218`,
  `TemplateEditorView.swift:228`) stop warning too — a `@MainActor`-isolated
  class is safely capturable in a `@Sendable` closure because the actor
  provides the safety guarantee, not a `Sendable` conformance. Don't spend
  separate effort on these lines; confirm they're gone after the
  `@MainActor` pass.
- **`deinit` mutating `delegate`/`navigationDelegate`:** `FocusModeView`'s
  `Coordinator.deinit { textView?.delegate = nil }` and `PreviewWebView`'s
  `Coordinator.deinit { webView?.navigationDelegate = nil }` cannot
  synchronously touch `@MainActor` state from `deinit` (nonisolated by
  construction). First check whether `NSTextView.delegate`/`WKWebView.navigationDelegate`
  are `weak` in the SDK — if so, this manual nil-out is already redundant
  and can simply be deleted. If not provably redundant, replace with a
  fire-and-forget `Task { @MainActor [weak textView] in textView?.delegate = nil } }`
  from `deinit` instead of a synchronous mutation.

### Cluster 12 — `FocusModeView`'s `PreferenceKey` global mutable state
**Covers:** 1 warning — `FocusModeView.swift:63:16`.
**Files:** `Victor/Views/FocusMode/FocusModeView.swift`.
**Strategy: Sendable-adjacent triviality — change `var` to `let`.**
`ScrollOffsetPreferenceKey.defaultValue` never mutates; `PreferenceKey`'s
`{ get }` requirement is satisfiable by a `static let`.
**Implementation:** `static let defaultValue: CGFloat = 0`.

### Cluster 13 — Model-touching parser methods sending `DataFile`/`Template`/`Archetype`
**Covers:** 7 warnings — `SpecializedFileManager.swift:144,191` (2);
`DataFileParser.swift:122` (1); `TemplateParser.swift:61` (2, capture +
send); `TemplateEditorView.swift:114` (1); `NewContentView.swift:158` (1).
**Files:** `Victor/Services/DataFileParser.swift`, `Victor/Services/TemplateParser.swift`,
`Victor/Services/ArchetypeManager.swift`, `Victor/ViewModels/SpecializedFileManager.swift`,
`Victor/Views/TemplateEditor/TemplateEditorView.swift`, `Victor/Views/NewContent/NewContentView.swift`.
**Strategy: @MainActor on the model classes themselves — a deliberate,
disclosed departure from applying Cluster 2's "parsers stay off-main"
reasoning uniformly.** `DataFile`, `Template`, and `Archetype` (unlike
`ContentFile`/`Frontmatter`) are *only* ever constructed and mutated from
`@MainActor` call sites today — they're `@Observable`, `EditableFile`,
`@Bindable`-bound directly into the Config/Data/Template/Archetype editor
forms (CLAUDE.md's model table). `TemplateParser.swift:61`'s warning is
literally `await MainActor.run { template.markAsSaved() }` capturing a
non-Sendable `Template` in a `@Sendable` closure — the honest fix is to stop
needing the `MainActor.run` hop at all by making `Template` (and `DataFile`,
`Archetype`) `@MainActor` classes outright, which also directly resolves the
"sending dataFile/template/archetype" warnings at the other five call sites
(passing a `@MainActor`-isolated value into an `await`-ed call from another
`@MainActor` context is not a cross-isolation send).
**Implementation:**
- Add `@MainActor` to `class DataFile`, `class Template`, `class Archetype`.
- `DataFileParser.parseDataFile(at:)` / `.save(_:)`, `TemplateParser.parseTemplate(at:)` / `.save(_:)`,
  `ArchetypeManager.parseArchetype(at:)` / `.createContent(from:...)` become
  `@MainActor` methods (they already only run from `@MainActor` callers).
  Keep the raw, format-only helpers non-isolated and `Sendable`-clean per
  Cluster 2: `DataFileParser.parse(content:format:)`, `.serialize(data:format:)`,
  `TemplateParser.extractMetadata(from:)`, and the file-reading `Task.detached`
  blocks inside `save`/`parseArchetype`/`parseDataFile` stay as they are,
  capturing only `url`/`content` (`Sendable` primitives) rather than the
  model object — this is the one line-level change needed in each of
  `DataFileParser.save`, `ArchetypeManager.parseArchetype`,
  `ArchetypeManager.createContent`: capture `dataFile.url`/`archetype`'s
  needed primitives *before* entering `Task.detached`, never the model
  object itself.

---

## 2. M2 design — HugoServerService AsyncStream + LiveReloadClient event stream + `bytes.lines`

### Why not a single shared `AsyncStream` property
`AsyncStream` is single-consumer: if two `for await` loops iterate the same
stream, elements are split between them, not broadcast to both. Today four
independent places call `setOnStatusChange`/`setOnBuildErrorsChange`/`setOnOutputChange`
(`SiteViewModel`, `LivePreviewPanel`, `ServerControlView`, `ServerLogView`),
and `ServerLogView` lives in a separate `Window` scene with no `SiteViewModel`
in its environment (`VictorApp.swift:639`) — so consolidating to one consumer
that republishes isn't available. The registries are being replaced
one-for-one by **stream factories**: each call creates an independent
stream+continuation pair, preserving today's actual multicast behavior.

### HugoServerService public API
```swift
actor HugoServerService {
    // Deleted entirely: statusChangeCallbacks/buildErrorsChangeCallbacks/
    // outputChangeCallbacks dictionaries and all 9 addOn*/removeOn*/setOn*
    // methods.

    private var statusContinuations: [UUID: AsyncStream<HugoServerStatus>.Continuation] = [:]
    private var buildErrorContinuations: [UUID: AsyncStream<[HugoBuildError]>.Continuation] = [:]
    private var outputContinuations: [UUID: AsyncStream<[String]>.Continuation] = [:]

    /// New independent stream of status changes. Replays the current value
    /// immediately so a late subscriber (e.g. Server Logs window opened
    /// after the server already started) doesn't have to separately fetch
    /// `status` first.
    func statusUpdates() -> AsyncStream<HugoServerStatus> {
        let (stream, continuation) = AsyncStream.makeStream(of: HugoServerStatus.self)
        let id = UUID()
        statusContinuations[id] = continuation
        continuation.yield(status)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeStatusContinuation(id) }
        }
        return stream
    }
    func buildErrorUpdates() -> AsyncStream<[HugoBuildError]>   // same shape, replays buildErrors
    func outputUpdates() -> AsyncStream<[String]>               // same shape, replays serverOutput

    private func removeStatusContinuation(_ id: UUID) { statusContinuations.removeValue(forKey: id) }
    // + removeBuildErrorContinuation, removeOutputContinuation

    // notifyStatusChange/notifyBuildErrorsChange/notifyOutputChange now
    // `.yield()` to every continuation in the relevant dictionary instead of
    // `await`-calling stored closures.
}
```
Cancellation/ownership rule: **the consuming `Task`'s cancellation is the
only deregistration mechanism.** Cancelling (or letting a SwiftUI `.task {}`
tear down when its view disappears) ends the `for await` loop; `AsyncStream`
calls `onTermination` on the actor, which removes that continuation. No
caller ever calls a `removeOnXChange(id:)`-shaped method again — there isn't
one.

### `SiteViewModel.setupHugoServerObservers()`
Becomes two owned observation tasks:
```swift
private var statusObservationTask: Task<Void, Never>?
private var buildErrorsObservationTask: Task<Void, Never>?

func setupHugoServerObservers() {
    statusObservationTask = Task { [weak self] in
        guard let stream = await self?.hugoServerService.statusUpdates() else { return }
        for await status in stream {
            guard let self else { return }
            self.hugoServerStatus = status
            if status.isRunning { self.useLivePreview = true }
        }
    }
    buildErrorsObservationTask = Task { [weak self] in
        guard let stream = await self?.hugoServerService.buildErrorUpdates() else { return }
        for await errors in stream {
            self?.hugoBuildErrors = errors
        }
    }
}
```
`SiteViewModel` lives for the app's lifetime (owned by `VictorApp`'s
`@State`), so these tasks run until app termination; no explicit teardown
call is required, but store the `Task` handles anyway (testability, and in
case a future "close site without quitting" path wants to cancel them).
This deletes the separate "get initial state" boilerplate
(`let initialStatus = await HugoServerService.shared.status` etc.) — the
replay-on-subscribe behavior in `statusUpdates()`/`buildErrorUpdates()`
already delivers current state as the first stream element.

### `LivePreviewPanel`, `ServerControlView`, `ServerLogView`
Each converts its `setupXCallback()` function into a `.task { }` (or,
if already inside one, an inline `for await` loop) against
`HugoServerService.shared.statusUpdates()` / `.buildErrorUpdates()` /
`.outputUpdates()` directly — same independent-consumer shape as
`SiteViewModel`, just not routed through it (Cluster 9's environment
constraint above). Using SwiftUI's `.task {}` instead of a bare `Task {}`
inside `.onAppear`-style setup means the observation task is automatically
cancelled when the view disappears, which is a strict improvement over
today (today's `Task { await HugoServerService.shared.setOnStatusChange { ... } }`
never deregisters — every window open leaks a registration for its lifetime;
`.task {}` + `onTermination` fixes that as a side effect).

### `LiveReloadClient` event stream
```swift
enum LiveReloadEvent: Sendable {
    case navigate(String)
    case reload
}

actor LiveReloadClient {
    private var eventContinuations: [UUID: AsyncStream<LiveReloadEvent>.Continuation] = [:]

    func events() -> AsyncStream<LiveReloadEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: LiveReloadEvent.self)
        let id = UUID()
        eventContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in Task { await self?.removeEventContinuation(id) } }
        return stream
    }

    // connect(to:) drops the onNavigate/onReload parameters entirely.
    func connect(to serverURL: URL) { ... }
}
```
`handleReload`/`handleMessage` replace `Task { @MainActor in callback(path) } }`
with `for continuation in eventContinuations.values { continuation.yield(.navigate(path)) }`
(and `.reload` for the no-path case) — plain actor-local iteration, no
`@MainActor` closures stored or passed anywhere.

`ServerControlView`'s `setupServerStateObservers()`/`refreshServerState()`
(the two call sites that currently call `LiveReloadClient.shared.connect(to:onNavigate:onReload:)`)
collapse into:
```swift
.task(id: serverURL) {
    guard let url = serverURL else { return }
    await LiveReloadClient.shared.connect(to: url)
    for await event in await LiveReloadClient.shared.events() {
        switch event {
        case .navigate(let path): liveReloadNavigatePath = path
        case .reload: reloadTrigger += 1
        }
    }
}
```

### `Pipe.readabilityHandler` → `fileHandleForReading.bytes.lines`
```swift
private var stdoutTask: Task<Void, Never>?
private var stderrTask: Task<Void, Never>?

private func setupOutputHandlers(outputPipe: Pipe, errorPipe: Pipe) {
    stdoutTask = Task { [weak self] in
        do {
            for try await line in outputPipe.fileHandleForReading.bytes.lines {
                guard let self else { return }
                await self.processLine(line, isError: false)
            }
        } catch {
            await self?.logPumpFailure(error, isError: false)
        }
    }
    stderrTask = Task { [weak self] in
        do {
            for try await line in errorPipe.fileHandleForReading.bytes.lines {
                guard let self else { return }
                await self.processLine(line, isError: true)
            }
        } catch {
            await self?.logPumpFailure(error, isError: true)
        }
    }
}
```
- `processOutput(_:isError:)` + its internal `.components(separatedBy: .newlines)`
  split collapse into one `processLine(_ line: String, isError: Bool)` since
  `.bytes.lines` already yields one line at a time — delete the manual
  splitting/filtering.
- **EOF:** when the process exits and the pipe's write end closes, `.lines`
  simply finishes the sequence — the `for try await` loop exits normally, no
  error, no special-casing needed.
- **Error path:** a genuine read error (rare — bad descriptor) throws out of
  the loop; caught and logged via `logPumpFailure`, matching today's silent
  swallow-and-continue behavior for parse errors elsewhere in this file.
- **`stop()` interaction:** replace
  `outputPipe?.fileHandleForReading.readabilityHandler = nil` /
  `errorPipe?.fileHandleForReading.readabilityHandler = nil` with
  `stdoutTask?.cancel(); stderrTask?.cancel()` **before** `process.terminate()`,
  same ordering as today (stop pumping before tearing down the process so no
  stray reads fire after the intentional stop). `AsyncLineSequence` checks
  cancellation cooperatively between lines. Set both task properties to `nil`
  afterward, mirroring the existing pipe-property cleanup.
- **`handleProcessTermination`:** replace its
  `outputPipe?.fileHandleForReading.readabilityHandler = nil` lines with the
  same `stdoutTask?.cancel()`/`stderrTask?.cancel()` pair, for the crash path
  (process dies without `stop()` being called).

### What this conversion deletes outright
All of Cluster 9 (14 warnings) — every stored `@MainActor (...) -> Void`
closure in `HugoServerService`/`LiveReloadClient` is gone, so there is
nothing left to warn about "sending" across the actor boundary. It does
**not** touch Cluster 8 (`AutoSaveService`, different service, different
shape) or Cluster 10 (the `URLSessionDelegate`/`WKNavigationDelegate`
signature-drift warnings, which are a separate mechanism from the callback
registries).

---

## 3. Execution order for WP3.5

Numbered so each step's expected post-fix warning count is checkable against
a real `xcodebuild` run — treat the counts below as checkpoints, not promises;
verify at each step rather than trusting the arithmetic blind.

1. **Cluster 2 + 3 + 4** (parser/service singleton Sendable pass, its
   cascade, `HugoSite` Task.detached removal). Purely additive annotations
   plus two small deletions — lowest risk, unlocks the rest. Build.
   Expected: 103 → ~81.
2. **Cluster 1** (`ContentFile` snapshot at the FileSystemService/SiteViewModel
   boundary). Depends on Cluster 2 being done first (touches the same
   `FileSystemService` file). Build + run the app, edit a file, Save All,
   diff on-disk bytes against editor content (see Risk Notes §5 — this is
   the one place a subtle ordering bug reintroduces a P0-class save race).
   Expected: ~81 → ~74.
3. **Cluster 13** (`DataFile`/`Template`/`Archetype` → `@MainActor`, parser
   method re-isolation). Build + open each of the Data/Template/Archetype
   editors, edit and save one file of each kind. Expected: ~74 → ~67.
4. **Cluster 8** (`AutoSaveService` closure `@Sendable` annotations).
   Mechanical, no call-site changes. Build. Expected: ~67 → ~64.
5. **Cluster 11** (`@MainActor` on every Coordinator/`NSViewRepresentable`
   helper + `FindPanelHelper`). The single largest cluster — do it in one
   pass across all 6 files, then one build, not file-by-file builds (the
   fixes are structurally identical; incremental builds here waste time).
   After the build, manually exercise: markdown editor typing + drag-drop
   image insert, text editor panel, focus mode entry/exit, template editor
   syntax highlighting + save. Expected: ~64 → ~33.
6. **Clusters 12, 7, 6** (PreferenceKey `let`, `FileRowView` `nonisolated ==`,
   `GlobalSearchView` URL-snapshot into `SearchService`). Independent
   one-liners/small edits, batch together. Build + run a global search.
   Expected: ~33 → ~30.
7. **Cluster 5** (`AssetService` snapshot conversion, both directions).
   The most invasive single-file change after Cluster 9 — do it in isolation
   with its own build. Manually test: open asset browser, scroll the grid
   fast (metadata-load de-dup risk, see Risk Notes §5), open an image detail
   panel, confirm thumbnails render once each with no flicker/duplicate
   work. Expected: ~30 → ~19.
8. **Cluster 10** (delegate signature drift, 3 sites). Fix one at a time with
   Xcode's fix-it, rebuild after each — these are easy to get wrong silently
   (a `@Sendable`/`@MainActor` combination that compiles but changes calling
   convention). Expected: ~19 → ~16.
9. **Cluster 9 + the M2 design in §2** (HugoServerService/LiveReloadClient
   AsyncStream conversion, `Pipe.bytes.lines`). Do this last among the
   clusters — it's the largest behavioral change, and by this point every
   other file it might interact with (SiteViewModel, LivePreviewPanel) is
   already warning-clean, so this pass isn't fighting other in-flight edits.
   Full manual server lifecycle test per Risk Notes §5. Expected: ~16 → 0.
10. **Verification sweep.** Clean-build (`xcodebuild clean build`) and
    confirm literally 0 warnings twice in a row (a flaky/incremental build
    can under-report). Run the full test suite
    (`xcodebuild test -project Victor.xcodeproj -scheme Victor -destination 'platform=macOS'`).
11. **Flip `SWIFT_VERSION` to `6.0`** in `project.yml`, `xcodegen generate`,
    clean build. At 0 warnings under Swift 5 strict-concurrency-complete,
    this should produce 0 errors under Swift 6 mode by construction — if it
    doesn't, something in steps 1–9 was papered over rather than fixed, and
    that's a signal to go back, not to add a suppression.

---

## 4. Hands-off list — do not do these in WP3.5

- **No model struct rewrites.** `ContentFile`, `FileNode`, `Frontmatter`,
  `DataFile`, `Template`, `Archetype`, `Asset` all stay classes. `@MainActor`
  on `DataFile`/`Template`/`Archetype` (Cluster 13) is an isolation
  attribute, not a value-type conversion — CLAUDE.md's binding/tree-identity
  rationale is unaffected and still governs.
- **No broader Task.detached audit.** WP3.5 touches exactly four
  `Task.detached` call sites, each because it's the direct, sole cause of a
  cluster's warning: `HugoSite.create`/`validateAsync` (Cluster 4), and the
  file-write blocks inside `DataFileParser.save`/`ArchetypeManager.parseArchetype`/`.createContent`
  (Cluster 13, capture-only-primitives fix). The other ~15 `Task.detached`
  sites across the codebase (victor-tdt/M3, ticketed separately, "0.5d,
  mechanical") are out of scope even if you're already in a neighboring file.
- **No M4 grab-bag items.** `Logger`'s `os_log`→`os.Logger` migration,
  `DateFormatter`→`Date.FormatStyle`, the `NSFileCoordinator` continuation
  helper unification, `DispatchQueue.asyncAfter`→`Task.sleep` — all
  victor-mod, all separate. The only `DispatchQueue.main.async`/`RunLoop.main.perform`
  sites WP3.5 touches are the ones inside Cluster 11's files that are
  literally emitting a warning, and the only change there is wrapping in
  `Task { @MainActor in }` — not re-timing or otherwise improving the logic.
- **No consolidation of HugoServerService's four independent observers into
  a single SiteViewModel-owned source of truth.** `ServerLogView`'s separate
  `Window` scene has no `SiteViewModel` in its environment today (verified,
  `VictorApp.swift:639`). Plumbing it in is legitimate future work but is a
  UI/dependency-injection change, not a concurrency fix — don't fold it into
  this ticket.
- **No `@unchecked Sendable` stamping of mutable model classes** as a
  shortcut anywhere in Clusters 1, 4, 5, 6, 7, or 13. Only the 8 genuinely
  stateless service singletons in Cluster 2 get Sendable conformance.
- **Don't redesign the `#Preview` blocks** in `ServerLogView.swift` beyond
  the minimum edit needed to compile against the new `AsyncStream`-based API
  (Cluster 9).
- **Don't flip `SWIFT_VERSION` to 6.0 speculatively mid-burndown** to "see
  what breaks." Do it once, at the end (step 11), after two clean 0-warning
  builds.

---

## 5. Risk notes — behavior, not just types, can change here

**Cluster 9 / M2 (HugoServerService + LiveReloadClient AsyncStream
conversion) — highest risk.** This is a structural rewrite of the app's only
live-status plumbing, touched by four independent UI surfaces. Test
explicitly, manually, beyond unit tests:
- Start/stop the Hugo server repeatedly; confirm the toolbar server-status
  indicator, `LivePreviewPanel`, `ServerControlView`, and a freshly-opened
  Server Logs window (`Cmd`-triggered *after* the server is already running)
  all show correct, current state — the replay-on-subscribe behavior is what
  makes the "open late" case work, and it's new behavior, not a port of
  something that existed before.
- Kill the Hugo subprocess externally (not via the app's Stop button) and
  confirm crash-recovery + the background build-failure notification path
  (`notifyBackgroundBuildFailureIfNeeded`) still fire correctly through the
  new `.yield()`-based notification path.
- Edit a file while the server runs and confirm LiveReload's
  navigate/reload events still drive `LivePreviewPanel` correctly, including
  across a server restart (reconnect path in `LiveReloadClient.establishConnection()`)
  — the `events()` stream's continuations are actor-level state decoupled
  from the WebSocket session lifecycle, so a reconnect should not drop or
  duplicate a consumer's registration, but this is exactly the kind of thing
  that's obvious in a design doc and wrong in practice until observed.

**Cluster 5 (AssetService snapshot conversion) — moderate risk.** Today the
`guard !asset.isMetadataLoaded else return` short-circuit lives inside the
actor method itself, evaluated synchronously against the (non-isolated,
directly-dereferenced) `Asset`. Moving it to the `@MainActor` caller, ahead of
the actor call, changes *where* duplicate-load prevention happens. Test: open
the asset browser and scroll the grid rapidly (SwiftUI re-triggers
`.task { }` on cells re-entering view) — confirm each asset's metadata loads
exactly once, no flicker, no wasted duplicate `NSImage` decodes for the same
URL fired from two overlapping `.task` invocations.

**Cluster 1 (`ContentFile` snapshot at the save boundary) — moderate risk,
but the one most worth over-testing.** `saveAllModifiedFiles()` currently
has an explicit comment about syncing `fileCacheManager`'s edited content
into `contentFile.markdownContent` *before* calling save, because this exact
class of bug (stale content on Save-and-Quit) was already found and fixed
once (see CLAUDE.md's "File Switching Race Conditions" note). Changing
`saveContentFile`'s signature from "takes the `ContentFile` object" to
"takes an extracted `url`/`content` pair" means the extraction point becomes
an explicit line of code instead of implicit (reading `file.fullContent`
inside the callee, after any mutation). Get the two lines
(`contentFile.markdownContent = editedContent` then
`let content = contentFile.fullContent`) in the right order in code review,
and add/re-run a test that edits a file, calls `saveAllModifiedFiles()`, and
asserts the bytes written to disk equal the edited content — not just that
no warning fired.
