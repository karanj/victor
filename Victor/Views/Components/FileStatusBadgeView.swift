import SwiftUI

/// Reusable file status badge component
/// Displays unsaved changes indicator (orange circle) and saved indicator (green checkmark)
struct FileStatusBadgeView: View {
    let hasUnsavedChanges: Bool
    let showSavedIndicator: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            // Unsaved indicator
            if hasUnsavedChanges {
                Circle()
                    .fill(Color.Status.modified)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Unsaved changes")
                    .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
            }

            // Saved indicator
            if showSavedIndicator {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.Status.saved)
                    .accessibilityLabel("Saved")
                    .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
            }
        }
    }
}

// MARK: - Preview

#Preview("Unsaved") {
    FileStatusBadgeView(hasUnsavedChanges: true, showSavedIndicator: false)
}

#Preview("Saved") {
    FileStatusBadgeView(hasUnsavedChanges: false, showSavedIndicator: true)
}

#Preview("Neither") {
    FileStatusBadgeView(hasUnsavedChanges: false, showSavedIndicator: false)
}
