import Foundation
import SwiftUI

/// ViewModel for the editor panel, handling file editing, saving, and auto-save logic
@MainActor
@Observable
class EditorViewModel {
    // MARK: - Dependencies

    private let fileNode: FileNode
    private let contentFile: ContentFile
    private let siteViewModel: SiteViewModel

    /// Defaults to the process-wide singleton; tests inject their own instance for
    /// isolation (victor-zw4) - see AutoSaveServiceTests.
    private let autoSaveService: AutoSaveService

    // MARK: - State

    /// Local content storage - doesn't depend on selectedNode
    /// This eliminates the race condition class where stale EditorViewModels could read/write wrong file's content
    private var localContent: String

    /// Editable content - reads from local storage and syncs back to SiteViewModel.
    ///
    /// The setter OWNS change handling (dirty flag + auto-save scheduling):
    /// a keystroke is one binding write from NSTextView's textDidChange, handled
    /// entirely here. Previously the view delivered this via
    /// `.onChange(of: viewModel.editableContent)`, which made EditorPanelView's
    /// body read per-keystroke state and re-evaluate on every character typed
    /// (keystroke-lag fix, part 2 - see EditorViewModelTests).
    var editableContent: String {
        get { localContent }
        set {
            localContent = newValue
            // Sync back to per-file storage in SiteViewModel
            siteViewModel.setEditedContent(newValue, for: fileNode.id)
            handleContentChange()
        }
    }

    var isSaving = false
    var showSavedIndicator = false
    var showConflictAlert = false

    // Cursor position tracking
    var cursorLine: Int = 1
    var cursorColumn: Int = 1

    // Track last saved frontmatter version for lightweight change detection
    // Using version counter is O(1) compared to O(n) snapshot comparison
    private var lastSavedFrontmatterVersion: Int = 0


    // Track pending auto-save task for cleanup on file switch
    private var autoSaveTask: Task<Void, Never>?

    // MARK: - Computed Properties

    var hasUnsavedChanges: Bool {
        // Check if markdown content has changed
        // Using localContent directly (not editableContent) ensures this works correctly
        // even after file switch - no dependency on selectedNode
        let contentChanged = localContent != contentFile.markdownContent

        // Check if frontmatter has changed using lightweight version counter
        // This is O(1) compared to the previous O(n) snapshot comparison
        let frontmatterChanged: Bool = {
            guard let currentFrontmatter = contentFile.frontmatter else {
                return false
            }
            return currentFrontmatter.version != lastSavedFrontmatterVersion
        }()

        return contentChanged || frontmatterChanged
    }

    var navigationTitle: String {
        contentFile.frontmatter?.title ?? "No title"
    }

    // MARK: - Initialization

    init(
        fileNode: FileNode,
        contentFile: ContentFile,
        siteViewModel: SiteViewModel,
        autoSaveService: AutoSaveService = .shared
    ) {
        self.fileNode = fileNode
        self.contentFile = contentFile
        self.siteViewModel = siteViewModel
        self.autoSaveService = autoSaveService

        // Initialize local content from per-file storage if it exists (preserves unsaved edits),
        // otherwise fall back to the saved content from the file
        self.localContent = siteViewModel.getEditedContent(for: fileNode.id)
                         ?? contentFile.markdownContent

        // Record initial frontmatter version
        self.lastSavedFrontmatterVersion = contentFile.frontmatter?.version ?? 0
    }

    // MARK: - Public Methods

    /// Update editable content when the underlying file changes
    func updateContent(from newMarkdown: String) {
        localContent = newMarkdown
        // Sync to SiteViewModel per-file storage
        siteViewModel.setEditedContent(newMarkdown, for: fileNode.id)
        // Also update frontmatter version when content is externally updated
        lastSavedFrontmatterVersion = contentFile.frontmatter?.version ?? 0
        // Re-evaluate dirty state (e.g. clears the modified flag after an external
        // reload). The view's onChange(of: editableContent) used to provide this
        // as a side effect; the model owns it now.
        handleContentChange()
    }

    /// Handle content changes for file status tracking and auto-save
    /// Preview sync happens through setEditedContent which updates SiteViewModel's per-file storage
    func handleContentChange() {
        // CRITICAL: Guard against spurious onChange triggers after file switch
        // If this EditorViewModel's file is no longer selected, ignore the change
        // This prevents false "unsaved changes" indicators when switching files
        guard fileNode.id == siteViewModel.selectedNode?.id else {
            return
        }

        // Update file status in sidebar
        if hasUnsavedChanges {
            siteViewModel.markFileModified(fileNode.id)
        } else {
            siteViewModel.clearFileModified(fileNode.id)
        }

        // Schedule auto-save if enabled and there are unsaved changes
        if hasUnsavedChanges && AppSettings.shared.isAutoSaveEnabled {
            scheduleAutoSave()
        }
    }

    /// Update cursor position from editor callback
    func updateCursorPosition(line: Int, column: Int) {
        cursorLine = line
        cursorColumn = column
    }

    /// Manually save the file
    func save() async -> Bool {
        isSaving = true
        showSavedIndicator = false

        // Capture content value before async operations
        let markdownToSave = editableContent
        let fullContent = buildFullContent(markdownContent: markdownToSave)
        let success = await siteViewModel.saveFile(node: fileNode, content: fullContent)

        isSaving = false

        if success {
            // Update the content file's markdown content with captured value
            contentFile.markdownContent = markdownToSave

            // Record frontmatter version after successful save
            lastSavedFrontmatterVersion = contentFile.frontmatter?.version ?? 0

            // Update file status in sidebar
            siteViewModel.markFileSaved(fileNode.id)

            // Show saved indicator briefly
            showSavedIndicator = true
            try? await Task.sleep(for: .seconds(AppConstants.Timing.savedIndicatorDuration))
            showSavedIndicator = false
        }

        return success
    }

    /// Handle conflict when file is modified externally
    func reloadFromDisk() async {
        await siteViewModel.reloadFile(node: fileNode)
    }

    /// Release reference to pending auto-save task when ViewModel is replaced
    /// The task will continue to completion in the background - it has already
    /// captured the content and file URL, so the save will complete correctly.
    /// Callbacks use [weak self] so they'll safely no-op after ViewModel is gone.
    func cleanup() {
        // Don't cancel - let the pending save complete in background
        // Just release our reference so we don't hold onto the task
        autoSaveTask = nil
    }

    // MARK: - Private Methods

    /// Build full file content by combining frontmatter and markdown
    /// IMPORTANT: Reads directly from captured values, not computed properties
    /// to avoid race conditions when files are switched mid-save
    private func buildFullContent(markdownContent: String) -> String {
        if let frontmatter = contentFile.frontmatter {
            let serialized = FrontmatterParser.shared.serializeFrontmatter(frontmatter)
            return serialized + "\n" + markdownContent
        } else {
            return markdownContent
        }
    }

    /// Schedule auto-save with conflict detection.
    ///
    /// Redesigned (keystroke-lag perf ticket): previously this ran `buildFullContent`
    /// (frontmatter YAML serialization + full-document concat) on EVERY keystroke,
    /// before handing a fixed string off to AutoSaveService's actor-side debounce.
    /// Now the debounce itself lives here, as a plain MainActor `Task.sleep` (mirroring
    /// TextEditorViewModel's pattern) - a keystroke only cancels-and-respawns this
    /// Task, with no content capture and no serialization. The full document is built
    /// exactly once, at fire time, from LIVE state (`siteViewModel.getEditedContent`/
    /// `contentFile.frontmatter`) - this is a deliberate design decision (not just a
    /// perf win): it also fixes a real bug where frontmatter edited during the
    /// debounce window was silently lost, since the old code's captured string was
    /// already finalized before that edit happened (see
    /// testFrontmatterEditedDuringDebounceWindowReachesDisk).
    ///
    /// CRITICAL: `nodeID`/`nodeURL`/`capturedContentFile`/`capturedSiteViewModel`/
    /// `service` are captured as local lets and used directly in the Task body below -
    /// NOT via `self.xxx` - so this Task does not capture `self` at all. That's what
    /// lets a file switch mid-debounce still complete the save: `cleanup()` releases
    /// this EditorViewModel's own reference to `autoSaveTask`, and if nothing else
    /// retains this ViewModel, it can be deallocated while the Task is still sleeping
    /// - the save must not depend on `self` surviving that. Only the callbacks
    /// (onConflict/onSuccess/onError), which update UI-indicator/model state that's
    /// meaningless once this ViewModel might be stale, use `[weak self]` - same
    /// no-op-after-dealloc contract `cleanup()` already documents.
    ///
    /// Registers itself with `AutoSaveService`'s node-ID-keyed debounce registry
    /// (victor-rnm TOCTOU hardening, post-launch review): `SiteViewModel.renameFile`/
    /// `moveNode` call `cancelDebounce(nodeID:)` before touching disk, which cancels
    /// AND awaits this Task, so they can't proceed while a write for this node is
    /// still in flight. `newTask` is a self-referencing `var` (not `let`) so the Task
    /// body can register its OWN handle as its first action - safe because
    /// `newTask = Task { ... }` is a plain synchronous assignment with no suspension
    /// point, so the closure cannot start running (and therefore cannot read
    /// `newTask`) until that MainActor-serialized statement has already completed.
    /// The registry entry is removed unconditionally as the Task's LAST action
    /// (whether cancelled early or after a completed write) so it never grows
    /// unbounded - see `deregisterDebounce`'s doc comment.
    private func scheduleAutoSave() {
        let nodeID = fileNode.id
        let capturedContentFile = contentFile
        let capturedSiteViewModel = siteViewModel
        let service = autoSaveService
        let debounceToken = UUID()

        // Cancel any pending debounce before scheduling a new one - this alone (no
        // content capture, no serialization) is now the entire per-keystroke cost.
        autoSaveTask?.cancel()

        var newTask: Task<Void, Never>!
        newTask = Task {
            await service.registerDebounce(nodeID: nodeID, token: debounceToken, task: newTask)

            try? await Task.sleep(for: .seconds(AppSettings.currentAutoSaveDelay()))
            if !Task.isCancelled {
                // Read the URL fresh, AFTER the sleep - NOT a value snapshotted at
                // schedule time. SiteViewModel.renameFile mutates `contentFile.url`
                // in place, so a rename that lands during this sleep is honored: the
                // save targets the file's CURRENT path instead of recreating it at a
                // path that no longer exists (victor-rnm hardening - flagged there as
                // the highest-risk bug in that package).
                let nodeURL = capturedContentFile.url

                // Build the full document ONCE, now, from LIVE state - not a snapshot
                // taken back when this debounce was scheduled.
                let markdownToSave = capturedSiteViewModel.getEditedContent(for: nodeID)
                    ?? capturedContentFile.markdownContent
                let fullContent: String
                if let frontmatter = capturedContentFile.frontmatter {
                    fullContent = FrontmatterParser.shared.serializeFrontmatter(frontmatter) + "\n" + markdownToSave
                } else {
                    fullContent = markdownToSave
                }

                await service.scheduleImmediateSave(
                    fileURL: nodeURL,
                    content: fullContent,
                    lastModified: capturedContentFile.lastModified,
                    onConflict: { @MainActor [weak self] in
                        guard let self = self else { return .cancel }
                        // Only show conflict alert if this is still the selected file
                        guard nodeID == self.siteViewModel.selectedNode?.id else {
                            return .cancel  // Silently cancel if file switched
                        }
                        // Cancel auto-save and show alert
                        self.showConflictAlert = true
                        return .cancel
                    },
                    onSuccess: { @MainActor [weak self] newModificationDate in
                        guard let self = self else { return }

                        // CRITICAL: Only update state if this is still the current file
                        // If user switched files, this EditorViewModel is stale and shouldn't modify anything
                        guard nodeID == self.siteViewModel.selectedNode?.id else {
                            // File was switched - don't update UI or modify state
                            // The save to disk was successful, but UI updates are for the old file
                            Logger.shared.info("[AutoSave] Successfully saved \(nodeURL.lastPathComponent) after file switch")
                            return
                        }

                        Logger.shared.info("[AutoSave] Successfully saved \(nodeURL.lastPathComponent)")

                        // Update modification date
                        self.contentFile.lastModified = newModificationDate
                        // Use the same markdown content that was actually written
                        self.contentFile.markdownContent = markdownToSave

                        // Record frontmatter version after successful auto-save
                        self.lastSavedFrontmatterVersion = self.contentFile.frontmatter?.version ?? 0

                        // Update file status in sidebar
                        self.siteViewModel.markFileSaved(nodeID)

                        // Show saved indicator briefly
                        self.showSavedIndicator = true
                        Task { [weak self] in
                            try? await Task.sleep(for: .seconds(AppConstants.Timing.autoSaveIndicatorDuration))
                            self?.showSavedIndicator = false
                        }
                    },
                    onError: { @MainActor [weak self] error in
                        guard let self = self else { return }
                        // Only show error if this is still the selected file
                        guard nodeID == self.siteViewModel.selectedNode?.id else {
                            // Log the error even though we're not showing it to the user
                            Logger.shared.warning("[AutoSave] Error saving \(nodeURL.lastPathComponent) after file switch: \(error.localizedDescription)")
                            return
                        }
                        // Show error in site view model (unless it's a user cancellation)
                        if !(error is AutoSaveError) {
                            self.siteViewModel.errorMessage = error.localizedDescription
                        }
                    }
                )
            }

            // Always deregister - single exit point whether we were cancelled
            // early or completed a write, so AutoSaveService's registry never
            // grows unbounded and `cancelDebounce` never blocks on a Task that
            // already finished (see AutoSaveService.cancelDebounce's doc
            // comment for why this must be the Task's last action).
            await service.deregisterDebounce(nodeID: nodeID, token: debounceToken)
        }
        autoSaveTask = newTask
    }
}
