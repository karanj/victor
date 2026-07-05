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

    /// Editable content - reads from local storage and syncs back to SiteViewModel
    var editableContent: String {
        get { localContent }
        set {
            localContent = newValue
            // Sync back to per-file storage in SiteViewModel
            siteViewModel.setEditedContent(newValue, for: fileNode.id)
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

    /// Schedule auto-save with conflict detection
    private func scheduleAutoSave() {
        // CRITICAL: Capture all values NOW before any async operations
        // This prevents race conditions if the user switches files before auto-save completes
        let markdownToSave = editableContent  // Read once and capture
        let fullContent = buildFullContent(markdownContent: markdownToSave)
        let nodeID = fileNode.id  // Capture node ID to validate later
        let nodeURL = fileNode.url  // Capture URL (shouldn't change, but be safe)

        // Cancel any pending auto-save task before scheduling a new one
        autoSaveTask?.cancel()

        autoSaveTask = Task {
            await autoSaveService.scheduleAutoSave(
                fileURL: nodeURL,
                content: fullContent,
                lastModified: contentFile.lastModified,
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
                    // Use the captured markdown content, not editableContent
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
    }
}
