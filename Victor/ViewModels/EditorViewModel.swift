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

    // MARK: - Computed Properties

    var hasUnsavedChanges: Bool {
        editableContent != contentFile.markdownContent
    }

    var navigationTitle: String {
        contentFile.frontmatter?.title ?? "No title"
    }

    var navigationSubtitle: String {
        hasUnsavedChanges ? "\(contentFile.fileName) • Edited" : contentFile.fileName
    }

    // MARK: - Initialization

    init(fileNode: FileNode, contentFile: ContentFile, siteViewModel: SiteViewModel) {
        self.fileNode = fileNode
        self.contentFile = contentFile
        self.siteViewModel = siteViewModel
        self.editableContent = contentFile.markdownContent
    }

    // MARK: - Public Methods

    /// Update editable content when the underlying file changes
    func updateContent(from newMarkdown: String) {
        editableContent = newMarkdown
    }

    /// Handle content changes for live preview and auto-save
    func handleContentChange() {
        // Update live preview if enabled
        if siteViewModel.isLivePreviewEnabled {
            siteViewModel.currentEditingContent = editableContent
        }

        // Schedule auto-save if enabled and there are unsaved changes
        if hasUnsavedChanges && siteViewModel.isAutoSaveEnabled {
            scheduleAutoSave()
        }
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
                onConflict: { @MainActor in
                    // Cancel auto-save and show alert
                    self.showConflictAlert = true
                    return .cancel
                },
                onSuccess: { @MainActor newModificationDate in
                    // Update modification date
                    self.contentFile.lastModified = newModificationDate
                    self.contentFile.markdownContent = self.editableContent

                    // Show saved indicator briefly
                    self.showSavedIndicator = true
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        self.showSavedIndicator = false
                    }
                },
                onError: { @MainActor error in
                    // Show error in site view model (unless it's a user cancellation)
                    if !(error is AutoSaveError) {
                        self.siteViewModel.errorMessage = error.localizedDescription
                    }
                }
            )
        }
    }
}
