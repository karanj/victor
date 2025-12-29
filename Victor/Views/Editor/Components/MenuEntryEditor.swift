import SwiftUI

/// Editor for a single menu entry
struct MenuEntryEditor: View {
    @Binding var entry: MenuEntry
    let onDelete: () -> Void
    @State private var showAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with menu name and delete button
            HStack {
                Text(entry.menuName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Remove from this menu")
            }

            // Basic fields
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Display Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Page title", text: Binding(
                        get: { entry.name ?? "" },
                        set: { entry.name = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Weight")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("0", value: Binding(
                        get: { entry.weight ?? 0 },
                        set: { entry.weight = $0 == 0 ? nil : $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Parent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("None", text: Binding(
                        get: { entry.parent ?? "" },
                        set: { entry.parent = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Identifier")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Auto", text: Binding(
                        get: { entry.identifier ?? "" },
                        set: { entry.identifier = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }

            // Advanced toggle
            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pre HTML")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("<i class='icon'></i>", text: Binding(
                                get: { entry.pre ?? "" },
                                set: { entry.pre = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Post HTML")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("", text: Binding(
                                get: { entry.post ?? "" },
                                set: { entry.post = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Title (Tooltip)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Tooltip text on hover", text: Binding(
                            get: { entry.title ?? "" },
                            set: { entry.title = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.top, 8)
            }
            .font(.caption)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

#Preview {
    @Previewable @State var entry = MenuEntry(
        menuName: "main",
        name: "My Page",
        weight: 10,
        parent: nil,
        identifier: "my-page"
    )

    return MenuEntryEditor(entry: $entry, onDelete: {})
        .frame(width: 400)
        .padding()
}
