import SwiftUI

/// Status bar showing document statistics and cursor position
struct EditorStatusBar: View {
    let wordCount: Int
    let characterCount: Int
    let cursorLine: Int
    let cursorColumn: Int

    var body: some View {
        HStack(spacing: 0) {
            // Word count
            Text("\(wordCount) \(wordCount == 1 ? "word" : "words")")

            separator

            // Character count
            Text("\(formattedCharacterCount) \(characterCount == 1 ? "character" : "characters")")

            separator

            // Cursor position
            Text("Line \(cursorLine), Col \(cursorColumn)")

            Spacer()
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) {
            Divider()
        }
    }

    /// Separator between status items
    private var separator: some View {
        Text(" \u{2022} ")
            .foregroundStyle(.tertiary)
    }

    /// Format character count with thousands separator
    private var formattedCharacterCount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: characterCount)) ?? "\(characterCount)"
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        Text("Editor content would go here")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))

        EditorStatusBar(
            wordCount: 234,
            characterCount: 1456,
            cursorLine: 42,
            cursorColumn: 15
        )
    }
    .frame(width: 500, height: 300)
}
