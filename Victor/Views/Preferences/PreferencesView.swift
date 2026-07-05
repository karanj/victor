import SwiftUI
import AppKit

/// Main preferences view with all settings in a single pane
struct PreferencesView: View {
    /// Shared settings instance - the File-menu toggle and this window observe each other
    @Bindable private var settings = AppSettings.shared

    // Hugo version (loaded on appear)
    @State private var hugoVersion: String = "Checking..."
    @State private var isHugoInstalled: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Binding to convert hex string to Color for ColorPicker
    private var draftColor: Binding<Color> {
        Binding(
            get: { Color(hex: settings.badgeColorDraftHex) ?? Color.BadgeColorKey.draft.defaultColor },
            set: { settings.badgeColorDraftHex = $0.hexString }
        )
    }

    private var scheduledColor: Binding<Color> {
        Binding(
            get: { Color(hex: settings.badgeColorScheduledHex) ?? Color.BadgeColorKey.scheduled.defaultColor },
            set: { settings.badgeColorScheduledHex = $0.hexString }
        )
    }

    private var expiredColor: Binding<Color> {
        Binding(
            get: { Color(hex: settings.badgeColorExpiredHex) ?? Color.BadgeColorKey.expired.defaultColor },
            set: { settings.badgeColorExpiredHex = $0.hexString }
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
            get: { availableFonts.contains(settings.editorFontName) ? settings.editorFontName : "SF Mono" },
            set: { settings.editorFontName = $0 }
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

    /// victor-zw4: kept on `.shared` rather than injected - `PreferencesView()` is
    /// constructed with zero args from a `Settings` scene (`VictorApp.swift`) with no
    /// `SiteViewModel` or other seam available, so threading an instance through would
    /// mean adding SwiftUI Environment plumbing solely for this one version check.
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

                Picker("Font Size:", selection: $settings.editorFontSize) {
                    ForEach(fontSizes, id: \.self) { size in
                        Text("\(Int(size)) pt").tag(size)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Highlight current line", isOn: $settings.highlightCurrentLine)
                    .toggleStyle(.checkbox)
            } header: {
                Text("Editor")
            }

            Section {
                Toggle("Enable auto-save", isOn: $settings.isAutoSaveEnabled)
                    .toggleStyle(.checkbox)

                if settings.isAutoSaveEnabled {
                    Picker("Save after:", selection: $settings.autoSaveDelay) {
                        ForEach(delayOptions, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text("Auto-Save")
            } footer: {
                Text(settings.isAutoSaveEnabled
                    ? "Files are automatically saved after you stop typing."
                    : "Use Command+S to save manually.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .animation(reduceMotion ? nil : .easeInOut(duration: AppConstants.Animation.standard), value: settings.isAutoSaveEnabled)
    }

    // MARK: - Appearance Tab

    private var appearanceTab: some View {
        Form {
            Section {
                ColorPicker("Draft:", selection: draftColor, supportsOpacity: false)
                ColorPicker("Scheduled:", selection: scheduledColor, supportsOpacity: false)
                ColorPicker("Expired:", selection: expiredColor, supportsOpacity: false)

                Button("Reset to Defaults") {
                    settings.badgeColorDraftHex = Color.BadgeColorKey.draft.defaultHex
                    settings.badgeColorScheduledHex = Color.BadgeColorKey.scheduled.defaultHex
                    settings.badgeColorExpiredHex = Color.BadgeColorKey.expired.defaultHex
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
                            .foregroundStyle(Color.Status.saved)
                        Text("Installed")
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.Status.error)
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
                    TextField("", value: $settings.hugoServerPort,
                              format: .number.grouping(.never),
                              prompt: Text("(1024-65535)"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .multilineTextAlignment(.trailing)
                }

                Toggle("Build drafts", isOn: $settings.hugoServerBuildDrafts)
                    .toggleStyle(.checkbox)

                Toggle("Build future posts", isOn: $settings.hugoServerBuildFuture)
                    .toggleStyle(.checkbox)

                Toggle("Build expired posts", isOn: $settings.hugoServerBuildExpired)
                    .toggleStyle(.checkbox)
            } header: {
                Text("Server Defaults")
            } footer: {
                Text("These settings are used when starting the Hugo development server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Notify when a build fails in the background", isOn: $settings.notifyOnBuildFailure)
                    .toggleStyle(.checkbox)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Shows a notification if a Hugo build fails while Victor isn't the active app. Failures while you're working in Victor still appear inline.")
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
