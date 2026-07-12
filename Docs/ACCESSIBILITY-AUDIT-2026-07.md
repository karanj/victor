# Accessibility Audit — 2026-07 (victor-3l6, MAC-ARSED-GAP-PLAN Phase D.1)

Static-analysis VoiceOver/accessibility pass across `Victor/Views/`. Two parts:
Part 1 covers the new selection/rename/menu surfaces from this week's
gap-closure work; Part 2 is a backlog sweep of the rest of the app. Icon-only
buttons were already labeled in an earlier pass (victor-0qe) — this audit
does not re-litigate that pass, only gaps it left or introduced since.

All fixes are accessibility-modifier-only (`.accessibilityLabel`,
`.accessibilityValue`, `.accessibilityHint`, `.accessibilityHidden`,
`.accessibilityAddTraits`, `.accessibilityElement(children:)`, plus one
`Button(role:)` and one `AccessibilityNotification.Announcement` post per the
ticket's explicit ask for RenameSheet). No layout, logic, or state changes.
54 files touched, ~140 individual modifier additions.

## Part 1 — New surfaces (priority)

| Surface | Issue | Status | Rationale |
|---|---|---|---|
| `RenameSheet.swift` | "Rename" title not marked as header | Fixed | `.accessibilityAddTraits(.isHeader)` |
| `RenameSheet.swift` | Cancel button had no semantic role | Fixed | `Button("Cancel", role: .cancel)` — VoiceOver announces it as a cancel action |
| `RenameSheet.swift` | Inline validation error (`Text(validationError.message)`) only ever visible, never associated with the field or announced | Fixed | `.accessibilityHint` on the `TextField` carries the constraint when the field is focused; `.onChange(of: validationError)` posts `AccessibilityNotification.Announcement` so a live typo gets announced without the user needing to discover the inline text |
| `FileListView.swift` — `FileRowView` (sidebar rows) | Icon, name, badges (bundle/config/draft/scheduled/expired), and status dot were 5+ separate VoiceOver stops per row; icon's `accessibilityLabel` was only the file-type description, not the filename | Fixed | `.accessibilityElement(children: .combine)` on the row merges icon-type-label + name + badges + `FileStatusIndicator`'s label ("Unsaved changes"/"Recently saved") into one stop — includes both selection-relevant context (name) and file status |
| `FileListView.swift` — batch-trash confirmation alert | Verify pruned count is read correctly | Verified, no fix needed | `trashConfirmationTitle` already computes off `pendingTrashNodes` (post-`pruneDescendants`), a plain SwiftUI `.alert` — title and buttons are read natively and correctly |
| `FileListView.swift` — `SelectionContextMenu` | Verify items are plainly labeled | Verified, no fix needed | Every item is `Label(text, systemImage:)` — visible text, standard menu-item accessibility |
| Drag/drop has no accessible equivalent | Sidebar drag-out (`dragItemProvider`, victor-sel B.4) has no VoiceOver-reachable path to move a file into a folder | **Finding, not fixed** — see below | Out of scope per instructions (list-only) |
| `VictorApp.swift` — Edit-menu additions (Find/Replace, Spelling & Grammar, Substitutions, Transformations, Speech submenus, victor-spl) | Verify menu items are reachable and sensibly titled | Verified, no fix needed | All items are plain-text `Button`/`Toggle`/`Menu` inside `CommandGroup` — standard NSMenu items, inherently accessible, no icon-only entries |
| `FileListView.swift` — `.onDeleteCommand`/`.onCopyCommand` | Keyboard-only accelerators (Delete key, Cmd+C) with no explicit accessibility action | Not fixed — listed in human-pass checklist | These route through standard key-equivalent handling, not custom accessibility actions; whether VoiceOver's rotor "right-click" gesture reaches the same `.contextMenu(forSelectionType:)` reliably needs a live VoiceOver check, not a code fix |

### Drag/drop finding (detail)

Moving a file by drag-and-drop (`FolderRowWithSheets`/`FileRowWithSheets`'s
`.onDrag` + `.dropDestination`, victor-sel B.4) has **no keyboard/VoiceOver
equivalent**. Unlike Rename, Trash, Duplicate, etc. — all of which are also
reachable via the context menu or a keyboard accelerator — moving a file
into a different folder can *only* be done by dragging. A VoiceOver user (or
anyone who can't perform a precise drag gesture) cannot move a file at all
today.

**Recommendation (not implemented, per scope):** add a "Move to Folder…"
item to `SelectionContextMenu`'s single- and multi-target menus, opening a
folder-picker sheet (same sheet pattern as `RenameSheet`/`NewDataFileView`)
that calls into `SiteViewModel`'s existing move/reorganize path. This is a
real feature addition (new sheet, new SiteViewModel method surface), not a
modifier-only fix, so it's out of scope for this ticket — flagging for a
follow-up ticket.

## Part 2 — Backlog sweep

Findings grouped by category. "Fixed" rows are the accessibility-modifier
edits applied; "Recommended" rows need either UX judgment or a structural
change and were deliberately left alone.

### Fixed — icon-only interactive elements missing labels

| Surface | Elements |
|---|---|
| `Components/EditorToolbarButtons.swift` (shared by Config/Data/Translation/Archetype editors) | Save (+ "Saving" value), Reload, Open in Default App, Reveal in Finder |
| `Editor/TextEditorPanel.swift` | Same four toolbar buttons (own copy of the pattern) |
| `MainWindow/SidebarView.swift` | Clear-search button, site-options ellipsis menu |
| `GlobalSearch/GlobalSearchView.swift` | Close, clear-search, clear-replacement, show/hide-replace toggle |
| `Editor/FrontmatterEditorView.swift`, `Inspector/MetadataSection.swift` | Add-tag (+), remove-tag (×) buttons in both the frontmatter-tab and inspector tag inputs |
| `Editor/Components/CustomFieldEditor.swift` | Delete-field button (labeled with the field key) |
| `Editor/Components/MenuEntryEditor.swift` | Remove-from-menu button |
| `ConfigEditor/Tabs/ConfigContentTab.swift` | Remove-permalink-pattern button, insert-token menu |
| `ConfigEditor/Tabs/ConfigTaxonomiesTab.swift` | Remove-taxonomy button (labeled with the taxonomy name) |
| `ConfigEditor/ConfigEditorView.swift` | Reload-from-disk button (raw editor banner) |
| `AssetBrowser/AssetBrowserView.swift` | Refresh-assets button |
| `TemplateEditor/TemplateBrowserView.swift` | Clear-search, refresh-templates buttons |
| `DataEditor/DataFileEditorView.swift` | Move-up/move-down/delete-item buttons (array items), delete-field button (object fields) |
| `TranslationEditor/TranslationEditorView.swift` | Clear-search, show-plural-forms (+ value), delete-translation buttons |
| `Viewers/ImageViewerPanel.swift`, `Viewers/TextViewerPanel.swift` | Zoom in/out, open-in-default-app, reveal-in-Finder, copy-path buttons |
| `Viewers/FolderContentsView.swift` | Reveal-in-Finder button; grid/list view-mode picker segments (icon-only, now labeled "Grid"/"List") |
| `Editor/ShortcodePickerView.swift` | Clear-search button |
| `Editor/ShortcodeFormView.swift` | Required-field asterisk now reads "required" instead of a bare glyph |
| `AssetBrowser/AssetDetailPanel.swift` | Copy-to-clipboard feedback (see announcements below) |
| `ArchetypeEditor/ArchetypeHelpPanel.swift` | Two copy buttons (variable / example) |
| `ArchetypeEditor/ArchetypeEditorView.swift` | Help-panel toggle (+ shown/hidden value) |
| `Shared/BuildIssuesPopover.swift` | Dismiss button; per-issue severity icon now reads "Error"/"Warning"/"Info" (previously conveyed only by color) |
| `Components/LabeledTextField.swift` (shared by several forms) | All three variants' `TextField`s now carry the visible label text as `accessibilityLabel` — previously only visually associated |

### Fixed — missing `.accessibilityValue` on stateful/status controls

| Surface | Control |
|---|---|
| `ServerControls/ServerControlView.swift` | Toolbar server-status dot+text → combined element, label "Server status", value = running/stopped/starting/error text; decorative dot hidden |
| `ServerControls/ServerControlView.swift` | Build-error/warning badge now has an explicit label distinguishing "error" vs "warning" (previously conveyed only by red/orange color) |
| `MainWindow/TabBarView.swift` | Build-issues pill's label aligned to the same error/warning wording |
| `Preview/LivePreviewPanel.swift` | Nav-toolbar server-status dot+text → same combine/value treatment as `ServerControlView` |
| `Preview/LivePreviewPanel.swift` | URL-display group combined into one element |
| `Preferences/PreferencesView.swift` | Hugo-installed status row (checkmark/xmark + text) combined; version row combined; Default Port field now labeled |
| `MainWindow/FrontmatterBottomPanel.swift` | Collapsible header now reports Expanded/Collapsed as a value |
| `Inspector/InspectorPanel.swift`, `ArchetypeEditor/ArchetypeHelpPanel.swift` | `InspectorSection`/`HelpSection` collapsible headers now report Expanded/Collapsed |
| `Editor/Components/HelpTooltip.swift` | `OptionalDateField`/`NumberField`'s enable-toggle now labeled with the field name (was an unlabeled checkbox) |
| `Editor/Tabs/AdvancedTab.swift`, `Editor/Tabs/SEOTab.swift` | "Override default outputs" / "Set sitemap priority" enable-toggles labeled |
| `TranslationEditor/NewTranslationFileView.swift`, `Editor/FrontmatterEditorView.swift` | Selection-by-background-tint-only chips (language quick-pick, frontmatter tab bar) now also carry `.isSelected` trait |

### Fixed — missing `.isHeader` traits on section headers

Applied to `Text(...).font(.headline)`-style titles across ~30 views:
`RenameSheet`, `NewContentView`, `NewDataFileView`, `NewTranslationFileView`,
`NewArchetypeView`, `ServerConfigPopover` (+ its two subsection headers),
`ServerLogView` (+ empty-state header), `SidebarView` ("Open a Hugo Site",
"Recent Sites", site name), `ContentView` ("Select a File"),
`ArchetypeEditorView`, `ArchetypeHelpPanel`, `TextEditorPanel`,
`TemplateEditorView`, `TemplateBrowserView` (toolbar title + "Summary"/"By
Type"/"Popular Partials"/"No Templates Found"), `AssetBrowserView`,
`AssetDetailPanel`, `TranslationEditorView`, `ConfigEditorView`,
`GlobalSearchView`, `MetadataSection` ("Custom Fields"),
`FormSectionView` (shared component — one fix, many call sites),
`ShortcodeFormView` (title + Content + Preview headers), `MenusTab` ("Add to
Menu"), `MenuEntryEditor`, `DataFileEditorView`, `FolderContentsView` (name +
"Empty Folder"), `UnsupportedFilePanel`, `EmptyStateView`'s `ErrorStateView`,
`BuildIssuesPopover`, `FocusModeView`'s top-bar filename, `ShortcodeCardView`.

DisclosureGroup-driven headers (`ShortcodeFormView`'s "Optional Parameters
(N)", `DataFileEditorView`'s "Item N") were deliberately left alone —
`DisclosureGroup` already exposes its own expand/collapse semantics natively;
adding `.isHeader` there would be redundant, not incremental.

### Fixed — decorative images not hidden

~35 call sites: file-type/section icons that sit next to a text label
conveying the same information (config-file gear, folder icons, template-type
icons, breadcrumb separator chevron, search magnifying glasses, arrow
separators in permalink/taxonomy rows, hover-only drag-hint glyphs in the
asset browser, status triangle/checkmark icons paired with text, empty-state
icons above a title). Left alone: any icon inside a `Label(text, systemImage:)`
pairing, since `Label` already merges icon + text into one accessible unit —
those were correct as-is and not touched.

### Fixed — unannounced transient status text

| Surface | What |
|---|---|
| `AssetBrowser/AssetDetailPanel.swift` | "Copied!" feedback after Copy Path/Markdown/Figure now posts `AccessibilityNotification.Announcement("Copied to clipboard")` on top of the existing (now labeled) `Text` |
| `MainWindow/RenameSheet.swift` | Validation error now announced on change (see Part 1) |
| `MainWindow/FrontmatterBottomPanel.swift` | Raw-editor parse error now folded into the `TextEditor`'s `accessibilityLabel` so focusing the editor states the error |
| `NewContentView`, `NewDataFileView`, `NewTranslationFileView`, `NewArchetypeView`, `ArchetypeEditorView` | Inline error `Text` now carries an explicit `"Error: <message>"` label (visible-only before) |

**Deliberately not fixed — transient build-error pills** (`TabBarView`'s
build-issues pill, `ServerControlView`'s error badge): these already have
clear static labels (fixed above), but *appearing* doesn't post a live
announcement. The surrounding code comments explicitly record that the old
auto-popover behavior was removed because it interrupted users on every new
error batch — auto-announcing via VoiceOver on every appearance would
reintroduce the same interruption pattern for VoiceOver users specifically.
Whether/how to surface this (a debounced announcement, an opt-in setting) is
a UX call, not a mechanical fix — recommending it be decided explicitly
rather than defaulted.

### Recommended, not fixed (requires restructuring or judgment)

| Surface | Issue | Why not fixed |
|---|---|---|
| `DataEditor/DataFileEditorView.swift` — `DataValueEditor` | The boolean-value `Toggle("", isOn:)` has no accessibility label; the component is generic (reused for both keyed object fields and unkeyed array items) with no `key` parameter to derive a label from | Adding a label requires a new initializer parameter — a structural change, not modifier-only |
| `TemplateEditor/TemplateBrowserView.swift` — partial-reference count (`×N` next to a partial name) | Low-confidence: might already read acceptably as part of the row's existing text flow | Left for a human VoiceOver pass to confirm before touching |
| `TranslationEditor/TranslationEditorView.swift` — raw/form column header row ("Key" / "Translation") | Same low-confidence flag from the sweep | Same — human pass to confirm |
| Drag/drop "Move to Folder…" (Part 1) | No accessible equivalent for moving a file | Real feature addition, out of scope |
| Build-error pill/badge live announcement | No VoiceOver announcement when a new error batch appears | UX judgment call (interruption risk), not mechanical |

### Verified already correct — no action taken

- `Components/FileStatusBadgeView.swift`, `Editor/EditorStatusBar.swift` (deliberately one of the three approved per-keystroke leaf views per CLAUDE.md's invalidation contract — plain `Text`, nothing to fix)
- `Shared/KeyboardShortcutsView.swift` (native `Table`, headers/rows accessible by default)
- `Preferences/PreferencesView.swift`, `ConfigEditor/Tabs/ConfigEssentialsTab.swift`, `ConfigEditor/Tabs/ConfigAdvancedTab.swift` (`LabeledContent` and `Section("string")` already provide correct label/value and header semantics natively)
- `Preview/PreviewWebView.swift`, `Editor/EditorTextView.swift` (`NSViewRepresentable` wrappers around WKWebView/NSTextView — accessibility is handled by AppKit/WebKit, not SwiftUI, at this layer)
- `Views/Animations/AnimationModifiers.swift`, `Editor/Components/SyntaxHighlightedTextView.swift`, `MainWindow/WindowAccessor.swift` (no SwiftUI accessibility surface — pure modifiers/invisible bridge view)
- `Editor/EditorPanelView.swift`'s `EditorToolbar`/`ToolbarButton`/`HeadingMenu`/`LivePreviewToggle` (already fully labeled by the victor-0qe pass — `ToolbarButton` sets `.accessibilityLabel`, `LivePreviewToggle` uses `.labelStyle(.titleAndIcon)` so text is visible)
- `Views/MainWindow/FileListView.swift`'s `SelectionContextMenu` and batch-trash alert (Part 1, see above)
- `VictorApp.swift` Edit-menu additions (Part 1, see above)

## Per-keystroke invalidation contract compliance

No fix in this pass reads `EditorViewModel.localContent`/`hasUnsavedChanges`/
`cursorLine`/`cursorColumn` or `SiteViewModel.editedContentVersion` from a
wide-scope view. The only per-keystroke-adjacent surface touched is
`MainWindow/EditorPanelView.swift`'s `SaveButton`, which is already the
designated leaf view for that state (CLAUDE.md names it explicitly) — the
one addition there (`.accessibilityLabel("Saving")` on its `ProgressView`)
reads no new state, it's a static label on an existing per-render branch.
`EditorStatusBar`/`EditorStatusBarView` (the other named leaf) needed no
change — a single `Text` is already fully accessible with no help.

## Requires a human VoiceOver pass

Static analysis can flag missing labels/traits but can't verify runtime
behavior. Before closing this out, someone should walk through with VoiceOver
on and check:

1. **Sidebar tree cursor navigation** — arrowing through `FileListView`'s
   `List`/`DisclosureGroup` tree with VO, confirming the new combined row
   element (name + type + badges + status) reads in a sensible order and that
   expand/collapse of folders is discoverable and operable via VO.
2. **RenameSheet focus capture and announcement** — confirm the sheet grabs
   VO focus on presentation (`isNameFieldFocused = true` on `.onAppear`),
   that the new `AccessibilityNotification.Announcement` for validation
   errors actually interrupts/is heard while typing, and that it doesn't fire
   so often it becomes noise (every keystroke that keeps the name invalid).
3. **Batch-trash alert wording** — trigger with a mixed folder+file
   multi-selection and confirm VO reads the pruned count (not the raw
   selection count) correctly aloud.
4. **Multi-select rotor behavior** — confirm Cmd-clicking/Shift-clicking to
   build a multi-selection is achievable via VO's interaction model (VO
   generally drives macOS UI via the same click/keyboard primitives, but
   List multi-select selection-state announcements should be checked).
5. **Right-click / context-menu reachability via VO** — `SelectionContextMenu`
   is presented via `.contextMenu(forSelectionType:)`; confirm VO's
   "show menu" gesture (VO+Shift+M) reaches it for both single and multi
   selections, and that `.onDeleteCommand`/`.onCopyCommand` (Delete/Cmd+C)
   are reachable some way for a VO-only user who may not have a means to
   trigger arbitrary key equivalents easily.
6. **Collapsible-header value announcements** — confirm the new
   Expanded/Collapsed `.accessibilityValue()` additions (
   `FrontmatterBottomPanel`, `InspectorSection`, `ArchetypeHelpPanel`'s
   `HelpSection`, `TranslationEditorView`'s plural-forms toggle) actually get
   spoken on activation, not just present in the accessibility tree.
7. **Copy-to-clipboard announcement timing** — `AssetDetailPanel`'s new
   `AccessibilityNotification.Announcement("Copied to clipboard")`: confirm
   it doesn't race with or get swallowed by VO's own click-feedback speech.
8. **RenameSheet `Button(role: .cancel)`** — confirm VO announces it
   distinctly (e.g. as "Cancel button" vs a generic button) and that no
   visual regression came with the role (macOS sometimes applies subtle
   styling to `.cancel`/`.destructive` roles).
9. **Build-issue pill/badge severity wording** — confirm "N build error(s)"
   vs "N build warning(s)" reads naturally and isn't announced repeatedly
   as the count changes underneath a stationary VO cursor.
