import SwiftUI
import AppKit

/// Main preferences view with tabbed sections
struct PreferencesView: View {
    /// Use AppStorage for preferences that need to be accessible without SiteViewModel
    @AppStorage("highlightCurrentLine") private var highlightCurrentLine = true
    @AppStorage("editorFontSize") private var editorFontSize = 13.0
    @AppStorage("editorFontName") private var editorFontName = "SF Mono"
    @AppStorage("isAutoSaveEnabled") private var isAutoSaveEnabled = true
    @AppStorage("autoSaveDelay") private var autoSaveDelay = 2.0

    var body: some View {
        TabView {
            EditorPreferencesTab(
                highlightCurrentLine: $highlightCurrentLine,
                editorFontSize: $editorFontSize,
                editorFontName: $editorFontName
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
    @Binding var editorFontName: String

    /// Available font sizes
    private let fontSizes: [Double] = [10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24]

    /// All installed monospace fonts from the system
    private var availableFonts: [String] {
        var fonts = NSFontManager.shared.availableFontFamilies.filter { family in
            guard let font = NSFont(name: family, size: 13) else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.monoSpace)
        }.sorted()

        // Include the system monospace font if not already present
        // (it may not appear in availableFontFamilies since it's accessed via monospacedSystemFont)
        if let systemMonoFamily = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular).familyName,
           !fonts.contains(systemMonoFamily) {
            fonts.append(systemMonoFamily)
            fonts.sort()
        }

        return fonts
    }

    var body: some View {
        Form {
            Section {
                Picker("Font:", selection: $editorFontName) {
                    ForEach(availableFonts, id: \.self) { fontName in
                        Text(fontName)
                            .font(.custom(fontName == ".AppleSystemUIFontMonospaced-Regular" ? "SF Mono" : fontName, size: 13))
                            .tag(fontName)
                    }
                }
                .pickerStyle(.menu)

                Picker("Font Size:", selection: $editorFontSize) {
                    ForEach(fontSizes, id: \.self) { size in
                        Text("\(Int(size)) pt").tag(size)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Highlight current line", isOn: $highlightCurrentLine)
            } header: {
                Text("Editor Appearance")
            } footer: {
                Text("Changes apply immediately to the editor.")
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
