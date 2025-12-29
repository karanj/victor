import SwiftUI

/// Menu configuration tab for adding pages to Hugo menus
struct MenusTab: View {
    @Bindable var frontmatter: Frontmatter
    @State private var showAddMenu = false
    @State private var newMenuName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Add this page to menus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HelpTooltip(text: "Menus allow you to organize your site navigation. Common menus include 'main' (primary navigation), 'footer', and 'sidebar'.")
                Spacer()
            }

            // Menu entries
            if frontmatter.menus.isEmpty {
                emptyState
            } else {
                ForEach(Array(frontmatter.menus.enumerated()), id: \.element.id) { index, _ in
                    MenuEntryEditor(
                        entry: $frontmatter.menus[index],
                        onDelete: { removeMenu(at: index) }
                    )
                }
            }

            // Add menu button
            if showAddMenu {
                addMenuForm
            } else {
                Button(action: { showAddMenu = true }) {
                    Label("Add to Menu", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)

            Text("Not in any menus")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Add this page to a menu to include it in your site's navigation.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var addMenuForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add to Menu")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            // Common menus
            HStack(spacing: 8) {
                ForEach(CommonMenu.allCases, id: \.self) { menu in
                    let isAlreadyAdded = frontmatter.menus.contains { $0.menuName == menu.rawValue }
                    Button(action: { addMenu(name: menu.rawValue) }) {
                        Text(menu.displayName)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isAlreadyAdded)
                }
            }

            // Custom menu name
            HStack {
                TextField("Custom menu name", text: $newMenuName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if !newMenuName.isEmpty {
                            addMenu(name: newMenuName)
                        }
                    }

                Button("Add") {
                    addMenu(name: newMenuName)
                }
                .disabled(newMenuName.isEmpty || frontmatter.menus.contains { $0.menuName == newMenuName })

                Button("Cancel") {
                    showAddMenu = false
                    newMenuName = ""
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func addMenu(name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedName.isEmpty else { return }
        guard !frontmatter.menus.contains(where: { $0.menuName == trimmedName }) else { return }

        frontmatter.menus.append(MenuEntry(menuName: trimmedName))
        showAddMenu = false
        newMenuName = ""
    }

    private func removeMenu(at index: Int) {
        frontmatter.menus.remove(at: index)
    }
}

#Preview {
    let frontmatter = Frontmatter(rawContent: "---\n---", format: .yaml)
    frontmatter.menus = [
        MenuEntry(menuName: "main", name: "My Page", weight: 10),
        MenuEntry(menuName: "footer", weight: 100)
    ]

    return ScrollView {
        MenusTab(frontmatter: frontmatter)
            .padding()
    }
    .frame(width: 450, height: 600)
}
