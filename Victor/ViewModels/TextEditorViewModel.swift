import Foundation
import SwiftUI

/// ViewModel for editing plain text files (YAML, TOML, JSON, HTML, CSS, JS, etc.)
@MainActor
@Observable
class TextEditorViewModel {
    // MARK: - Properties

    /// The text file being edited (nil if none selected)
    var textFile: TextFile?

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

    /// Whether auto-save is enabled (reads from UserDefaults)
    private var isAutoSaveEnabled: Bool {
        UserDefaults.standard.object(forKey: "isAutoSaveEnabled") as? Bool ?? true
    }

    /// Auto-save delay in seconds (reads from UserDefaults)
    private var autoSaveDelay: Double {
        UserDefaults.standard.object(forKey: "autoSaveDelay") as? Double ?? 2.0
    }
    private var savedIndicatorTask: Task<Void, Never>?

    // MARK: - Public Methods

    /// Load a text file for editing
    func loadFile(_ file: TextFile) {
        // Cancel any pending auto-save
        autoSaveTask?.cancel()

        self.textFile = file
        self.editableContent = file.content
        self.errorMessage = nil
        self.showSavedIndicator = false
    }

    /// Called when content changes in the editor
    func contentDidChange() {
        guard let file = textFile else { return }
        file.content = editableContent

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
            try await FileSystemService.shared.writeFile(to: file.url, content: editableContent)
            file.content = editableContent
            file.markAsSaved()
            file.lastModified = Date()

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
            let content = try await Task.detached {
                try String(contentsOf: file.url, encoding: .utf8)
            }.value

            file.content = content
            file.originalContent = content
            self.editableContent = content
            self.errorMessage = nil
        } catch {
            errorMessage = "Failed to reload: \(error.localizedDescription)"
        }
    }

    // MARK: - Private Methods

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
