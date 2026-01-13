import SwiftUI
import AppKit

/// Main preferences view with all settings in a single pane
struct PreferencesView: View {
    /// Use AppStorage for preferences that need to be accessible without SiteViewModel
    @AppStorage("highlightCurrentLine") private var highlightCurrentLine = true
    @AppStorage("editorFontSize") private var editorFontSize = 13.0
    @AppStorage("editorFontName") private var editorFontName = "SF Mono"
    @AppStorage("isAutoSaveEnabled") private var isAutoSaveEnabled = true
    @AppStorage("autoSaveDelay") private var autoSaveDelay = 2.0

    // Badge color preferences (stored as hex strings)
    @AppStorage("badgeColorDraft") private var draftColorHex = Color.BadgeColorKey.draft.defaultHex
    @AppStorage("badgeColorScheduled") private var scheduledColorHex = Color.BadgeColorKey.scheduled.defaultHex
    @AppStorage("badgeColorExpired") private var expiredColorHex = Color.BadgeColorKey.expired.defaultHex

    /// Binding to convert hex string to Color for ColorPicker
    private var draftColor: Binding<Color> {
        Binding(
            get: { Color(hex: draftColorHex) ?? Color.BadgeColorKey.draft.defaultColor },
            set: { draftColorHex = $0.hexString }
        )
    }

    private var scheduledColor: Binding<Color> {
        Binding(
            get: { Color(hex: scheduledColorHex) ?? Color.BadgeColorKey.scheduled.defaultColor },
            set: { scheduledColorHex = $0.hexString }
        )
    }

    private var expiredColor: Binding<Color> {
        Binding(
            get: { Color(hex: expiredColorHex) ?? Color.BadgeColorKey.expired.defaultColor },
            set: { expiredColorHex = $0.hexString }
        )
    }

    /// Available font sizes
    private let fontSizes: [Double] = [10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24]

    /// Available delay options in seconds
    private let delayOptions: [(label: String, value: Double)] = [
        ("1 second", 1.0),
        ("2 seconds", 2.0),
        ("3 seconds", 3.0),
        ("5 seconds", 5.0),
        ("10 seconds", 10.0)
    ]

    /// All installed monospace fonts from the system
    private var availableFonts: [String] {
        var fonts = NSFontManager.shared.availableFontFamilies.filter { family in
            guard let font = NSFont(name: family, size: 13) else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.monoSpace)
        }.sorted()

        // Always include "SF Mono" as an option (maps to system monospace)
        if !fonts.contains("SF Mono") {
            fonts.insert("SF Mono", at: 0)
        }

        return fonts
    }

    /// Validated font name - ensures the selection exists in available fonts
    private var validatedFontName: Binding<String> {
        Binding(
            get: { availableFonts.contains(editorFontName) ? editorFontName : "SF Mono" },
            set: { editorFontName = $0 }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Font:", selection: validatedFontName) {
                    ForEach(availableFonts, id: \.self) { fontName in
                        Text(fontName)
                            .font(.custom(fontName, size: 13))
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
                    .toggleStyle(.checkbox)
            } header: {
                Text("Editor")
            }

            Section {
                Toggle("Enable auto-save", isOn: $isAutoSaveEnabled)
                    .toggleStyle(.checkbox)

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
                Text(isAutoSaveEnabled
                    ? "Files are automatically saved after you stop typing."
                    : "Use Command+S to save manually.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ColorPicker("Draft:", selection: draftColor, supportsOpacity: false)
                ColorPicker("Scheduled:", selection: scheduledColor, supportsOpacity: false)
                ColorPicker("Expired:", selection: expiredColor, supportsOpacity: false)

                Button("Reset to Defaults") {
                    draftColorHex = Color.BadgeColorKey.draft.defaultHex
                    scheduledColorHex = Color.BadgeColorKey.scheduled.defaultHex
                    expiredColorHex = Color.BadgeColorKey.expired.defaultHex
                }
                .buttonStyle(.link)
            } header: {
                Text("Badge Colors")
            } footer: {
                Text("Colors for content status badges in the sidebar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 350, idealWidth: 400, maxWidth: 500,
               minHeight: 350, idealHeight: 420, maxHeight: 500)
        .animation(.easeInOut(duration: 0.2), value: isAutoSaveEnabled)
    }
}

// MARK: - Preview

#Preview {
    PreferencesView()
}
