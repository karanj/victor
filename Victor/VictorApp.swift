import SwiftUI
import AppKit

// MARK: - Find Panel Helper

/// Helper to trigger NSTextView's native find panel from SwiftUI menu commands
/// `@MainActor`: both static funcs call `NSApp.sendAction` (WP3.5 Cluster 11).
@MainActor
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

// MARK: - Edit Menu Helper

/// Generalizes `FindPanelHelper`'s responder-chain dispatch for the system
/// Edit-menu submenus (Spelling and Grammar, Substitutions, Transformations,
/// Speech) re-added by victor-spl after `CommandGroup(replacing: .textEditing)`
/// dropped them. String-selector form deliberately used at call sites instead
/// of `#selector` - these are AppKit responder-chain actions (`showGuessPanel:`,
/// `uppercaseWord:`, etc.) implemented across NSText/NSTextView/NSResponder,
/// not methods this target declares, so there's no single owning type to
/// anchor a `#selector` expression to.
/// `@MainActor`: calls `NSApp.sendAction` (WP3.5 Cluster 11).
@MainActor
enum EditMenuHelper {
    static func send(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }
}

// MARK: - App Delegate for Quit Confirmation

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Reference to check for unsaved changes
    weak var siteViewModel: SiteViewModel?

    /// W3.1 (victor-doc): set by `VictorApp.onAppear` so folders dropped on
    /// the Dock icon, opened via Finder "Open With", or passed to
    /// `open -a Victor <folder>` route through the single existing window
    /// instead of AppKit's default document-window handling. This is the
    /// path that actually fires for Dock-icon drops (confirmed empirically -
    /// see victor-doc report); `onOpenURL` on the WindowGroup is kept as a
    /// defensive second path but is not reached once this delegate method is
    /// implemented, since AppKit only calls one open-URL handler per launch.
    var onOpenSiteFolders: (([URL]) -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable native window tabbing - app architecture is single-window
        // Enabling tabs causes freeze due to shared SiteViewModel state conflicts
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    /// Dock-icon folder drop, Finder "Open With ▸ Victor", and
    /// `open -a Victor <folder>` all deliver here as the 'odoc' Apple Event.
    func application(_ application: NSApplication, open urls: [URL]) {
        Logger.shared.info("application(_:open:) received \(urls.count) URL(s): \(urls.map(\.path))")
        onOpenSiteFolders?(urls)
    }

    // MARK: - Dock Menu (W2.4)

    /// Dock icon right-click menu: server toggle + recent sites.
    /// Plain AppKit (NSMenu/NSMenuItem) since there's no SwiftUI entry point
    /// for the Dock menu - target/action call back into `siteViewModel`,
    /// which this delegate already holds a weak reference to.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        guard let viewModel = siteViewModel else { return menu }

        if viewModel.site != nil {
            let serverTitle = viewModel.isHugoServerRunning ? "Stop Hugo Server" : "Start Hugo Server"
            let serverItem = NSMenuItem(title: serverTitle, action: #selector(dockToggleHugoServer), keyEquivalent: "")
            serverItem.target = self
            menu.addItem(serverItem)
        }

        let recentPaths = viewModel.recentSitePaths
        if !recentPaths.isEmpty {
            if !menu.items.isEmpty {
                menu.addItem(.separator())
            }
            for path in recentPaths {
                let item = NSMenuItem(
                    title: URL(fileURLWithPath: path).lastPathComponent,
                    action: #selector(dockOpenRecentSite(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = path
                menu.addItem(item)
            }
        }

        return menu
    }

    @objc private func dockToggleHugoServer() {
        Task { @MainActor [weak siteViewModel] in
            await siteViewModel?.toggleHugoServer()
        }
    }

    @objc private func dockOpenRecentSite(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        Task { @MainActor [weak siteViewModel] in
            await siteViewModel?.openRecentSite(path)
        }
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

// MARK: - Sharing Helper

/// Presents NSSharingServicePicker anchored to the key window.
/// Exists because ShareLink inside a CommandGroup silently does nothing on
/// macOS 14 (FB13281955); menu items call this instead.
@MainActor
enum SharingHelper {
    /// The picker must stay alive while its popover is on screen; a fire-and-
    /// forget local would deallocate before presentation completes.
    private static var activePicker: NSSharingServicePicker?

    static func share(items: [Any]) {
        guard let contentView = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: items)
        activePicker = picker
        picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
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
///
/// Equatable, keyed on `editorID` ONLY (keystroke-lag fix, part 2): this value
/// is published from editor-panel `body`s that re-evaluate on every keystroke,
/// constructing a fresh instance each time. Closures can't be compared, so
/// without Equatable SwiftUI must treat every publish as a change - invalidating
/// VictorApp's body (a `@FocusedValue` holder) and rebuilding the entire
/// `.commands` NSMenu tree per character typed. Comparing by the publishing
/// editor's identity is sound because the closures read live `@State`/
/// `@Observable` values at call time: two instances published for the same file
/// node are behaviorally interchangeable. Do NOT add per-keystroke state (e.g. a
/// dirty flag) to this struct or its equality - that reintroduces the storm.
/// Pinned by EditorActionsTests.
struct EditorActions: Equatable {
    /// Identity of the publishing editor - the file node's id. Drives Equatable.
    let editorID: UUID
    /// Apply Markdown formatting at the cursor/selection. `nil` when the
    /// focused editor doesn't support Markdown formatting.
    var formatting: ((MarkdownFormat) -> Void)?
    /// Present the shortcode picker. `nil` when not applicable.
    var showShortcodePicker: (() -> Void)?
    /// Save the focused document; returns whether the save succeeded.
    var save: () async -> Bool
    /// Reload the focused document from disk, discarding local edits.
    var revert: () async -> Void
    /// Whether the focused document currently has unsaved changes. Menu
    /// validation calls this - it must consult transition-guarded state
    /// (SiteViewModel.isFileModified), never per-keystroke @Observable state
    /// like EditorViewModel.hasUnsavedChanges (see keystroke-lag notes).
    var hasUnsavedChanges: () -> Bool

    static func == (lhs: EditorActions, rhs: EditorActions) -> Bool {
        lhs.editorID == rhs.editorID
    }
}

extension FocusedValues {
    /// `@Entry` (victor-mod grab-bag item 4) generates the `FocusedValueKey` type and
    /// getter/setter boilerplate the manual pattern above used to need - available on
    /// this project's toolchain (Xcode 26.3 / Swift 6.2), so this isn't gated.
    @Entry var editorActions: EditorActions?
}

@main
struct VictorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var siteViewModel = SiteViewModel()
    @FocusedValue(\.editorActions) private var editorActions
    @Environment(\.openWindow) private var openWindow

    // Editor preferences (shared with Preferences window via AppSettings)
    @Bindable private var settings = AppSettings.shared

    // Accessibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // File-menu confirmation dialogs. Attached to the window content (not
    // ContentView itself, which WP1.1 owns concurrently) so they present
    // against a real window instead of the menu bar's detached view context.
    @State private var isCloseSiteConfirmationPresented = false
    @State private var isRevertConfirmationPresented = false

    // W3.1 (victor-doc): folder awaiting load once the Close Site
    // confirmation above resolves. Set only when an incoming open request
    // (Dock drop / Open With / `open -a`) arrives while a site with unsaved
    // changes is already open.
    @State private var pendingOpenSiteURL: URL?

    // W3.1 (victor-doc): de-dupes duplicate delivery of the same open-folder
    // event. Empirically, `open -a Victor <folder>` can deliver through
    // *both* `onOpenURL` and the AppDelegate path, and `onOpenURL` alone has
    // been observed firing twice for a single invocation. Loading the same
    // site twice concurrently corrupts SiteViewModel's filteredNodes cache
    // (two racing `loadSite` calls thrash `_fileNodesVersion`) into a busy
    // re-render loop, so track the in-flight URL and ignore repeats. Set
    // synchronously (no `await` in between) so two back-to-back deliveries
    // in the same run-loop turn can't both pass the guard.
    @State private var siteURLLoadInFlight: URL?

    var body: some Scene {
        WindowGroup {
            ContentView(siteViewModel: siteViewModel)
                .frame(minWidth: AppConstants.Window.minWidth, minHeight: AppConstants.Window.minHeight)
                .onAppear {
                    // Wire up app delegate to view model for quit confirmation
                    appDelegate.siteViewModel = siteViewModel
                    // W3.1 (victor-doc): Dock drop / Open With route through
                    // the delegate (see AppDelegate.application(_:open:)).
                    appDelegate.onOpenSiteFolders = { urls in
                        // Single-window app: multi-selecting several folders
                        // and dropping them together can deliver N URLs in one
                        // call. Only the first can win; handling the rest
                        // would race loadSite against itself (see the
                        // siteURLLoadInFlight comment).
                        if let url = urls.first {
                            handleOpenSiteFolder(url)
                        }
                    }
                }
                // W3.1 (victor-doc): `open -a Victor ~/blog` and some Finder
                // open paths deliver here instead of the delegate. Both
                // paths funnel into the same single-window handler.
                .onOpenURL { url in
                    handleOpenSiteFolder(url)
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
                            await openPendingSiteIfNeeded()
                        }
                    }
                    Button("Close Without Saving", role: .destructive) {
                        siteViewModel.closeSite()
                        Task { await openPendingSiteIfNeeded() }
                    }
                    Button("Cancel", role: .cancel) {
                        // W3.1: an open request that triggered this dialog is abandoned on Cancel.
                        pendingOpenSiteURL = nil
                    }
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
                // W5.2 (victor-kbd): Cmd+Option+F stays here - it's the
                // platform-standard Find and Replace chord (Xcode, TextEdit).
                // The original W5.2 decision misattributed it to Xcode's
                // navigator filter (which is actually Cmd+Option+J, now used
                // by Search Files below) - corrected 2026-07-04.
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

                Divider()

                // Spelling and Grammar / Substitutions / Transformations / Speech
                // (victor-spl): these are the standard system submenus macOS
                // installs in this same `.textEditing` CommandGroup slot -
                // replacing the group for Find (above) silently dropped all
                // four, so they're rebuilt here via responder-chain dispatch
                // (EditMenuHelper) in standard Edit-menu order.
                Menu("Spelling and Grammar") {
                    Button("Show Spelling and Grammar") {
                        EditMenuHelper.send(Selector("showGuessPanel:"))
                    }
                    .keyboardShortcut(":", modifiers: .command)

                    Button("Check Document Now") {
                        EditMenuHelper.send(Selector("checkSpelling:"))
                    }
                    .keyboardShortcut(";", modifiers: .command)

                    Divider()

                    Toggle("Check Spelling While Typing", isOn: $settings.checkSpellingWhileTyping)
                    Toggle("Check Grammar With Spelling", isOn: $settings.checkGrammarWithSpelling)
                    Toggle("Correct Spelling Automatically", isOn: $settings.correctSpellingAutomatically)
                }

                Menu("Substitutions") {
                    Button("Show Substitutions") {
                        EditMenuHelper.send(Selector("orderFrontSubstitutionsPanel:"))
                    }

                    Divider()

                    // Smart Quotes/Dashes/Links are deliberately not exposed here:
                    // smart punctuation is forced off in EditorTextView (~line
                    // 467) because it corrupts markdown syntax, so there's no
                    // live setting for those items to toggle.
                    Toggle("Text Replacement", isOn: $settings.useTextReplacement)
                }

                Menu("Transformations") {
                    Button("Make Upper Case") {
                        EditMenuHelper.send(Selector("uppercaseWord:"))
                    }

                    Button("Make Lower Case") {
                        EditMenuHelper.send(Selector("lowercaseWord:"))
                    }

                    Button("Capitalize") {
                        EditMenuHelper.send(Selector("capitalizeWord:"))
                    }
                }

                Menu("Speech") {
                    Button("Start Speaking") {
                        EditMenuHelper.send(Selector("startSpeaking:"))
                    }

                    Button("Stop Speaking") {
                        EditMenuHelper.send(Selector("stopSpeaking:"))
                    }
                }
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

                Menu("Open Recent") {
                    ForEach(siteViewModel.recentSitePaths, id: \.self) { path in
                        Button(URL(fileURLWithPath: path).lastPathComponent) {
                            Task { await siteViewModel.openRecentSite(path) }
                        }
                    }

                    if !siteViewModel.recentSitePaths.isEmpty {
                        Divider()

                        Button("Clear Menu") {
                            siteViewModel.clearRecentSites()
                        }
                    }
                }
                .disabled(siteViewModel.recentSitePaths.isEmpty)
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

                Divider()

                // W3.6: share the selected file; second item exposes the local
                // preview URL while the Hugo server is running.
                // Deliberately NOT ShareLink: inside a CommandGroup it renders
                // but does nothing on macOS 14 (Apple FB13281955), so these go
                // through NSSharingServicePicker anchored to the key window.
                Button("Share…") {
                    if let url = siteViewModel.selectedNode?.url {
                        SharingHelper.share(items: [url])
                    }
                }
                .disabled(siteViewModel.selectedNode == nil)

                if let serverURL = siteViewModel.hugoServerURL, siteViewModel.isHugoServerRunning {
                    Button("Share Preview URL") {
                        SharingHelper.share(items: [serverURL])
                    }
                }
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
                // W5.2 (victor-kbd, corrected 2026-07-04): Cmd+Option+J is
                // Xcode's actual filter-in-navigator chord - the original
                // decision said Cmd+Option+F, but that's the platform-standard
                // Find and Replace binding (kept there). Cmd+P is deliberately
                // NOT kept as a second binding here - it's reserved for Quick
                // Open (victor-qop) once that ships. A SwiftUI Button can only
                // own one `.keyboardShortcut`, so there's a window between
                // this ticket and victor-qop shipping where Cmd+P does
                // nothing; that's accepted, not a bug.
                .keyboardShortcut("j", modifiers: [.command, .option])
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

                // W5.1 (victor-kbd): Xcode-convention pane traversal (sidebar
                // <-> editor <-> inspector). Distinct from the Go menu's
                // Cmd+Control+Left/Right (back/forward navigation history,
                // below) - Option vs. Control keeps the two from colliding.
                // `paneFocusDirection` is an observable trigger consumed by
                // `ContentView`'s `@FocusState`, since that state lives in a
                // different view than this scene-level menu.
                Button("Focus Previous Pane") {
                    siteViewModel.paneFocusDirection = .previous
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])

                Button("Focus Next Pane") {
                    siteViewModel.paneFocusDirection = .next
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])

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

            // Go menu (W2.2) - file navigation history + jumps to top-level Hugo folders
            CommandMenu("Go") {
                Button("Back") {
                    siteViewModel.navigateBack()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .control])
                .disabled(!siteViewModel.canNavigateBack)

                Button("Forward") {
                    siteViewModel.navigateForward()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .control])
                .disabled(!siteViewModel.canNavigateForward)

                Divider()

                goToFolderButton(title: "Go to content/", role: .content)
                goToFolderButton(title: "Go to static/", role: .staticFiles)
                goToFolderButton(title: "Go to layouts/", role: .layouts)
                goToFolderButton(title: "Go to data/", role: .data)
            }

            // Help menu (W5.2) - keyboard shortcut reference
            CommandGroup(after: .help) {
                Button("Keyboard Shortcuts") {
                    openWindow(id: "shortcuts")
                }
            }
        }

        // Preferences window (Cmd+,)
        Settings {
            PreferencesView()
        }
        
        Window("Server Logs",id: "server-logs") {
            ServerLogView()
        }

        // W5.2 (victor-kbd): Help > Keyboard Shortcuts. A doc file is the
        // wrong UX for end users, so this is a small native window built
        // from a static table rather than a link out to
        // Docs/MAC-POLISH-DESIGN.md (which stays the source of truth the
        // table here is transcribed from).
        Window("Keyboard Shortcuts", id: "shortcuts") {
            KeyboardShortcutsView()
        }
        .defaultSize(width: 560, height: 620)
    }

    /// W3.1 (victor-doc): route an incoming site-folder URL (Dock drop,
    /// Finder "Open With", or `open -a Victor <folder>`) through the same
    /// single-window load path as File > Open Hugo Site, reusing the Close
    /// Site confirmation when another site is open with unsaved changes.
    /// Never opens a second window - the confirmation dialogs above are
    /// App-scoped state shared across the (single) window, per victor-doc's
    /// P2 note.
    private func handleOpenSiteFolder(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            siteViewModel.errorMessage = "\"\(url.lastPathComponent)\" is not a folder. Choose a Hugo site folder to open it in Victor."
            return
        }

        // Duplicate delivery of the same open request (see
        // `siteURLLoadInFlight` doc comment) - ignore the repeat. Set
        // synchronously (no `await` before this point) so two back-to-back
        // deliveries in the same run-loop turn can't both pass the guard.
        guard siteURLLoadInFlight != url else { return }
        siteURLLoadInFlight = url

        Task {
            // Cold launch kicks off an auto-restore of the last saved site
            // (SiteViewModel.init -> loadSavedSite). Wait for that to settle
            // first so it can't race this request's `loadSite` call - see
            // `initialSiteRestoreTask`'s doc comment for why that matters.
            await siteViewModel.initialSiteRestoreTask?.value

            guard !siteViewModel.hasUnsavedChanges else {
                pendingOpenSiteURL = url
                isCloseSiteConfirmationPresented = true
                siteURLLoadInFlight = nil
                return
            }

            await siteViewModel.loadSite(from: url)
            if siteURLLoadInFlight == url {
                siteURLLoadInFlight = nil
            }
        }
    }

    /// Loads `pendingOpenSiteURL` (set by `handleOpenSiteFolder` when the
    /// Close Site confirmation had to run first) once the previous site has
    /// been closed. `loadSite` performs the Hugo-site validation itself and
    /// sets `errorMessage` if `url` isn't one.
    private func openPendingSiteIfNeeded() async {
        guard let url = pendingOpenSiteURL else { return }
        pendingOpenSiteURL = nil

        guard siteURLLoadInFlight != url else { return }
        siteURLLoadInFlight = url
        await siteViewModel.loadSite(from: url)
        if siteURLLoadInFlight == url {
            siteURLLoadInFlight = nil
        }
    }

    /// A Go menu "Go to <role>/" item: selects and reveals the site's
    /// top-level folder for `role`, disabled when the loaded site has none.
    @ViewBuilder
    private func goToFolderButton(title: String, role: HugoRole) -> some View {
        Button(title) {
            if let folder = siteViewModel.topLevelFolder(for: role) {
                siteViewModel.selectAndRevealNode(folder)
            }
        }
        .disabled(siteViewModel.topLevelFolder(for: role) == nil)
    }
}
