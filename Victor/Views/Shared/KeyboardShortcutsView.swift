import SwiftUI

/// A single row in the Help > Keyboard Shortcuts reference window's table.
/// `menu` names the menu the shortcut lives under (mirrors the app's menu
/// structure so the flattened table still reads like "where do I find this").
private struct ShortcutEntry: Identifiable {
    let id = UUID()
    let shortcut: String
    let action: String
    let menu: String
}

/// A named group of shortcuts used only to build `ShortcutEntry.menu` below -
/// keeps the source list grouped/readable without needing `Table`'s
/// (currently macOS-only, selection-oriented) `Section` support.
private struct ShortcutSection {
    let title: String
    let entries: [(shortcut: String, action: String)]

    var rows: [ShortcutEntry] {
        entries.map { ShortcutEntry(shortcut: $0.shortcut, action: $0.action, menu: title) }
    }
}

/// W5.2 (victor-kbd): Help > Keyboard Shortcuts window (`Window(id: "shortcuts")`
/// in VictorApp.swift). A doc file is the wrong UX for end users, so this is a
/// small native window built from a static table - the source of truth for
/// the *content* is the "Appendix: Keyboard shortcuts" table in
/// Docs/MAC-POLISH-DESIGN.md; keep the two in sync when shortcuts change.
struct KeyboardShortcutsView: View {
    private let sections: [ShortcutSection] = [
        ShortcutSection(title: "Edit — Find", entries: [
            ("⌘F", "Find…"),
            ("⌘G", "Find Next"),
            ("⇧⌘G", "Find Previous"),
            ("⌘E", "Use Selection for Find"),
            ("⌥⌘F", "Find and Replace…"),
            ("⇧⌘F", "Find in Files…"),
        ]),
        ShortcutSection(title: "File", entries: [
            ("⌘N", "New Post…"),
            ("⇧⌘N", "New Folder"),
            ("⌘O", "Open Hugo Site…"),
            ("⇧⌘W", "Close Site"),
            ("⌘S", "Save"),
            ("⌥⌘S", "Save All"),
            ("⌥⌘R", "Reveal in Finder"),
        ]),
        ShortcutSection(title: "Format", entries: [
            ("⌘B", "Bold"),
            ("⌘I", "Italic"),
            ("⌘K", "Insert Link"),
            ("⇧⌘I", "Insert Image"),
            ("⇧⌘K", "Insert Shortcode…"),
            ("⌘'", "Block Quote"),
        ]),
        ShortcutSection(title: "View", entries: [
            ("⌃⌘S", "Toggle Sidebar"),
            ("⌥⌘J", "Search Files (sidebar filter)"),
            ("⌘1", "Editor Only"),
            ("⌘2", "Preview Only"),
            ("⌘3", "Split View"),
            ("⌥⌘←", "Focus Previous Pane"),
            ("⌥⌘→", "Focus Next Pane"),
            ("⌥⌘I", "Show/Hide Inspector"),
            ("⌃⌘F", "Enter/Exit Focus Mode"),
        ]),
        ShortcutSection(title: "Go", entries: [
            ("⌃⌘←", "Back"),
            ("⌃⌘→", "Forward"),
        ]),
        ShortcutSection(title: "Dialogs & panels", entries: [
            ("Esc", "Cancel / dismiss the current dialog"),
            ("⏎", "Confirm the current dialog's default button"),
            ("Space", "Toggle Quick Look preview (Asset Browser)"),
        ]),
    ]

    private var rows: [ShortcutEntry] {
        sections.flatMap(\.rows)
    }

    var body: some View {
        Table(rows) {
            TableColumn("Shortcut") { row in
                Text(row.shortcut)
                    .font(.system(.body, design: .monospaced))
            }
            .width(100)
            TableColumn("Action") { row in
                Text(row.action)
            }
            TableColumn("Menu") { row in
                Text(row.menu)
                    .foregroundStyle(.secondary)
            }
            .width(140)
        }
        .frame(minWidth: 520, minHeight: 420)
        .navigationTitle("Keyboard Shortcuts")
    }
}

#Preview {
    KeyboardShortcutsView()
}
