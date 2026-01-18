import SwiftUI

/// Taxonomies tab for Hugo configuration editor
/// Handles custom taxonomy definitions
struct ConfigTaxonomiesTab: View {
    @Bindable var config: HugoConfig
    @State private var newSingular = ""
    @State private var newPlural = ""

    var body: some View {
        Form {
            Section {
                ForEach(Array(config.taxonomies.keys.sorted()), id: \.self) { singular in
                    HStack {
                        Text(singular)
                            .fontWeight(.medium)
                            .frame(width: 120, alignment: .trailing)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(config.taxonomies[singular] ?? "")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) {
                            config.taxonomies.removeValue(forKey: singular)
                            config.hasUnsavedChanges = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    TextField("singular", text: $newSingular)
                        .frame(width: 120)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor))
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("plural", text: $newPlural)
                        .frame(width: 120)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor))
                    Button("Add") {
                        if !newSingular.isEmpty && !newPlural.isEmpty {
                            config.taxonomies[newSingular] = newPlural
                            config.hasUnsavedChanges = true
                            newSingular = ""
                            newPlural = ""
                        }
                    }
                    .disabled(newSingular.isEmpty || newPlural.isEmpty)
                }
            } header: {
                Text("Taxonomies")
            } footer: {
                Text("Define custom taxonomies for organizing content. The singular form is used in URLs, the plural in section names.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
