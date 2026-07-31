import Foundation

/// Signals a save that failed and was already reported to the user elsewhere - typically via
/// `SiteViewModel.errorMessage`, which `ContentView` shows as an alert. `EditorSaveHelper`
/// treats it as any other failure (no saved indicator); the editor discards the message so the
/// user doesn't get told twice.
enum EditorSaveFailure: Error {
    case alreadyReported
}

// MARK: - EditorSaveHelper

/// The save pattern shared by every non-markdown editor view: flag saving, write,
/// mark saved, flash the saved indicator, surface any error.
struct EditorSaveHelper {

    /// Writes `content()` to `url`.
    @MainActor
    func performSave(
        to url: URL,
        content: () throws -> String,
        setIsSaving: (Bool) -> Void,
        setShowSavedIndicator: (Bool) -> Void,
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

    /// Same state handling, but the caller owns the write - for editors whose save is
    /// more than "put this string on disk".
    @MainActor
    func performSave(
        operation saveOperation: () async throws -> Void,
        setIsSaving: (Bool) -> Void,
        setShowSavedIndicator: (Bool) -> Void,
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

/// The reload counterpart: read from disk, hand the content to the model, mark saved.
struct EditorReloadHelper {

    @MainActor
    func performReload(
        from url: URL,
        updateContent: (String) throws -> Void,
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
