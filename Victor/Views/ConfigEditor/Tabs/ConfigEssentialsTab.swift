import SwiftUI

/// Essentials tab for Hugo configuration editor
/// Handles basic site identity, theme, and copyright settings
struct ConfigEssentialsTab: View {
    @Bindable var config: HugoConfig

    var body: some View {
        Form {
            Section("Site Identity") {
                LabeledContent("Base URL") {
                    TextField("",text: $config.baseURL, prompt: Text("https://example.com/"))
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor))
                        .disableAutocorrection(true)
                        .onChange(of: config.baseURL) { _, _ in
                            config.hasUnsavedChanges = true
                        }
                }
                .help("The absolute URL of your site")

                LabeledContent("Title") {
                    TextField("", text: $config.title, prompt: Text("My Site"))
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor))
                        .onChange(of: config.title) { _, _ in
                            config.hasUnsavedChanges = true
                        }
                }
                .help("The title of your site")

                LabeledContent("Language Code") {
                    TextField("", text: $config.languageCode,prompt: Text("en-us"))
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor))
                        .onChange(of: config.languageCode) { _, _ in
                            config.hasUnsavedChanges = true
                        }
                }
                .help("RFC 5646 language code (e.g., en-us)")
            }

            Section("Theme") {
                LabeledContent("Theme") {
                    TextField("", text: Binding(
                        get: { config.theme ?? "" },
                        set: { config.theme = $0.isEmpty ? nil : $0 }
                    ),prompt: Text("theme-name"))
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .onChange(of: config.theme) { _, _ in
                        config.hasUnsavedChanges = true
                    }
                }
                .help("Theme name or comma-separated list of themes")
            }

            Section("Copyright") {
                LabeledContent("Copyright") {
                    TextField("", text: Binding(
                        get: { config.copyright ?? "" },
                        set: { config.copyright = $0.isEmpty ? nil : $0 }
                    ), prompt: Text("© 2025 Your Name"))
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .onChange(of: config.copyright) { _, _ in
                        config.hasUnsavedChanges = true
                    }
                }
                .help("Copyright notice for your site footer")
            }
        }
        .formStyle(.grouped)
    }
}
