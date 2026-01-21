import SwiftUI

// MARK: - Text Style View Modifiers

/// Applies primary foreground style
struct PrimaryTextModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.foregroundStyle(.primary)
    }
}

/// Applies secondary foreground style
struct SecondaryTextModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.foregroundStyle(.secondary)
    }
}

/// Applies tertiary foreground style
struct TertiaryTextModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.foregroundStyle(.tertiary)
    }
}

// MARK: - View Extension

extension View {
    /// Applies `.foregroundStyle(.primary)`
    var primaryText: some View {
        modifier(PrimaryTextModifier())
    }

    /// Applies `.foregroundStyle(.secondary)`
    var secondaryText: some View {
        modifier(SecondaryTextModifier())
    }

    /// Applies `.foregroundStyle(.tertiary)`
    var tertiaryText: some View {
        modifier(TertiaryTextModifier())
    }
}

// MARK: - Previews

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        Text("Primary text style")
            .primaryText

        Text("Secondary text style")
            .secondaryText

        Text("Tertiary text style")
            .tertiaryText

        Divider()

        Text("Comparison with standard modifiers:")
            .font(.headline)

        HStack {
            VStack(alignment: .leading) {
                Text("New").font(.caption).bold()
                Text(".primaryText").primaryText
                Text(".secondaryText").secondaryText
                Text(".tertiaryText").tertiaryText
            }

            VStack(alignment: .leading) {
                Text("Standard").font(.caption).bold()
                Text(".foregroundStyle(.primary)").foregroundStyle(.primary)
                Text(".foregroundStyle(.secondary)").foregroundStyle(.secondary)
                Text(".foregroundStyle(.tertiary)").foregroundStyle(.tertiary)
            }
        }
    }
    .padding()
}
