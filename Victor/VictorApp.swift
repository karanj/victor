import SwiftUI
import AppKit

// MARK: - App Delegate for Quit Confirmation

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Reference to check for unsaved changes
    weak var siteViewModel: SiteViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable native window tabbing - app architecture is single-window
        // Enabling tabs causes freeze due to shared SiteViewModel state conflicts
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Check if there are unsaved changes
        guard let viewModel = siteViewModel, viewModel.hasUnsavedChanges else {
            return .terminateNow
        }

        // Show confirmation dialog
        let alert = NSAlert()
        alert.messageText = "You have unsaved changes"
        alert.informativeText = "Do you want to save your changes before quitting?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save and Quit")
        alert.addButton(withTitle: "Quit Without Saving")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // Save and quit
            Task { @MainActor in
                await viewModel.saveAllModifiedFiles()
                NSApp.terminate(nil)
            }
            return .terminateCancel // Cancel for now, will terminate after save

        case .alertSecondButtonReturn:
            // Quit without saving
            return .terminateNow

        default:
            // Cancel
            return .terminateCancel
        }
    }
}

// MARK: - Focused Values for Editor Commands

struct EditorFormattingKey: FocusedValueKey {
    typealias Value = (MarkdownFormat) -> Void
}

struct ShortcodePickerKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var editorFormatting: EditorFormattingKey.Value? {
        get { self[EditorFormattingKey.self] }
        set { self[EditorFormattingKey.self] = newValue }
    }

    var showShortcodePicker: ShortcodePickerKey.Value? {
        get { self[ShortcodePickerKey.self] }
        set { self[ShortcodePickerKey.self] = newValue }
    }
}

@main
struct VictorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var siteViewModel = SiteViewModel()
    @FocusedValue(\.editorFormatting) private var editorFormatting
    @FocusedValue(\.showShortcodePicker) private var showShortcodePicker

    // Editor preferences (using @AppStorage for sync with Preferences window)
    @AppStorage("highlightCurrentLine") private var highlightCurrentLine = true
    @AppStorage("isAutoSaveEnabled") private var isAutoSaveEnabled = true

    // Accessibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some Scene {
        WindowGroup {
            ContentView(siteViewModel: siteViewModel)
                .frame(minWidth: AppConstants.Window.minWidth, minHeight: AppConstants.Window.minHeight)
                .onAppear {
                    // Wire up app delegate to view model for quit confirmation
                    appDelegate.siteViewModel = siteViewModel
                }
        }
        .defaultSize(width: AppConstants.Window.defaultWidth, height: AppConstants.Window.defaultHeight)
        .commands {
            // Standard text editing commands (includes Edit > Find menu)
            TextEditingCommands()

            // File menu commands
            CommandGroup(replacing: .newItem) {
                Button("Open Hugo Site...") {
                    Task {
                        await siteViewModel.openSiteFolder()
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .saveItem) {
                Toggle("Auto-Save", isOn: $isAutoSaveEnabled)
            }

            // Format menu - Text formatting
            CommandGroup(after: .textFormatting) {
                Button("Bold") {
                    editorFormatting?(.bold)
                }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(editorFormatting == nil)

                Button("Italic") {
                    editorFormatting?(.italic)
                }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(editorFormatting == nil)

                Divider()

                Button("Insert Link") {
                    editorFormatting?(.link)
                }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(editorFormatting == nil)

                Button("Insert Image") {
                    editorFormatting?(.image)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(editorFormatting == nil)

                Button("Insert Shortcode...") {
                    showShortcodePicker?()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(showShortcodePicker == nil)

                Button("Block Quote") {
                    editorFormatting?(.blockquote)
                }
                .keyboardShortcut("'", modifiers: .command)
                .disabled(editorFormatting == nil)
            }

            // View menu - Search and Navigation
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("s", modifiers: [.control, .command])

                Divider()

                Button("Search Files") {
                    siteViewModel.shouldFocusSearch = true
                }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(siteViewModel.site == nil)

                Button("Find in Files...") {
                    siteViewModel.isGlobalSearchPresented = true
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(siteViewModel.site == nil)
            }

            // View menu - Layout modes
            CommandGroup(after: .toolbar) {
                Divider()

                Button("Editor Only") {
                    siteViewModel.layoutMode = .editor
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Preview Only") {
                    siteViewModel.layoutMode = .preview
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Split View") {
                    siteViewModel.layoutMode = .split
                }
                .keyboardShortcut("3", modifiers: .command)

                Divider()

                Button(siteViewModel.isInspectorVisible ? "Hide Inspector" : "Show Inspector") {
                    if reduceMotion {
                        siteViewModel.toggleInspector()
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            siteViewModel.toggleInspector()
                        }
                    }
                }
                .keyboardShortcut("i", modifiers: [.option, .command])

                Divider()

                Button(siteViewModel.isFocusModeActive ? "Exit Focus Mode" : "Enter Focus Mode") {
                    if reduceMotion {
                        siteViewModel.toggleFocusMode()
                    } else {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            siteViewModel.toggleFocusMode()
                        }
                    }
                }
                .keyboardShortcut("f", modifiers: [.control, .command])
                .disabled(siteViewModel.selectedNode == nil)

                Divider()

                Toggle("Highlight Current Line", isOn: $highlightCurrentLine)
            }
        }

        // Preferences window (Cmd+,)
        Settings {
            PreferencesView()
        }
    }
}
