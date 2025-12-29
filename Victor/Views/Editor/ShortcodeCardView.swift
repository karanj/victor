import SwiftUI

// MARK: - Shortcode Card View

/// Card view for displaying a shortcode in the picker list
struct ShortcodeCardView: View {
    let shortcode: HugoShortcode

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: shortcode.icon)
                .font(.title2)
                .foregroundStyle(shortcode.isDeprecated ? .secondary : .primary)
                .frame(width: 32)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(shortcode.name)
                        .font(.headline)
                        .foregroundStyle(shortcode.isDeprecated ? .secondary : .primary)

                    if shortcode.isDeprecated {
                        Text("Deprecated")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }

                    if shortcode.hasClosingTag {
                        Text("Block")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }

                Text(shortcode.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Required params indicator
            if !shortcode.requiredParameters.isEmpty {
                Text("\(shortcode.requiredParameters.count) required")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        ForEach(HugoShortcode.allShortcodes.prefix(5)) { shortcode in
            ShortcodeCardView(shortcode: shortcode)
                .padding(.horizontal)
            Divider()
        }
    }
    .frame(width: 350)
}
