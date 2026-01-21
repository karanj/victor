import Foundation

// MARK: - EditorSaveHelper

/// Helper for common save operations across all editor views
/// Encapsulates the save pattern: set isSaving, write content, mark saved, show indicator
struct EditorSaveHelper {

    /// Perform a save operation with consistent state management and error handling
    /// - Parameters:
    ///   - url: The file URL to save to
    ///   - content: Closure that returns the content to save (may throw)
    ///   - isSaving: Getter for current isSaving state
    ///   - setIsSaving: Setter for isSaving state
    ///   - showSavedIndicator: Getter for current showSavedIndicator state
    ///   - setShowSavedIndicator: Setter for showSavedIndicator state
    ///   - errorMessage: Getter for current errorMessage state
    ///   - setErrorMessage: Setter for errorMessage state
    ///   - markAsSaved: Called after successful save to mark the model as saved
    ///   - afterSave: Optional callback after successful save (e.g., to notify parent)
    ///   - savedIndicatorDuration: How long to show the saved indicator (default 2 seconds)
    @MainActor
    func performSave(
        to url: URL,
        content: () throws -> String,
        isSaving: () -> Bool,
        setIsSaving: (Bool) -> Void,
        showSavedIndicator: () -> Bool,
        setShowSavedIndicator: (Bool) -> Void,
        errorMessage: () -> String?,
        setErrorMessage: (String?) -> Void,
        markAsSaved: () -> Void,
        afterSave: () async -> Void,
        savedIndicatorDuration: Double = 2.0
    ) async {
        setIsSaving(true)
        setErrorMessage(nil)

        do {
            let contentToWrite = try content()
            try contentToWrite.write(to: url, atomically: true, encoding: .utf8)
            markAsSaved()
            await afterSave()
            setShowSavedIndicator(true)
            try? await Task.sleep(for: .seconds(savedIndicatorDuration))
            setShowSavedIndicator(false)
        } catch {
            setErrorMessage("Save failed: \(error.localizedDescription)")
        }

        setIsSaving(false)
    }

    /// Perform a save operation with a custom async save closure
    /// Use this when the save logic is more complex than just writing content to a file
    /// - Parameters:
    ///   - saveOperation: Async closure that performs the actual save (may throw)
    ///   - isSaving: Getter for current isSaving state
    ///   - setIsSaving: Setter for isSaving state
    ///   - showSavedIndicator: Getter for current showSavedIndicator state
    ///   - setShowSavedIndicator: Setter for showSavedIndicator state
    ///   - errorMessage: Getter for current errorMessage state
    ///   - setErrorMessage: Setter for errorMessage state
    ///   - afterSave: Optional callback after successful save (e.g., to notify parent)
    ///   - savedIndicatorDuration: How long to show the saved indicator (default 2 seconds)
    @MainActor
    func performSave(
        operation saveOperation: () async throws -> Void,
        isSaving: () -> Bool,
        setIsSaving: (Bool) -> Void,
        showSavedIndicator: () -> Bool,
        setShowSavedIndicator: (Bool) -> Void,
        errorMessage: () -> String?,
        setErrorMessage: (String?) -> Void,
        afterSave: () async -> Void,
        savedIndicatorDuration: Double = 2.0
    ) async {
        setIsSaving(true)
        setErrorMessage(nil)

        do {
            try await saveOperation()
            await afterSave()
            setShowSavedIndicator(true)
            try? await Task.sleep(for: .seconds(savedIndicatorDuration))
            setShowSavedIndicator(false)
        } catch {
            setErrorMessage("Save failed: \(error.localizedDescription)")
        }

        setIsSaving(false)
    }
}

// MARK: - EditorReloadHelper

/// Helper for common reload operations across all editor views
/// Encapsulates the reload pattern: read from disk, update model, mark saved
struct EditorReloadHelper {

    /// Perform a reload operation with consistent error handling
    /// - Parameters:
    ///   - url: The file URL to reload from
    ///   - updateContent: Closure to update the model with the loaded content
    ///   - errorMessage: Getter for current errorMessage state
    ///   - setErrorMessage: Setter for errorMessage state
    ///   - markAsSaved: Called after successful reload to mark the model as saved
    @MainActor
    func performReload(
        from url: URL,
        updateContent: (String) throws -> Void,
        errorMessage: () -> String?,
        setErrorMessage: (String?) -> Void,
        markAsSaved: () -> Void
    ) async {
        setErrorMessage(nil)

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            try updateContent(content)
            markAsSaved()
        } catch {
            setErrorMessage("Reload failed: \(error.localizedDescription)")
        }
    }
}
