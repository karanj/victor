import SwiftUI

/// SEO and sitemap-related frontmatter fields tab
struct SEOTab: View {
    @Bindable var frontmatter: Frontmatter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - SEO Section
            SectionHeader("Search Engine Optimization")

            // Keywords
            FormFieldWithHelp(label: "Keywords", help: "Keywords for search engines") {
                TagInputView(tags: Binding(
                    get: { frontmatter.keywords ?? [] },
                    set: { frontmatter.keywords = $0.isEmpty ? nil : $0 }
                ), placeholder: "Add keyword")
            }

            // Summary
            TextEditorWithCount(
                label: "Summary",
                help: "Custom summary or teaser text (used in listings and social shares)",
                text: $frontmatter.summary,
                idealLength: 200,
                maxLength: 300,
                height: 80
            )

            // Link Title
            TextFieldWithCount(
                label: "Link Title",
                help: "Short title used in menus and links",
                text: $frontmatter.linkTitle,
                placeholder: "Short title"
            )

            // MARK: - Sitemap Section
            SectionHeader("Sitemap", help: "Control how this page appears in sitemap.xml")

            // Change Frequency
            FormFieldWithHelp(
                label: "Change Frequency",
                help: "How often this page typically changes"
            ) {
                Picker("", selection: Binding(
                    get: { frontmatter.sitemap?.changefreq ?? .monthly },
                    set: { newValue in
                        ensureSitemapExists()
                        frontmatter.sitemap?.changefreq = newValue
                    }
                )) {
                    Text("Not set").tag(Optional<SitemapConfig.ChangeFreq>.none)
                    Divider()
                    ForEach(SitemapConfig.ChangeFreq.allCases, id: \.self) { freq in
                        Text(freq.description).tag(Optional(freq))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
            }

            // Priority
            FormFieldWithHelp(
                label: "Priority",
                help: "Relative importance (0.5 is default, 0.0-1.0 range)"
            ) {
                HStack {
                    Toggle("", isOn: Binding(
                        get: { frontmatter.sitemap?.priority != nil },
                        set: { isOn in
                            ensureSitemapExists()
                            frontmatter.sitemap?.priority = isOn ? 0.5 : nil
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()

                    if frontmatter.sitemap?.priority != nil {
                        Slider(value: Binding(
                            get: { frontmatter.sitemap?.priority ?? 0.5 },
                            set: {
                                ensureSitemapExists()
                                frontmatter.sitemap?.priority = $0
                            }
                        ), in: 0...1, step: 0.1)
                        .frame(width: 150)

                        Text(String(format: "%.1f", frontmatter.sitemap?.priority ?? 0.5))
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 30)
                    } else {
                        Text("Default (0.5)")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    }

                    Spacer()
                }
            }

            // Exclude from Sitemap
            FormFieldWithHelp(
                label: "Exclude",
                help: "Hide this page from sitemap.xml"
            ) {
                Toggle("Exclude from sitemap", isOn: Binding(
                    get: { frontmatter.sitemap?.disable ?? false },
                    set: {
                        ensureSitemapExists()
                        frontmatter.sitemap?.disable = $0
                    }
                ))
            }
        }
    }

    private func ensureSitemapExists() {
        if frontmatter.sitemap == nil {
            frontmatter.sitemap = SitemapConfig()
        }
    }
}

#Preview {
    let frontmatter = Frontmatter(rawContent: "---\n---", format: .yaml)
    frontmatter.keywords = ["hugo", "static site", "cms"]
    frontmatter.summary = "A sample summary for the page"
    frontmatter.linkTitle = "Short Title"
    frontmatter.sitemap = SitemapConfig(changefreq: .monthly, priority: 0.8)

    return ScrollView {
        SEOTab(frontmatter: frontmatter)
            .padding()
    }
    .frame(width: 400, height: 600)
}
