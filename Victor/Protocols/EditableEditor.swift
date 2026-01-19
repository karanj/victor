import SwiftUI

/// Protocol for views that edit EditableFile models
/// Provides standard interface for save/reload functionality
///
/// ## Usage
/// Conforming views should implement save/reload using this pattern:
/// ```swift
/// func save() async {
///     isSaving = true
///     errorMessage = nil
///
///     do {
///         try await performSave()
///         model.markAsSaved()
///         await onSaveComplete()
///         await EditorHelpers.showSavedIndicatorBriefly(&showSavedIndicator)
///     } catch {
///         errorMessage = "Save failed: \(error.localizedDescription)"
///     }
///
///     isSaving = false
/// }
/// ```
protocol EditableEditor: View {
    associatedtype Model: EditableFile

    var model: Model { get }
    var isSaving: Bool { get set }
    var showSavedIndicator: Bool { get set }
    var errorMessage: String? { get set }

    /// Save the model to disk (implement file-specific logic)
    func performSave() async throws

    /// Reload the model from disk (implement file-specific logic)
    func performReload() async throws

    /// Callback after successful save (usually notify parent)
    func onSaveComplete() async

    /// Standard save flow (implement using the pattern in protocol docs)
    func save() async

    /// Standard reload flow (implement using the pattern in protocol docs)
    func reload() async
}

/// Helper functions for editor implementations
enum EditorHelpers {
    /// Show saved indicator briefly (2 seconds)
    @MainActor
    static func showSavedIndicatorBriefly(_ showSavedIndicator: inout Bool) async {
        showSavedIndicator = true
        try? await Task.sleep(for: .seconds(2.0))
        showSavedIndicator = false
    }
}
