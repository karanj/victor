import SwiftUI

/// Tab selection for frontmatter editor
enum FrontmatterTab: String, CaseIterable {
    case essential = "Essential"
    case publishing = "Publishing"
    case seo = "SEO"
    case menus = "Menus"
    case advanced = "Advanced"

    var icon: String {
        switch self {
        case .essential: return "doc.text"
        case .publishing: return "calendar.badge.clock"
        case .seo: return "magnifyingglass"
        case .menus: return "list.bullet"
        case .advanced: return "gearshape"
        }
    }
}

/// View for editing Hugo frontmatter fields with tabbed interface
struct FrontmatterEditorView: View {
    @Bindable var frontmatter: Frontmatter
    @State private var selectedTab: FrontmatterTab = .essential

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            tabBar

            Divider()

            // Tab content
            ScrollView {
                tabContent
                    .padding()
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(FrontmatterTab.allCases, id: \.self) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func tabButton(for tab: FrontmatterTab) -> some View {
        Button(action: { selectedTab = tab }) {
            HStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.caption)
                Text(tab.rawValue)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .essential:
            EssentialFieldsTab(frontmatter: frontmatter)
        case .publishing:
            PublishingTab(frontmatter: frontmatter)
        case .seo:
            SEOTab(frontmatter: frontmatter)
        case .menus:
            MenusTab(frontmatter: frontmatter)
        case .advanced:
            AdvancedTab(frontmatter: frontmatter)
        }
    }
}

// MARK: - Form Field View (legacy support)

struct FormFieldView<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
        }
    }
}

// MARK: - Tag Input View

struct TagInputView: View {
    @Binding var tags: [String]
    var placeholder: String = "Add tag (press Enter)"
    @State private var newTag: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Display existing tags
            if !tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                        TagChip(
                            text: tag,
                            onDelete: { removeTag(at: index) }
                        )
                    }
                }
            }

            // Input for new tags
            HStack {
                TextField(placeholder, text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit {
                        addTag()
                    }

                if !newTag.isEmpty {
                    Button(action: addTag) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { return }
        tags.append(trimmed)
        newTag = ""
    }

    private func removeTag(at index: Int) {
        tags.remove(at: index)
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let text: String
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption)

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    // Move to next line
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
            }

            self.size = CGSize(
                width: maxWidth,
                height: currentY + lineHeight
            )
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleFrontmatter = Frontmatter(
        rawContent: """
        ---
        title: "Sample Blog Post"
        date: 2024-01-15T10:00:00Z
        draft: false
        tags: ["swift", "swiftui", "macos"]
        categories: ["development"]
        description: "A sample blog post demonstrating frontmatter editing"
        ---
        """,
        format: .yaml
    )

    sampleFrontmatter.title = "Sample Blog Post"
    sampleFrontmatter.date = Date()
    sampleFrontmatter.draft = false
    sampleFrontmatter.tags = ["swift", "swiftui", "macos"]
    sampleFrontmatter.categories = ["development"]
    sampleFrontmatter.description = "A sample blog post demonstrating frontmatter editing"
    sampleFrontmatter.menus = [MenuEntry(menuName: "main", weight: 10)]
    sampleFrontmatter.params = ["author": "Jane Doe", "featured": true]

    return FrontmatterEditorView(frontmatter: sampleFrontmatter)
        .frame(width: 450, height: 600)
}
