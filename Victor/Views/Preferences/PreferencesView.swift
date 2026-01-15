import SwiftUI
import AppKit

/// Main preferences view with all settings in a single pane
struct PreferencesView: View {
    /// Use AppStorage for preferences that need to be accessible without SiteViewModel
    @AppStorage("highlightCurrentLine") private var highlightCurrentLine = true
    @AppStorage("editorFontSize") private var editorFontSize = 13.0
    @AppStorage("editorFontName") private var editorFontName = "SF Mono"
    @AppStorage("isAutoSaveEnabled") private var isAutoSaveEnabled = false
    @AppStorage("autoSaveDelay") private var autoSaveDelay = 2.0

    // Badge color preferences (stored as hex strings)
    @AppStorage("badgeColorDraft") private var draftColorHex = Color.BadgeColorKey.draft.defaultHex
    @AppStorage("badgeColorScheduled") private var scheduledColorHex = Color.BadgeColorKey.scheduled.defaultHex
    @AppStorage("badgeColorExpired") private var expiredColorHex = Color.BadgeColorKey.expired.defaultHex

    // Hugo server preferences
    @AppStorage("hugoServerPort") private var serverPort = 1313
    @AppStorage("hugoServerBuildDrafts") private var buildDrafts = false
    @AppStorage("hugoServerBuildFuture") private var buildFuture = false
    @AppStorage("hugoServerBuildExpired") private var buildExpired = false

    // Hugo version (loaded on appear)
    @State private var hugoVersion: String = "Checking..."
    @State private var isHugoInstalled: Bool = false

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
        TabView {
            // General tab - Editor and Auto-Save settings
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            // Appearance tab - Badge colors
            appearanceTab
                .tabItem {
                    Label("Appearance", systemImage: "paintpalette")
                }

            // Server tab - Hugo server settings
            serverTab
                .tabItem {
                    Label("Server", systemImage: "server.rack")
                }
        }
        .frame(minWidth: 400, idealWidth: 450, maxWidth: 550,
               minHeight: 350, idealHeight: 400, maxHeight: 500)
        .onAppear {
            checkHugoInstallation()
        }
    }

    private func checkHugoInstallation() {
        Task {
            isHugoInstalled = await HugoServerService.shared.isHugoInstalled()
            if let version = await HugoServerService.shared.getHugoVersion() {
                hugoVersion = version
            } else {
                hugoVersion = "Not installed"
            }
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
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
        }
        .formStyle(.grouped)
        .animation(.easeInOut(duration: 0.2), value: isAutoSaveEnabled)
    }

    // MARK: - Appearance Tab

    private var appearanceTab: some View {
        Form {
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
    }

    // MARK: - Server Tab

    private var serverTab: some View {
        Form {
            Section {
                HStack {
                    Text("Hugo:")
                    Spacer()
                    if isHugoInstalled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Installed")
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text("Not found")
                            .foregroundStyle(.secondary)
                    }
                }

                if isHugoInstalled {
                    HStack {
                        Text("Version:")
                        Spacer()
                        Text(hugoVersion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else {
                    Link("Install Hugo", destination: URL(string: "https://gohugo.io/installation/")!)
                        .font(.callout)
                }
            } header: {
                Text("Hugo Installation")
            }

            Section {
                HStack {
                    Text("Default Port:")
                    Spacer()
                    TextField("", value: $serverPort,
                              format: .number.grouping(.never),
                              prompt: Text("(1024-65535)"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .multilineTextAlignment(.trailing)
                }

                Toggle("Build drafts", isOn: $buildDrafts)
                    .toggleStyle(.checkbox)

                Toggle("Build future posts", isOn: $buildFuture)
                    .toggleStyle(.checkbox)

                Toggle("Build expired posts", isOn: $buildExpired)
                    .toggleStyle(.checkbox)
            } header: {
                Text("Server Defaults")
            } footer: {
                Text("These settings are used when starting the Hugo development server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Preview

#Preview {
    PreferencesView()
}
