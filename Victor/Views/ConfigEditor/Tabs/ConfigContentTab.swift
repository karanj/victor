import SwiftUI

/// Content tab for Hugo configuration editor
/// Handles build options and output settings
struct ConfigContentTab: View {
    @Bindable var config: HugoConfig

    var body: some View {
        Form {
            Section("Build Options") {
                Toggle("Build Drafts", isOn: $config.buildDrafts)
                    .toggleStyle(.checkbox)
                    .help("Include draft content in builds")
                    .onChange(of: config.buildDrafts) { _, _ in
                        config.hasUnsavedChanges = true
                    }

                Toggle("Build Future", isOn: $config.buildFuture)
                    .toggleStyle(.checkbox)
                    .help("Include future-dated content in builds")
                    .onChange(of: config.buildFuture) { _, _ in
                        config.hasUnsavedChanges = true
                    }

                Toggle("Build Expired", isOn: $config.buildExpired)
                    .toggleStyle(.checkbox)
                    .help("Include expired content in builds")
                    .onChange(of: config.buildExpired) { _, _ in
                        config.hasUnsavedChanges = true
                    }
            }

            Section("Output") {
                Toggle("Enable robots.txt", isOn: $config.enableRobotsTXT)
                    .toggleStyle(.checkbox)
                    .help("Generate robots.txt file")
                    .onChange(of: config.enableRobotsTXT) { _, _ in
                        config.hasUnsavedChanges = true
                    }

                LabeledContent("Summary Length") {
                    Stepper("\(config.summaryLength) words",
                            value: $config.summaryLength, in: 10...500, step: 10)
                        .onChange(of: config.summaryLength) { _, _ in
                            config.hasUnsavedChanges = true
                        }
                }
                .help("Default length for auto-generated summaries")
            }
        }
        .formStyle(.grouped)
    }
}
