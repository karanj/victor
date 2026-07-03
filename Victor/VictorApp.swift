import SwiftUI
import AppKit

// MARK: - Find Panel Helper

/// Helper to trigger NSTextView's native find panel from SwiftUI menu commands
enum FindPanelHelper {
    /// Extended actions from NSTextFinder.Action (not all in NSFindPanelAction)
    static let showReplaceInterface = 12  // NSTextFinder.Action.showReplaceInterface

    /// Perform a find panel action on the current first responder
    static func performAction(_ action: NSFindPanelAction) {
        performActionWithTag(Int(action.rawValue))
    }

    /// Perform a find panel action with a raw tag value (for NSTextFinder.Action values)
    static func performActionWithTag(_ tag: Int) {
        // Create a menu item with the action tag (NSTextView uses sender.tag)
        let menuItem = NSMenuItem()
        menuItem.tag = tag

        // Send the action through the responder chain
        NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: menuItem)
    }
}

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

    // Editor preferences (shared with Preferences window via AppSettings)
    @Bindable private var settings = AppSettings.shared

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
            // Find menu commands - route to NSTextView's native find bar
            CommandGroup(replacing: .textEditing) {
                Button("Find...") {
                    FindPanelHelper.performAction(.showFindPanel)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Find and Replace...") {
                    // Use NSTextFinder.Action.showReplaceInterface (value 12)
                    FindPanelHelper.performActionWithTag(FindPanelHelper.showReplaceInterface)
                }
                .keyboardShortcut("f", modifiers: [.command, .option])

                Button("Find Next") {
                    FindPanelHelper.performAction(.next)
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("Find Previous") {
                    FindPanelHelper.performAction(.previous)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Button("Use Selection for Find") {
                    FindPanelHelper.performAction(.setFindString)
                }
                .keyboardShortcut("e", modifiers: .command)

                Divider()

                Button("Find in Files...") {
                    siteViewModel.isGlobalSearchPresented = true
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(siteViewModel.site == nil)
            }

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
                Toggle("Auto-Save", isOn: $settings.isAutoSaveEnabled)
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
            }

            // View menu - Layout modes
            CommandGroup(after: .toolbar) {
                Divider()

                Button("Editor Only") {
                    settings.layoutMode = .editor
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Preview Only") {
                    settings.layoutMode = .preview
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Split View") {
                    settings.layoutMode = .split
                }
                .keyboardShortcut("3", modifiers: .command)

                Divider()

                Button(settings.isInspectorVisible ? "Hide Inspector" : "Show Inspector") {
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

                Toggle("Highlight Current Line", isOn: $settings.highlightCurrentLine)
            }
        }

        // Preferences window (Cmd+,)
        Settings {
            PreferencesView()
        }
        
        Window("Server Logs",id: "server-logs") {
            ServerLogView()
        }
    }
}
