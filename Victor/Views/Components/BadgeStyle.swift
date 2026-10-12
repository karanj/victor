import SwiftUI

// MARK: - Badge Shape

/// The shape of a badge
enum BadgeShape {
    case roundedRectangle(cornerRadius: CGFloat)
    case capsule
}

// MARK: - Badge Modifier

/// Applies consistent badge styling across the app.
///
///     Text("Draft").badgeStyle(color: .orange)
///     Text("Block").badgeStyle(color: .blue, shape: .capsule)
///     Text("42").countBadgeStyle()
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
    /// `color` tints both the text and the background.
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

    /// Capsule variant, for status/tag badges.
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

    /// Neutral grey chip for metadata labels (file type, format, theme name).
    func secondaryBadgeStyle(
        font: Font = .caption,
        horizontalPadding: CGFloat = 6,
        cornerRadius: CGFloat = 4
    ) -> some View {
        self
            .font(font)
            .foregroundStyle(.secondary)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: cornerRadius))
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

// MARK: - File Tag Badge

/// Filled tag trailing a file name in the sidebar and folder view
/// (bundle, config, Draft, ...).
/// Fixed-size so the file name truncates first instead of the badge wrapping.
struct FileTagBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .lineLimit(1)
            .foregroundStyle(color.contrastingTextColor)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color, in: RoundedRectangle(cornerRadius: 3))
            .fixedSize()
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
