import SwiftUI

// MARK: - Focused Values for Editor Commands

struct EditorFormattingKey: FocusedValueKey {
    typealias Value = (MarkdownFormat) -> Void
}

extension FocusedValues {
    var editorFormatting: EditorFormattingKey.Value? {
        get { self[EditorFormattingKey.self] }
        set { self[EditorFormattingKey.self] = newValue }
    }
}

@main
struct VictorApp: App {
    @State private var siteViewModel = SiteViewModel()
    @FocusedValue(\.editorFormatting) private var editorFormatting

    // Editor preferences (using @AppStorage for sync with Preferences window)
    @AppStorage("highlightCurrentLine") private var highlightCurrentLine = true
    @AppStorage("isAutoSaveEnabled") private var isAutoSaveEnabled = true

    // Accessibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some Scene {
        WindowGroup {
            ContentView(siteViewModel: siteViewModel)
                .frame(minWidth: 1000, minHeight: 600)
        }
        .commands {
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

                Button("Block Quote") {
                    editorFormatting?(.blockquote)
                }
                .keyboardShortcut("'", modifiers: .command)
                .disabled(editorFormatting == nil)
            }

            // View menu - Search and Navigation
            CommandGroup(after: .sidebar) {
                // Quick Open disabled temporarily - needs keyboard navigation fix
                // Button("Quick Open...") {
                //     siteViewModel.toggleQuickOpen()
                // }
                // .keyboardShortcut("p", modifiers: .command)
                // .disabled(siteViewModel.site == nil)

                Button("Focus Search") {
                    siteViewModel.shouldFocusSearch = true
                }
                .keyboardShortcut("f", modifiers: .command)
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
