import SwiftUI

/// Publishing-related frontmatter fields tab
struct PublishingTab: View {
    @Bindable var frontmatter: Frontmatter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Dates Section
            SectionHeader("Dates", help: "Control when content appears on your site")

            OptionalDateField(
                label: "Publish Date",
                help: "Content won't appear until this date",
                date: $frontmatter.publishDate
            )

            OptionalDateField(
                label: "Expiry Date",
                help: "Content will be hidden after this date",
                date: $frontmatter.expiryDate
            )

            OptionalDateField(
                label: "Last Modified",
                help: "When this content was last updated",
                date: $frontmatter.lastmod
            )

            // MARK: - Ordering Section
            SectionHeader("Ordering", help: "Control how content is sorted in lists")

            NumberField(
                label: "Weight",
                help: "Lower numbers appear first in lists (default: 0)",
                value: $frontmatter.weight,
                placeholder: "0"
            )

            // MARK: - URL Settings Section
            SectionHeader("URL Settings", help: "Override the default URL for this page")

            TextFieldWithCount(
                label: "Slug",
                help: "The last part of the URL (e.g., /blog/[slug])",
                text: $frontmatter.slug,
                placeholder: "my-post-slug"
            )

            TextFieldWithCount(
                label: "URL",
                help: "Override the entire URL path",
                text: $frontmatter.url,
                placeholder: "/custom/path/"
            )

            // Aliases
            FormFieldWithHelp(label: "Aliases", help: "Old URLs that redirect to this page") {
                TagInputView(tags: Binding(
                    get: { frontmatter.aliases ?? [] },
                    set: { frontmatter.aliases = $0.isEmpty ? nil : $0; frontmatter.markChanged() }
                ), placeholder: "Add alias (e.g., /old-path)")
            }
        }
        // Change detection for frontmatter edits
        .onChange(of: frontmatter.publishDate) { _, _ in frontmatter.markChanged() }
        .onChange(of: frontmatter.expiryDate) { _, _ in frontmatter.markChanged() }
        .onChange(of: frontmatter.lastmod) { _, _ in frontmatter.markChanged() }
        .onChange(of: frontmatter.weight) { _, _ in frontmatter.markChanged() }
        .onChange(of: frontmatter.slug) { _, _ in frontmatter.markChanged() }
        .onChange(of: frontmatter.url) { _, _ in frontmatter.markChanged() }
    }
}

#Preview {
    let frontmatter = Frontmatter(rawContent: "---\n---", format: .yaml)
    frontmatter.publishDate = Date().addingTimeInterval(86400 * 7) // 1 week from now
    frontmatter.weight = 10
    frontmatter.slug = "my-custom-slug"
    frontmatter.aliases = ["/old-path", "/another-old-path"]

    return ScrollView {
        PublishingTab(frontmatter: frontmatter)
            .padding()
    }
    .frame(width: 400, height: 600)
}
