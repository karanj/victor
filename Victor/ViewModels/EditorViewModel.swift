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

    // MARK: - State

    /// Editable content - computed property that reads/writes directly to SiteViewModel
    /// This eliminates state duplication between EditorViewModel and SiteViewModel
    var editableContent: String {
        get { siteViewModel.currentEditingContent }
        set { siteViewModel.currentEditingContent = newValue }
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

    // Cached word/character counts to avoid recomputation on every render
    // These are invalidated when content changes
    private var cachedWordCount: Int = 0
    private var cachedCharacterCount: Int = 0
    private var lastCountedContentHash: Int = 0

    // Track pending auto-save task for cleanup on file switch
    private var autoSaveTask: Task<Void, Never>?

    // MARK: - Computed Properties

    var hasUnsavedChanges: Bool {
        // Check if markdown content has changed
        let contentChanged = editableContent != contentFile.markdownContent

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

    /// Word count for the current document (cached for performance)
    var wordCount: Int {
        updateCountCacheIfNeeded()
        return cachedWordCount
    }

    /// Character count for the current document (cached for performance)
    var characterCount: Int {
        updateCountCacheIfNeeded()
        return cachedCharacterCount
    }

    /// Update the cached word/character counts if the content has changed
    /// Uses hash comparison to avoid expensive recomputation on every access
    private func updateCountCacheIfNeeded() {
        let currentHash = editableContent.hashValue
        guard currentHash != lastCountedContentHash else { return }

        // Content changed, recompute counts
        lastCountedContentHash = currentHash
        cachedCharacterCount = editableContent.count

        let words = editableContent
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        cachedWordCount = words.count
    }

    // MARK: - Initialization

    init(fileNode: FileNode, contentFile: ContentFile, siteViewModel: SiteViewModel) {
        self.fileNode = fileNode
        self.contentFile = contentFile
        self.siteViewModel = siteViewModel
        // Note: editableContent is now a computed property that reads/writes
        // siteViewModel.currentEditingContent directly, which is already set
        // by SiteViewModel.selectNode() when the file is selected.
        // Record initial frontmatter version
        self.lastSavedFrontmatterVersion = contentFile.frontmatter?.version ?? 0
    }

    // MARK: - Public Methods

    /// Update editable content when the underlying file changes
    func updateContent(from newMarkdown: String) {
        editableContent = newMarkdown
        // Also update frontmatter version when content is externally updated
        lastSavedFrontmatterVersion = contentFile.frontmatter?.version ?? 0
    }

    /// Handle content changes for file status tracking and auto-save
    /// Note: Preview sync is automatic since editableContent is a computed property
    /// that reads/writes directly to siteViewModel.currentEditingContent
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
        // Read directly from UserDefaults for immediate effect from Preferences changes
        let autoSaveEnabled = UserDefaults.standard.object(forKey: "isAutoSaveEnabled") as? Bool ?? true
        if hasUnsavedChanges && autoSaveEnabled {
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
            await AutoSaveService.shared.scheduleAutoSave(
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
                        return
                    }

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
                        return  // Silently ignore errors for old files
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
