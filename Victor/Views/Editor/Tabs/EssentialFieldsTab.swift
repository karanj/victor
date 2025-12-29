import SwiftUI

/// Essential frontmatter fields tab - the most commonly used fields
struct EssentialFieldsTab: View {
    @Bindable var frontmatter: Frontmatter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            FormFieldWithHelp(label: "Title", help: "The main title of your page") {
                TextField("Post title", text: Binding(
                    get: { frontmatter.title ?? "" },
                    set: { frontmatter.title = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            // Date
            OptionalDateField(
                label: "Date",
                help: "The date associated with this content",
                date: $frontmatter.date
            )

            // Draft Status
            FormFieldWithHelp(label: "Draft", help: "Draft pages aren't published to your site") {
                Toggle("Mark as draft", isOn: Binding(
                    get: { frontmatter.draft ?? false },
                    set: { frontmatter.draft = $0 }
                ))
            }

            // Description with character count
            TextEditorWithCount(
                label: "Description",
                help: "Meta description for search engines (aim for 150-160 characters)",
                text: $frontmatter.description,
                idealLength: 150,
                maxLength: 160,
                height: 60
            )

            // Tags
            FormFieldWithHelp(label: "Tags", help: "Tags help categorize and discover your content") {
                TagInputView(tags: Binding(
                    get: { frontmatter.tags ?? [] },
                    set: { frontmatter.tags = $0.isEmpty ? nil : $0 }
                ))
            }

            // Categories
            FormFieldWithHelp(label: "Categories", help: "Broader classification than tags") {
                TagInputView(tags: Binding(
                    get: { frontmatter.categories ?? [] },
                    set: { frontmatter.categories = $0.isEmpty ? nil : $0 }
                ))
            }
        }
    }
}

#Preview {
    let frontmatter = Frontmatter(rawContent: "---\n---", format: .yaml)
    frontmatter.title = "Sample Post"
    frontmatter.date = Date()
    frontmatter.draft = false
    frontmatter.tags = ["swift", "swiftui"]
    frontmatter.categories = ["development"]
    frontmatter.description = "A sample blog post"

    return ScrollView {
        EssentialFieldsTab(frontmatter: frontmatter)
            .padding()
    }
    .frame(width: 400, height: 500)
}
