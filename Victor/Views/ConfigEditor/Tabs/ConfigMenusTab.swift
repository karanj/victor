import SwiftUI

/// Menus tab for Hugo configuration editor — site-level menus (`[menus]` /
/// `[menu]` in the config file), not to be confused with the per-page
/// frontmatter `MenusTab.swift` (unrelated data model: `Frontmatter.menus:
/// [MenuEntry]`). Interaction patterns (draft-commit text fields, add/delete
/// forms) are adapted from that file and from `ConfigContentTab`'s
/// `PermalinkRowView`, but this tab is self-contained.
///
/// CONFIG-SCHEMA-SPEC §3.4. Every mutation funnels through
/// `applyMenuMutation`, the single write path: mutate `config.menus` →
/// `config.commitMenus()` (writes the store under the preserved
/// `menuKeySpelling`) → the `configCommitAction` environment action
/// (`HugoConfig.syncRawContentFromStructuredData()`, same environment key
/// every other tab's `ConfigFieldView` commits through).
struct ConfigMenusTab: View {
    @Bindable var config: HugoConfig

    @Environment(\.configCommitAction) private var commit

    @State private var showAddMenu = false
    @State private var newMenuName = ""

    private var sortedMenuNames: [String] {
        config.menus.keys.sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            if config.menus.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(sortedMenuNames, id: \.self) { menuName in
                        menuSection(for: menuName)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            Divider()
            footer
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet.indent")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text("No menus defined")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Menus power your site's navigation. Add a menu (e.g. \"main\" or \"footer\") to get started.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
    }

    // MARK: - Footer (add menu)

    @ViewBuilder
    private var footer: some View {
        if showAddMenu {
            addMenuForm
        } else {
            Button {
                showAddMenu = true
            } label: {
                Label("Add Menu", systemImage: "plus.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .padding()
        }
    }

    private var addMenuForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Menu")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 8) {
                ForEach(["main", "footer"], id: \.self) { suggestion in
                    Button(suggestion.capitalized) {
                        addMenu(name: suggestion)
                    }
                    .buttonStyle(.bordered)
                    .disabled(config.menus[suggestion] != nil)
                }

                TextField("Custom menu name", text: $newMenuName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .onSubmit { addMenu(name: newMenuName) }

                Button("Add") { addMenu(name: newMenuName) }
                    .disabled(!canAddMenu)

                Button("Cancel") {
                    showAddMenu = false
                    newMenuName = ""
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    private var canAddMenu: Bool {
        let trimmed = newMenuName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !trimmed.isEmpty && config.menus[trimmed] == nil
    }

    // MARK: - Per-menu section

    @ViewBuilder
    private func menuSection(for menuName: String) -> some View {
        let items = sortedItems(in: menuName)

        Section {
            ForEach(items) { item in
                ConfigMenuItemRow(
                    item: item,
                    siblingIdentifiers: siblingIdentifiers(for: item, in: items),
                    onUpdate: { updated in updateItem(updated, in: menuName) },
                    onDelete: { deleteItem(item, from: menuName) }
                )
            }
            .onMove { source, destination in
                moveItems(in: menuName, from: source, to: destination)
            }

            Button {
                addItem(to: menuName)
            } label: {
                Label("Add Item", systemImage: "plus.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        } header: {
            HStack {
                Text(menuName.capitalized)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(role: .destructive) {
                    deleteMenu(menuName)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete \(menuName) menu")
                .accessibilityLabel("Delete \(menuName) Menu")
            }
        }
    }

    private func sortedItems(in menuName: String) -> [HugoMenuItem] {
        (config.menus[menuName] ?? []).sorted { $0.weight < $1.weight }
    }

    /// Other items' identifiers in the same menu — a valid `parent` value
    /// must reference one of these. Excludes `item` itself and any sibling
    /// without an identifier (items without identifiers can't be parents).
    private func siblingIdentifiers(for item: HugoMenuItem, in items: [HugoMenuItem]) -> [String] {
        items
            .filter { $0.id != item.id }
            .compactMap { $0.identifier }
            .filter { !$0.isEmpty }
            .sorted()
    }

    // MARK: - Single write path

    /// The one place `config.menus` is mutated. Every call site here does:
    /// mutate → `commitMenus()` (writes the store under `menuKeySpelling`) →
    /// `configCommitAction` (`syncRawContentFromStructuredData`, keeping
    /// `hasUnsavedChanges`/the toolbar save button correct) — the same
    /// triple every other Config Editor tab's leaf rows perform through
    /// `ConfigFieldView`, kept in one helper so menus can't drift onto a
    /// second write path.
    private func applyMenuMutation(_ mutate: (inout [String: [HugoMenuItem]]) -> Void) {
        mutate(&config.menus)
        config.commitMenus()
        commit()
    }

    private func addMenu(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, config.menus[trimmed] == nil else { return }
        applyMenuMutation { menus in
            menus[trimmed] = []
        }
        showAddMenu = false
        newMenuName = ""
    }

    private func deleteMenu(_ menuName: String) {
        applyMenuMutation { menus in
            menus.removeValue(forKey: menuName)
        }
    }

    private func addItem(to menuName: String) {
        applyMenuMutation { menus in
            var items = menus[menuName] ?? []
            let nextWeight = (items.map(\.weight).max() ?? 0) + 10
            items.append(HugoMenuItem(name: "New Item", weight: nextWeight))
            menus[menuName] = items
        }
    }

    private func deleteItem(_ item: HugoMenuItem, from menuName: String) {
        applyMenuMutation { menus in
            menus[menuName]?.removeAll { $0.id == item.id }
        }
    }

    private func updateItem(_ updated: HugoMenuItem, in menuName: String) {
        applyMenuMutation { menus in
            guard var items = menus[menuName] else { return }
            guard let index = items.firstIndex(where: { $0.id == updated.id }) else { return }
            items[index] = updated
            menus[menuName] = items
        }
    }

    /// Drag-reorder: moves within the weight-sorted display list, then
    /// rewrites every item's weight in steps of 10 following the new order
    /// (`HugoMenuItem.reweighted`, CONFIG-SCHEMA-SPEC §3.4).
    private func moveItems(in menuName: String, from source: IndexSet, to destination: Int) {
        applyMenuMutation { menus in
            var items = sortedItems(in: menuName)
            items.move(fromOffsets: source, toOffset: destination)
            menus[menuName] = HugoMenuItem.reweighted(items)
        }
    }
}

// MARK: - Per-item row

private struct ConfigMenuItemRow: View {
    let item: HugoMenuItem
    let siblingIdentifiers: [String]
    let onUpdate: (HugoMenuItem) -> Void
    let onDelete: () -> Void

    private static let noneTag = "__none__"

    private var hasPreservedExtra: Bool {
        item.extra.keys.contains { ["pre", "post", "params"].contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                DraftTextField(
                    label: "Name",
                    placeholder: "Required",
                    value: item.name,
                    isValid: { !$0.isEmpty },
                    commit: { text in
                        var updated = item
                        updated.name = text
                        onUpdate(updated)
                    }
                )
                .frame(width: 160)

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete menu item")
                .accessibilityLabel("Delete Menu Item \(item.name)")
            }

            HStack(alignment: .top, spacing: 12) {
                DraftTextField(
                    label: "URL",
                    placeholder: "/about/",
                    value: item.url ?? "",
                    commit: { text in
                        onUpdate(HugoMenuItem.settingLink(item, type: .url, value: text))
                    }
                )
                .frame(width: 160)

                DraftTextField(
                    label: "Page Ref",
                    placeholder: "/posts/my-post",
                    value: item.pageRef ?? "",
                    commit: { text in
                        onUpdate(HugoMenuItem.settingLink(item, type: .pageRef, value: text))
                    }
                )
                .frame(width: 160)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weight").font(.caption).foregroundStyle(.secondary)
                    Stepper(
                        "\(item.weight)",
                        value: Binding(
                            get: { item.weight },
                            set: { newValue in
                                var updated = item
                                updated.weight = newValue
                                onUpdate(updated)
                            }
                        ),
                        step: 10
                    )
                    .frame(width: 100)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Parent").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { item.parent ?? Self.noneTag },
                        set: { newValue in
                            var updated = item
                            updated.parent = newValue == Self.noneTag ? nil : newValue
                            onUpdate(updated)
                        }
                    )) {
                        Text("None").tag(Self.noneTag)
                        ForEach(siblingIdentifiers, id: \.self) { identifier in
                            Text(identifier).tag(identifier)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                DraftTextField(
                    label: "Identifier",
                    placeholder: "auto",
                    value: item.identifier ?? "",
                    commit: { text in
                        var updated = item
                        updated.identifier = text.isEmpty ? nil : text
                        onUpdate(updated)
                    }
                )
                .frame(width: 160)

                DraftTextField(
                    label: "Title (tooltip)",
                    placeholder: "Shown on hover",
                    value: item.title ?? "",
                    commit: { text in
                        var updated = item
                        updated.title = text.isEmpty ? nil : text
                        onUpdate(updated)
                    }
                )
                .frame(width: 200)
            }

            if hasPreservedExtra {
                Text("pre/post/params preserved")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Draft-commit text field

/// Local `@State` draft, committed on blur/submit only — never per keystroke
/// (CLAUDE.md's Per-Keystroke Invalidation Contract). Same pattern as
/// `ConfigFieldView.swift`'s `ConfigTextDraftRow`, reimplemented here rather
/// than shared: that type is `private` and reads/writes a `ConfigValueStore`
/// directly, whereas `HugoMenuItem` fields flow through `onUpdate` closures
/// over immutable struct copies — different enough plumbing that sharing
/// would mean threading a store-shaped adapter through a model that has none.
private struct DraftTextField: View {
    let label: String
    let placeholder: String
    let value: String
    var isValid: (String) -> Bool = { _ in true }
    let commit: (String) -> Void

    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit { commitDraft() }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commitDraft() }
                }
        }
        .onAppear { draft = value }
        .onChange(of: value) { _, newValue in
            if !isFocused { draft = newValue }
        }
    }

    private func commitDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValid(trimmed) else {
            draft = value
            return
        }
        guard trimmed != value else { return }
        commit(trimmed)
    }
}

#Preview {
    let config = HugoConfig()
    config.menus = [
        "main": [
            HugoMenuItem(name: "Home", url: "/", weight: 10, identifier: "home"),
            HugoMenuItem(name: "About", url: "/about/", weight: 20, parent: "home")
        ],
        "footer": []
    ]

    return ConfigMenusTab(config: config)
        .environment(\.configCommitAction, config.syncRawContentFromStructuredData)
        .frame(width: 600, height: 500)
}
