import SwiftUI
import AppKit

/// W5.1 (victor-kbd): the three top-level panes keyboard focus can land on,
/// left-to-right on screen. This order is what Cmd+Option+Right traverses
/// forward through (Cmd+Option+Left reverses it) - see `ContentView.focusedPane`.
private enum AppPane: Hashable {
    case sidebar
    case editor
    case inspector
}

struct ContentView: View {
    @Bindable var siteViewModel: SiteViewModel
    @Bindable private var settings = AppSettings.shared
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var window: NSWindow?

    // W5.1 (victor-kbd): which of the three panes currently holds keyboard
    // focus. Moved by Tab/arrow-key traversal (via `.focusSection()`/
    // `.focusable()` below) and programmatically by the View menu's
    // Cmd+Option+Left/Right commands, relayed through
    // `siteViewModel.paneFocusDirection` since those commands live in
    // `VictorApp`'s scene-level `.commands`, which can't reach a
    // `@FocusState` declared here directly. This is the same
    // observable-trigger pattern `shouldFocusSearch` already uses for
    // Cmd+P/Cmd+Option+F - preferred over juggling `NSWindow.firstResponder`
    // through `WindowAccessor` because there's no single stable NSView per
    // pane to target (the editor pane's content varies by file type), while
    // every pane already gets a real SwiftUI focus identity for free here.
    @FocusState private var focusedPane: AppPane?

    // Accessibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Titlebar

    /// URL driving the titlebar proxy icon: the selected file, falling back to the
    /// site root when nothing is selected. Nil when no site is open (no proxy icon).
    private var navigationDocumentURL: URL? {
        siteViewModel.selectedNode?.url ?? siteViewModel.site?.rootURL
    }

    /// Window title: selected file's display name, falling back to the site's
    /// display name, then "Victor" when no site is open.
    private var windowTitle: String {
        siteViewModel.selectedNode?.name ?? siteViewModel.site?.displayName ?? "Victor"
    }

    /// Window subtitle: the site's display name, shown only when a file is selected
    /// (matches the "file.md — Site Name" convention).
    private var windowSubtitle: String {
        guard siteViewModel.selectedNode != nil else { return "" }
        return siteViewModel.site?.displayName ?? ""
    }

    var body: some View {
        ZStack {
            mainContent

            // Focus Mode overlay
            if siteViewModel.isFocusModeActive,
               let selectedNode = siteViewModel.selectedNode,
               selectedNode.contentFile != nil {
                FocusModeView(
                    text: $siteViewModel.currentEditingContent,
                    siteViewModel: siteViewModel,
                    fileName: selectedNode.name
                )
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: AppConstants.Animation.slow), value: siteViewModel.isFocusModeActive)
        .sheet(isPresented: $siteViewModel.isGlobalSearchPresented) {
            GlobalSearchView(siteViewModel: siteViewModel)
        }
        .onAppear {
            siteViewModel.setupHugoServerObservers()
        }
        .background(
            WindowAccessor { newWindow in
                window = newWindow
                window?.isDocumentEdited = siteViewModel.hasUnsavedChanges
            }
        )
        .onChange(of: siteViewModel.hasUnsavedChanges) { _, newValue in
            window?.isDocumentEdited = newValue
        }
        .onChange(of: siteViewModel.paneFocusDirection) { _, newDirection in
            guard let newDirection else { return }
            movePaneFocus(newDirection)
            siteViewModel.paneFocusDirection = nil
        }
    }

    // MARK: - Pane Focus Traversal (W5.1)

    /// Panes currently eligible for focus, left-to-right on screen. Inspector
    /// drops out when hidden so Cmd+Option+Right/Left never "focuses" a pane
    /// that isn't there.
    private var availablePanes: [AppPane] {
        var panes: [AppPane] = [.sidebar, .editor]
        if settings.isInspectorVisible {
            panes.append(.inspector)
        }
        return panes
    }

    /// Moves `focusedPane` to the next/previous pane in `availablePanes`,
    /// wrapping around at either end. Called both by the Cmd+Option+Left/Right
    /// menu commands (via the `paneFocusDirection` trigger above) and could be
    /// invoked directly in tests.
    private func movePaneFocus(_ direction: PaneFocusDirection) {
        let panes = availablePanes
        guard !panes.isEmpty else { return }
        guard let current = focusedPane, let currentIndex = panes.firstIndex(of: current) else {
            focusedPane = direction == .next ? panes.first : panes.last
            return
        }
        let count = panes.count
        switch direction {
        case .next:
            focusedPane = panes[(currentIndex + 1) % count]
        case .previous:
            focusedPane = panes[(currentIndex - 1 + count) % count]
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        // navigationDocument requires a non-optional URL; skip the modifier
        // entirely when no site is open rather than passing a placeholder URL.
        if let documentURL = navigationDocumentURL {
            navigationSplitView
                .navigationDocument(documentURL)
        } else {
            navigationSplitView
        }
    }

    private var navigationSplitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar - File navigation
            SidebarView(siteViewModel: siteViewModel)
                .navigationSplitViewColumnWidth(
                    min: AppConstants.Sidebar.minWidth,
                    ideal: AppConstants.Sidebar.idealWidth,
                    max: AppConstants.Sidebar.maxWidth
                )
                // W5.1 (victor-kbd): pane focus section - see `focusedPane` doc comment.
                .focusable()
                .focusSection()
                .focused($focusedPane, equals: .sidebar)
        } detail: {
            // Main content area with optional inspector
            HSplitView {
                // Main content area with tab-based layout
                VStack(spacing: 0) {
                    // Tab bar only shown for content files (markdown with frontmatter)
                    if siteViewModel.selectedNode?.contentFile != nil {
                        TabBarView(viewModel: siteViewModel)
                    }

                    // Content based on selected layout mode
                    if let selectedNode = siteViewModel.selectedNode {
                        layoutContent(for: selectedNode)
                            .id(selectedNode.id)  // Force view recreation on file switch
                            .transition(.opacity.animation(.easeInOut(duration: reduceMotion ? 0 : AppConstants.Animation.fast)))
                            .animation(reduceMotion ? nil : .easeInOut(duration: AppConstants.Animation.standard), value: settings.layoutMode)
                    } else {
                        noFileSelectedView
                            .transition(.opacity.animation(.easeInOut(duration: reduceMotion ? 0 : AppConstants.Animation.fast)))
                    }
                }
                .frame(minWidth: AppConstants.Content.minWidth)
                // W5.1 (victor-kbd): pane focus section - see `focusedPane` doc comment.
                .focusable()
                .focusSection()
                .focused($focusedPane, equals: .editor)

                // Inspector panel (right side)
                if settings.isInspectorVisible {
                    InspectorPanel(
                        contentFile: siteViewModel.selectedNode?.contentFile,
                        fileNode: siteViewModel.selectedNode,
                        siteViewModel: siteViewModel
                    )
                    .transition(.move(edge: .trailing))
                    .focusable()
                    .focusSection()
                    .focused($focusedPane, equals: .inspector)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: AppConstants.Animation.standard), value: settings.isInspectorVisible)
        }
        .navigationTitle(windowTitle)
        .navigationSubtitle(windowSubtitle)
        // Customizable toolbar (W1.3). Item *identity* (the ToolbarItem/id pair) is
        // always emitted every render; only the item's *content* is conditional
        // (real view vs. EmptyView). This is deliberate: toggling whether a
        // ToolbarItem with a given id is present at all (wrapping the ToolbarItem
        // itself in `if`) is what causes toolbar(id:)'s placement persistence to
        // reset/duplicate across launches. Keeping the id stable and only hiding
        // content works around that. All three items are core (situational, not
        // opt-in) so all default to visible; none is rare/destructive enough to
        // warrant `showsByDefault: false`.
        .toolbar(id: "com.victor.mainToolbar") {
            // Note: NavigationSplitView automatically provides a sidebar toggle button
            // so we don't need to add our own
            //
            // CRASH FIX (2026-07-05): item CONTENT must be as stable as item
            // identity. `if condition { View }` with no else makes AppKit
            // remove/re-insert the underlying NSToolbarItem whenever the
            // condition flips (twice per file switch via isLoadingFile and
            // contentFile), which both thrashes toolbar layout and races the
            // customization controller's item array - crashing with
            // "index>=0 && index<[_currentItems count]". Items are therefore
            // always present; state is expressed via .disabled/.opacity only
            // (also the HIG-correct behavior: toolbar items grey out, they
            // don't vanish).

            ToolbarItem(id: "serverControls", placement: .automatic, showsByDefault: true) {
                ServerControlView(siteViewModel: siteViewModel)
                    .disabled(siteViewModel.site == nil)
            }

            ToolbarItem(id: "loadingIndicator", placement: .automatic, showsByDefault: true) {
                ProgressView()
                    .controlSize(.small)
                    .opacity(siteViewModel.isLoading || siteViewModel.isLoadingFile ? 1 : 0)
                    .help(siteViewModel.isLoadingFile ? "Loading file..." : "Loading site...")
            }

            // Inspector toggle: enabled only for markdown content files
            // (Assets have their own built-in detail panel)
            ToolbarItem(id: "inspectorToggle", placement: .primaryAction, showsByDefault: true) {
                Button {
                    if reduceMotion {
                        siteViewModel.toggleInspector()
                    } else {
                        withAnimation(.easeInOut(duration: AppConstants.Animation.standard)) {
                            siteViewModel.toggleInspector()
                        }
                    }
                } label: {
                    Label(
                        settings.isInspectorVisible ? "Hide Inspector" : "Show Inspector",
                        systemImage: "sidebar.right"
                    )
                }
                .help("Toggle Inspector (⌥⌘I)")
                .disabled(siteViewModel.selectedNode?.contentFile == nil)
            }
        }
        .alert("Error", isPresented: Binding(
            get: { siteViewModel.errorMessage != nil },
            set: { if !$0 { siteViewModel.errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            if let errorMessage = siteViewModel.errorMessage {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Layout Content

    /// Determines the effective layout mode based on file type
    /// Non-markdown files always use editor-only mode (no preview)
    private var effectiveLayoutMode: EditorLayoutMode {
        guard let node = siteViewModel.selectedNode else {
            return settings.layoutMode
        }
        // Only markdown files with content get preview
        if node.fileType != .markdown || node.contentFile == nil {
            return .editor
        }
        return settings.layoutMode
    }

    /// Returns the appropriate view based on the current layout mode
    @ViewBuilder
    private func layoutContent(for node: FileNode) -> some View {
        switch effectiveLayoutMode {
        case .editor:
            // Full-width viewer/editor only
            FileViewerRouter(node: node, siteViewModel: siteViewModel)

        case .preview:
            // Full-width preview only (markdown only)
            if node.contentFile != nil {
                previewPanel(for: node)
            } else {
                FileViewerRouter(node: node, siteViewModel: siteViewModel)
            }

        case .split:
            // Side-by-side editor and preview (markdown only)
            if node.contentFile != nil {
                HSplitView {
                    FileViewerRouter(node: node, siteViewModel: siteViewModel)
                        .frame(minWidth: AppConstants.Content.panelMinWidth)

                    previewPanel(for: node)
                        .frame(minWidth: AppConstants.Content.panelMinWidth)
                }
            } else {
                FileViewerRouter(node: node, siteViewModel: siteViewModel)
            }
        }
    }

    /// Returns the appropriate preview panel based on the user's preview choice.
    /// Routed on `useLivePreview` ALONE - deliberately not `&&
    /// isHugoServerRunning`: with the server stopped, LivePreviewPanel shows its
    /// "server not running" placeholder with a Start Server button. The old
    /// double gate made that placeholder unreachable, so the live-preview
    /// feature was invisible until the user found Start in the window toolbar.
    @ViewBuilder
    private func previewPanel(for node: FileNode) -> some View {
        if siteViewModel.useLivePreview {
            // Use live preview from Hugo server
            LivePreviewPanel(
                siteViewModel: siteViewModel,
                currentFilePath: relativeFilePath(for: node),
                permalinkResolver: permalinkResolver(for: siteViewModel),
                currentDate: node.contentFile?.frontmatter?.date,
                currentSlug: node.contentFile?.frontmatter?.slug
            )
        } else if let contentFile = node.contentFile {
            // Use markdown preview
            PreviewPanel(contentFile: contentFile, siteViewModel: siteViewModel)
        }
    }

    /// Build a PermalinkResolver from the current Hugo config
    private func permalinkResolver(for viewModel: SiteViewModel) -> PermalinkResolver {
        if let config = viewModel.hugoConfig {
            let permalinks = PermalinkResolver.parsePermalinks(from: config)
            return PermalinkResolver(permalinks: permalinks)
        }
        return PermalinkResolver(permalinks: [:])
    }

    /// Get relative file path from site root
    private func relativeFilePath(for node: FileNode) -> String? {
        guard let siteRoot = siteViewModel.site?.rootURL else { return nil }
        let nodePath = node.url.path
        let rootPath = siteRoot.path
        guard nodePath.hasPrefix(rootPath) else { return nil }
        var relativePath = String(nodePath.dropFirst(rootPath.count))
        if relativePath.hasPrefix("/") {
            relativePath = String(relativePath.dropFirst())
        }
        return relativePath
    }

    // MARK: - Empty States

    /// View shown when no file is selected
    private var noFileSelectedView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: "doc.text")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)

            // Title and description
            VStack(spacing: 8) {
                Text("Select a File")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Choose a markdown file from the sidebar to start editing")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Helpful hints
            VStack(alignment: .leading, spacing: 12) {
                KeyboardHintRow(keys: "⌥⌘F", description: "Search files")
                KeyboardHintRow(keys: "⌘1", description: "Editor only")
                KeyboardHintRow(keys: "⌘2", description: "Preview only")
                KeyboardHintRow(keys: "⌘3", description: "Split view")
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

// MARK: - Keyboard Hint Row

struct KeyboardHintRow: View {
    let keys: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
                .frame(minWidth: 50)

            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView(siteViewModel: SiteViewModel())
}
