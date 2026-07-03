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

/// Actions the currently focused editor panel exposes to the menu bar.
///
/// Replaces the earlier two-key focused-value pattern (`editorFormatting`,
/// `showShortcodePicker`) so that adding menu-driven editor actions (Save,
/// Revert) doesn't mean growing more ad-hoc `FocusedValueKey`s (W2.3).
///
/// `formatting` and `showShortcodePicker` are optional because not every
/// editor supports Markdown formatting or shortcodes (e.g. TextEditorPanel
/// for plain-text files) - the Format menu simply disables those items when
/// the focused editor doesn't provide them.
struct EditorActions {
    /// Apply Markdown formatting at the cursor/selection. `nil` when the
    /// focused editor doesn't support Markdown formatting.
    var formatting: ((MarkdownFormat) -> Void)?
    /// Present the shortcode picker. `nil` when not applicable.
    var showShortcodePicker: (() -> Void)?
    /// Save the focused document; returns whether the save succeeded.
    var save: () async -> Bool
    /// Reload the focused document from disk, discarding local edits.
    var revert: () async -> Void
    /// Whether the focused document currently has unsaved changes.
    var hasUnsavedChanges: () -> Bool
}

struct EditorActionsKey: FocusedValueKey {
    typealias Value = EditorActions
}

extension FocusedValues {
    var editorActions: EditorActionsKey.Value? {
        get { self[EditorActionsKey.self] }
        set { self[EditorActionsKey.self] = newValue }
    }
}

@main
struct VictorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var siteViewModel = SiteViewModel()
    @FocusedValue(\.editorActions) private var editorActions

    // Editor preferences (shared with Preferences window via AppSettings)
    @Bindable private var settings = AppSettings.shared

    // Accessibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // File-menu confirmation dialogs. Attached to the window content (not
    // ContentView itself, which WP1.1 owns concurrently) so they present
    // against a real window instead of the menu bar's detached view context.
    @State private var isCloseSiteConfirmationPresented = false
    @State private var isRevertConfirmationPresented = false

    var body: some Scene {
        WindowGroup {
            ContentView(siteViewModel: siteViewModel)
                .frame(minWidth: AppConstants.Window.minWidth, minHeight: AppConstants.Window.minHeight)
                .onAppear {
                    // Wire up app delegate to view model for quit confirmation
                    appDelegate.siteViewModel = siteViewModel
                }
                .sheet(isPresented: $siteViewModel.isNewContentPresented) {
                    if let siteURL = siteViewModel.site?.rootURL,
                       let targetDirectory = siteViewModel.newContentTargetFolder?.url {
                        NewContentView(
                            siteURL: siteURL,
                            targetDirectory: targetDirectory,
                            onCreated: { fileURL in
                                Task {
                                    await siteViewModel.reloadSite()
                                    if let newNode = siteViewModel.findNode(url: fileURL) {
                                        siteViewModel.selectNode(newNode)
                                    }
                                }
                            }
                        )
                    }
                }
                .confirmationDialog(
                    "Close Site?",
                    isPresented: $isCloseSiteConfirmationPresented,
                    titleVisibility: .visible
                ) {
                    Button("Save All and Close") {
                        Task {
                            await siteViewModel.saveAllModifiedFiles()
                            siteViewModel.closeSite()
                        }
                    }
                    Button("Close Without Saving", role: .destructive) {
                        siteViewModel.closeSite()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This site has unsaved changes. Choose whether to save them before closing.")
                }
                .confirmationDialog(
                    "Revert to the last saved version?",
                    isPresented: $isRevertConfirmationPresented,
                    titleVisibility: .visible
                ) {
                    Button("Revert", role: .destructive) {
                        Task { await editorActions?.revert() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Your changes since the last save will be lost.")
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
                Button("New Post...") {
                    siteViewModel.isNewContentPresented = true
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(siteViewModel.site == nil)

                Button("New Folder") {
                    if let target = siteViewModel.newFolderTargetFolder {
                        Task { await siteViewModel.createFolder(in: target) }
                    }
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(siteViewModel.site == nil || siteViewModel.newFolderTargetFolder == nil)

                Divider()

                Button("Open Hugo Site...") {
                    Task {
                        await siteViewModel.openSiteFolder()
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Divider()

                Button("Close Site") {
                    if siteViewModel.hasUnsavedChanges {
                        isCloseSiteConfirmationPresented = true
                    } else {
                        siteViewModel.closeSite()
                    }
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(siteViewModel.site == nil)
            }

            CommandGroup(after: .saveItem) {
                Toggle("Auto-Save", isOn: $settings.isAutoSaveEnabled)

                Divider()

                Button("Save") {
                    Task { _ = await editorActions?.save() }
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(editorActions == nil || !(editorActions?.hasUnsavedChanges() ?? false))

                Button("Save All") {
                    Task { await siteViewModel.saveAllModifiedFiles() }
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(!siteViewModel.hasUnsavedChanges)

                Button("Revert to Saved") {
                    isRevertConfirmationPresented = true
                }
                .disabled(editorActions == nil || !(editorActions?.hasUnsavedChanges() ?? false))

                Divider()

                Button("Reveal in Finder") {
                    if let node = siteViewModel.selectedNode {
                        siteViewModel.revealInFinder(node: node)
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(siteViewModel.selectedNode == nil)
            }

            // Format menu - Text formatting
            CommandGroup(after: .textFormatting) {
                Button("Bold") {
                    editorActions?.formatting?(.bold)
                }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(editorActions?.formatting == nil)

                Button("Italic") {
                    editorActions?.formatting?(.italic)
                }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(editorActions?.formatting == nil)

                Divider()

                Button("Insert Link") {
                    editorActions?.formatting?(.link)
                }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(editorActions?.formatting == nil)

                Button("Insert Image") {
                    editorActions?.formatting?(.image)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(editorActions?.formatting == nil)

                Button("Insert Shortcode...") {
                    editorActions?.showShortcodePicker?()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(editorActions?.showShortcodePicker == nil)

                Button("Block Quote") {
                    editorActions?.formatting?(.blockquote)
                }
                .keyboardShortcut("'", modifiers: .command)
                .disabled(editorActions?.formatting == nil)
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
