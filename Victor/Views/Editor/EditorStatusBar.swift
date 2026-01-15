import SwiftUI

/// Status bar showing cursor position
/// Note: Word/character counts removed for performance - they're in the inspector panel instead
struct EditorStatusBar: View {
    let cursorLine: Int
    let cursorColumn: Int

    var body: some View {
        HStack(spacing: 0) {
            // Cursor position
            Text("Line \(cursorLine), Col \(cursorColumn)")

            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        Text("Editor content would go here")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))

        EditorStatusBar(
            cursorLine: 42,
            cursorColumn: 15
        )
    }
    .frame(width: 500, height: 300)
}
