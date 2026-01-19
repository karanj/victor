import SwiftUI

/// Common state management for all editor views
protocol EditorState {
    var isSaving: Bool { get set }
    var showSavedIndicator: Bool { get set }
    var errorMessage: String? { get set }
}

extension EditorState {
    /// Show saved indicator briefly (2 seconds)
    @MainActor
    mutating func showSavedIndicatorBriefly() async {
        showSavedIndicator = true
        try? await Task.sleep(for: .seconds(2.0))
        showSavedIndicator = false
    }
}
