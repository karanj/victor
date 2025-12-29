import SwiftUI

/// Main preferences view with tabbed sections
struct PreferencesView: View {
    /// Use AppStorage for preferences that need to be accessible without SiteViewModel
    @AppStorage("highlightCurrentLine") private var highlightCurrentLine = true
    @AppStorage("editorFontSize") private var editorFontSize = 13.0
    @AppStorage("isAutoSaveEnabled") private var isAutoSaveEnabled = true
    @AppStorage("autoSaveDelay") private var autoSaveDelay = 2.0

    var body: some View {
        TabView {
            EditorPreferencesTab(
                highlightCurrentLine: $highlightCurrentLine,
                editorFontSize: $editorFontSize
            )
            .tabItem {
                Label("Editor", systemImage: "pencil")
            }

            AutoSavePreferencesTab(
                isAutoSaveEnabled: $isAutoSaveEnabled,
                autoSaveDelay: $autoSaveDelay
            )
            .tabItem {
                Label("Auto-Save", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .frame(width: 450, height: 250)
    }
}

// MARK: - Editor Preferences Tab

struct EditorPreferencesTab: View {
    @Binding var highlightCurrentLine: Bool
    @Binding var editorFontSize: Double

    /// Available font sizes
    private let fontSizes: [Double] = [11, 12, 13, 14, 15, 16, 18, 20, 22, 24]

    var body: some View {
        Form {
            Section {
                Picker("Font Size:", selection: $editorFontSize) {
                    ForEach(fontSizes, id: \.self) { size in
                        Text("\(Int(size)) pt").tag(size)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)

                Toggle("Highlight current line", isOn: $highlightCurrentLine)
            } header: {
                Text("Editor Appearance")
            } footer: {
                Text("Changes apply to newly opened files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Auto-Save Preferences Tab

struct AutoSavePreferencesTab: View {
    @Binding var isAutoSaveEnabled: Bool
    @Binding var autoSaveDelay: Double

    /// Available delay options in seconds
    private let delayOptions: [(label: String, value: Double)] = [
        ("1 second", 1.0),
        ("2 seconds", 2.0),
        ("3 seconds", 3.0),
        ("5 seconds", 5.0),
        ("10 seconds", 10.0)
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Enable auto-save", isOn: $isAutoSaveEnabled)

                if isAutoSaveEnabled {
                    Picker("Save after:", selection: $autoSaveDelay) {
                        ForEach(delayOptions, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                }
            } header: {
                Text("Auto-Save")
            } footer: {
                if isAutoSaveEnabled {
                    Text("Files are automatically saved after you stop typing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Use Command+S to save manually.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .animation(.easeInOut(duration: 0.2), value: isAutoSaveEnabled)
    }
}

// MARK: - Preview

#Preview {
    PreferencesView()
}
