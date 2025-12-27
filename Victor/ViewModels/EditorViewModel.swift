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

    var editableContent: String
    var isSaving = false
    var showSavedIndicator = false
    var showConflictAlert = false

    // Cursor position tracking
    var cursorLine: Int = 1
    var cursorColumn: Int = 1

    // Track last saved frontmatter state for change detection
    private var lastSavedFrontmatter: FrontmatterSnapshot?

    // MARK: - Computed Properties

    var hasUnsavedChanges: Bool {
        // Check if markdown content has changed
        let contentChanged = editableContent != contentFile.markdownContent

        // Check if frontmatter has changed
        let frontmatterChanged: Bool = {
            guard let currentFrontmatter = contentFile.frontmatter else {
                // No frontmatter now - changed only if we had one before
                return lastSavedFrontmatter != nil
            }

            guard let lastSaved = lastSavedFrontmatter else {
                // We have frontmatter now but didn't before - it's changed
                return true
            }

            // Compare current state with last saved snapshot
            return currentFrontmatter.snapshot() != lastSaved
        }()

        return contentChanged || frontmatterChanged
    }

    var navigationTitle: String {
        contentFile.frontmatter?.title ?? "No title"
    }

    var navigationSubtitle: String {
        hasUnsavedChanges ? "\(contentFile.fileName) • Edited" : contentFile.fileName
    }

    /// Word count for the current document
    var wordCount: Int {
        let words = editableContent
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return words.count
    }

    /// Character count for the current document
    var characterCount: Int {
        editableContent.count
    }

    // MARK: - Initialization

    init(fileNode: FileNode, contentFile: ContentFile, siteViewModel: SiteViewModel) {
        self.fileNode = fileNode
        self.contentFile = contentFile
        self.siteViewModel = siteViewModel
        self.editableContent = contentFile.markdownContent
        // Snapshot initial frontmatter state
        self.lastSavedFrontmatter = contentFile.frontmatter?.snapshot()
    }

    // MARK: - Public Methods

    /// Update editable content when the underlying file changes
    func updateContent(from newMarkdown: String) {
        editableContent = newMarkdown
        // Also update frontmatter snapshot when content is externally updated
        lastSavedFrontmatter = contentFile.frontmatter?.snapshot()
    }

    /// Handle content changes for live preview and auto-save
    func handleContentChange() {
        // Always sync content for preview (needed for tab-based layout)
        // The preview panel handles its own debouncing
        siteViewModel.currentEditingContent = editableContent

        // Schedule auto-save if enabled and there are unsaved changes
        if hasUnsavedChanges && siteViewModel.isAutoSaveEnabled {
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

        let fullContent = buildFullContent()
        let success = await siteViewModel.saveFile(node: fileNode, content: fullContent)

        isSaving = false

        if success {
            // Update the content file's markdown content
            contentFile.markdownContent = editableContent

            // Snapshot the frontmatter state after successful save
            lastSavedFrontmatter = contentFile.frontmatter?.snapshot()

            // Show saved indicator briefly
            showSavedIndicator = true
            try? await Task.sleep(for: .seconds(2))
            showSavedIndicator = false
        }

        return success
    }

    /// Handle conflict when file is modified externally
    func reloadFromDisk() async {
        await siteViewModel.reloadFile(node: fileNode)
    }

    // MARK: - Private Methods

    /// Build full file content by combining frontmatter and markdown
    private func buildFullContent() -> String {
        if let frontmatter = contentFile.frontmatter {
            let serialized = FrontmatterParser.shared.serializeFrontmatter(frontmatter)
            return serialized + "\n" + editableContent
        } else {
            return editableContent
        }
    }

    /// Schedule auto-save with conflict detection
    private func scheduleAutoSave() {
        let fullContent = buildFullContent()

        Task {
            await AutoSaveService.shared.scheduleAutoSave(
                fileURL: fileNode.url,
                content: fullContent,
                lastModified: contentFile.lastModified,
                onConflict: { @MainActor [weak self] in
                    guard let self = self else { return .cancel }
                    // Cancel auto-save and show alert
                    self.showConflictAlert = true
                    return .cancel
                },
                onSuccess: { @MainActor [weak self] newModificationDate in
                    guard let self = self else { return }
                    // Update modification date
                    self.contentFile.lastModified = newModificationDate
                    self.contentFile.markdownContent = self.editableContent

                    // Snapshot the frontmatter state after successful auto-save
                    self.lastSavedFrontmatter = self.contentFile.frontmatter?.snapshot()

                    // Show saved indicator briefly
                    self.showSavedIndicator = true
                    Task { [weak self] in
                        try? await Task.sleep(for: .seconds(1))
                        self?.showSavedIndicator = false
                    }
                },
                onError: { @MainActor [weak self] error in
                    guard let self = self else { return }
                    // Show error in site view model (unless it's a user cancellation)
                    if !(error is AutoSaveError) {
                        self.siteViewModel.errorMessage = error.localizedDescription
                    }
                }
            )
        }
    }
}
