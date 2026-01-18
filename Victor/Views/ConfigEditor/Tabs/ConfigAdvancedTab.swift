import SwiftUI

/// Advanced tab for Hugo configuration editor
/// Handles localization settings and displays custom fields and params
struct ConfigAdvancedTab: View {
    @Bindable var config: HugoConfig

    var body: some View {
        Form {
            Section("Localization") {
                LabeledContent("Default Language") {
                    TextField("", text: $config.defaultContentLanguage,prompt: Text("en"))
                        .frame(width: 100)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor))
                        .onChange(of: config.defaultContentLanguage) { _, _ in
                            config.hasUnsavedChanges = true
                        }
                }

                LabeledContent("Time Zone") {
                    TextField("", text: Binding(
                        get: { config.timeZone ?? "" },
                        set: { config.timeZone = $0.isEmpty ? nil : $0 }
                    ),prompt: Text("America/New_York"))
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .onChange(of: config.timeZone) { _, _ in
                        config.hasUnsavedChanges = true
                    }
                }
                .help("IANA time zone (e.g., America/New_York, Europe/London)")
            }

            if !config.customFields.isEmpty {
                Section("Other Fields (Preserved)") {
                    ForEach(Array(config.customFields.keys.sorted()), id: \.self) { key in
                        LabeledContent(key) {
                            Text(formatValue(config.customFields[key]))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            if !config.params.isEmpty {
                Section("Site Params") {
                    ForEach(Array(config.params.keys.sorted()), id: \.self) { key in
                        LabeledContent(key) {
                            Text(formatValue(config.params[key]))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func formatValue(_ value: Any?) -> String {
        guard let value = value else { return "nil" }
        if let dict = value as? [String: Any] {
            return "{\(dict.count) fields}"
        } else if let array = value as? [Any] {
            return "[\(array.count) items]"
        }
        return String(describing: value)
    }
}
