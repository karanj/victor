import SwiftUI

// MARK: - Badge Shape

/// The shape of a badge
enum BadgeShape {
    case roundedRectangle(cornerRadius: CGFloat)
    case capsule
}

// MARK: - Badge Modifier

/// A view modifier that applies consistent badge styling across the app
///
/// Usage:
/// ```swift
/// Text("Draft")
///     .badgeStyle(color: .orange)
///
/// Text("Block")
///     .badgeStyle(color: .blue, shape: .capsule)
///
/// Text("42")
///     .countBadgeStyle()
/// ```
struct BadgeModifier: ViewModifier {
    let color: Color
    let font: Font
    let fontWeight: Font.Weight?
    let backgroundOpacity: Double
    let shape: BadgeShape
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    func body(content: Content) -> some View {
        switch shape {
        case .roundedRectangle(let cornerRadius):
            content
                .font(font)
                .fontWeight(fontWeight)
                .foregroundStyle(color)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(color.opacity(backgroundOpacity))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        case .capsule:
            content
                .font(font)
                .fontWeight(fontWeight)
                .foregroundStyle(color)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(color.opacity(backgroundOpacity))
                .clipShape(Capsule())
        }
    }
}

// MARK: - View Extension

extension View {
    /// Applies badge styling with customizable color and shape
    ///
    /// - Parameters:
    ///   - color: The badge color (used for both text and tinted background)
    ///   - font: The font to use (default: .caption2)
    ///   - fontWeight: Optional font weight (default: nil)
    ///   - backgroundOpacity: Opacity for the background (default: 0.15)
    ///   - shape: Shape of the badge (default: roundedRectangle with 4pt radius)
    ///   - horizontalPadding: Horizontal padding (default: 6)
    ///   - verticalPadding: Vertical padding (default: 2)
    func badgeStyle(
        color: Color,
        font: Font = .caption2,
        fontWeight: Font.Weight? = nil,
        backgroundOpacity: Double = 0.15,
        shape: BadgeShape = .roundedRectangle(cornerRadius: 4),
        horizontalPadding: CGFloat = 6,
        verticalPadding: CGFloat = 2
    ) -> some View {
        modifier(BadgeModifier(
            color: color,
            font: font,
            fontWeight: fontWeight,
            backgroundOpacity: backgroundOpacity,
            shape: shape,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding
        ))
    }

    /// Applies badge styling with capsule shape (for status/tag badges)
    ///
    /// - Parameters:
    ///   - color: The badge color
    ///   - backgroundOpacity: Opacity for the background (default: 0.2)
    func capsuleBadgeStyle(
        color: Color,
        backgroundOpacity: Double = 0.2
    ) -> some View {
        badgeStyle(
            color: color,
            fontWeight: .medium,
            backgroundOpacity: backgroundOpacity,
            shape: .capsule
        )
    }

    /// Applies count badge styling (for match counts, item counts, etc.)
    /// Uses secondary color with control background
    func countBadgeStyle() -> some View {
        self
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Previews

#Preview("Standard Badge") {
    HStack(spacing: 12) {
        Text("Draft")
            .badgeStyle(color: .orange)

        Text("Scheduled")
            .badgeStyle(color: .blue)

        Text("Expired")
            .badgeStyle(color: .gray)
    }
    .padding()
}

#Preview("Capsule Badge") {
    HStack(spacing: 12) {
        Text("Deprecated")
            .capsuleBadgeStyle(color: Color.Status.warning)

        Text("Block")
            .capsuleBadgeStyle(color: Color.Status.info)

        Text("Required")
            .capsuleBadgeStyle(color: .red)
    }
    .padding()
}

#Preview("Count Badge") {
    HStack(spacing: 12) {
        Text("5")
            .countBadgeStyle()

        Text("42")
            .countBadgeStyle()

        Text("128")
            .countBadgeStyle()
    }
    .padding()
}

#Preview("Mixed Badges") {
    VStack(alignment: .leading, spacing: 12) {
        HStack {
            Text("config.toml")
            Spacer()
            Text("Config")
                .badgeStyle(color: .orange)
        }

        HStack {
            Text("_index.md")
            Spacer()
            Text("5 matches")
                .countBadgeStyle()
        }

        HStack {
            Text("figure")
            Text("Deprecated")
                .capsuleBadgeStyle(color: Color.Status.warning)
            Text("Block")
                .capsuleBadgeStyle(color: Color.Status.info)
        }
    }
    .padding()
    .frame(width: 300)
}
