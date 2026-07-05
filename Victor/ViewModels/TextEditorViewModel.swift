import Foundation
import SwiftUI

/// ViewModel for editing plain text files (YAML, TOML, JSON, HTML, CSS, JS, etc.)
@MainActor
@Observable
class TextEditorViewModel {
    // MARK: - Properties

    /// The text file being edited (nil if none selected)
    var textFile: TextFile?

    /// FileNode.id for the current `textFile`. Distinct from `textFile.id` -
    /// `modifiedFileIDs` and friends on SiteViewModel are keyed by FileNode.id
    /// everywhere else, so this is what we report dirty state against.
    private(set) var nodeID: UUID?

    /// Reports dirty/saved state to SiteViewModel (edited-dot, Close Site
    /// confirmation, applicationShouldTerminate, Save All) - mirrors the
    /// weak-reference + nodeID pattern EditorViewModel uses for markdown files.
    /// Weak because this ViewModel is a single reused `@State` instance in
    /// FileViewerRouter (unlike EditorViewModel, which is recreated per file).
    weak var siteViewModel: SiteViewModel?

    /// Editable content bound to the editor
    var editableContent: String = ""

    /// Whether file has unsaved changes
    var hasUnsavedChanges: Bool {
        guard let file = textFile else { return false }
        return editableContent != file.originalContent
    }

    /// Whether currently saving
    var isSaving: Bool = false

    /// Show saved indicator briefly after save
    var showSavedIndicator: Bool = false

    /// Error message to display
    var errorMessage: String?

    // MARK: - Private Properties

    private var autoSaveTask: Task<Void, Never>?

    /// Defaults to the process-wide singleton; tests inject their own instance for
    /// isolation (victor-zw4).
    private let fileSystemService: FileSystemService

    // MARK: - Initialization

    init(fileSystemService: FileSystemService = .shared) {
        self.fileSystemService = fileSystemService
    }

    /// Whether auto-save is enabled
    private var isAutoSaveEnabled: Bool {
        AppSettings.shared.isAutoSaveEnabled
    }

    /// Auto-save delay in seconds
    private var autoSaveDelay: Double {
        AppSettings.shared.autoSaveDelay
    }
    private var savedIndicatorTask: Task<Void, Never>?

    // MARK: - Public Methods

    /// Load a text file for editing
    func loadFile(_ file: TextFile, nodeID: UUID) {
        // Cancel any pending auto-save
        autoSaveTask?.cancel()

        self.textFile = file
        self.nodeID = nodeID
        self.editableContent = file.content
        self.errorMessage = nil
        self.showSavedIndicator = false
    }

    /// Called when content changes in the editor
    func contentDidChange() {
        guard let file = textFile else { return }
        file.content = editableContent
        reportDirtyState()

        // Schedule auto-save if enabled
        if isAutoSaveEnabled && hasUnsavedChanges {
            scheduleAutoSave()
        }
    }

    /// Save the file manually
    func save() async {
        guard let file = textFile else { return }
        guard hasUnsavedChanges else { return }

        isSaving = true
        errorMessage = nil

        do {
            try await fileSystemService.writeFile(to: file.url, content: editableContent)
            file.content = editableContent
            file.markAsSaved()
            file.lastModified = Date()

            if let nodeID {
                siteViewModel?.markFileSaved(nodeID)
            }

            // Show saved indicator
            showSavedIndicatorBriefly()
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }

        isSaving = false
    }

    /// Reload content from disk (discard changes)
    func reloadFromDisk() async {
        guard let file = textFile else { return }

        do {
            // Extract the Sendable URL before crossing into Task.detached - the
            // closure must not capture `file` itself (a non-Sendable TextFile
            // class), same boundary-snapshot fix as WP3.5 Cluster 1's
            // ContentFile handling (this file wasn't in Cluster 1's audited
            // list, but has the identical pattern).
            let url = file.url
            let content = try await Task.detached {
                try String(contentsOf: url, encoding: .utf8)
            }.value

            file.content = content
            file.originalContent = content
            self.editableContent = content
            self.errorMessage = nil
            reportDirtyState()
        } catch {
            errorMessage = "Failed to reload: \(error.localizedDescription)"
        }
    }

    // MARK: - Private Methods

    /// Push current dirty/clean state to SiteViewModel's modifiedFileIDs, so
    /// the edited-dot, Close Site confirmation, applicationShouldTerminate,
    /// and Save All all see plain-text edits (P0 fix - previously invisible).
    private func reportDirtyState() {
        guard let nodeID else { return }
        if hasUnsavedChanges {
            siteViewModel?.markFileModified(nodeID)
        } else {
            siteViewModel?.clearFileModified(nodeID)
        }
    }

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()

        autoSaveTask = Task { [weak self] in
            guard let self = self else { return }

            // Wait for the debounce interval
            try? await Task.sleep(for: .seconds(self.autoSaveDelay))

            // Check if task was cancelled
            guard !Task.isCancelled else { return }

            // Perform save
            await self.save()
        }
    }

    private func showSavedIndicatorBriefly() {
        savedIndicatorTask?.cancel()
        showSavedIndicator = true

        savedIndicatorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.0))
            guard !Task.isCancelled else { return }
            self?.showSavedIndicator = false
        }
    }
}
