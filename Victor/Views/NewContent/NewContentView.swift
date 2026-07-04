import SwiftUI

/// View for creating new content from an archetype
struct NewContentView: View {
    let siteURL: URL
    let targetDirectory: URL
    let onCreated: (URL) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var archetypes: [Archetype] = []
    @State private var selectedArchetype: Archetype?
    @State private var title = ""
    @State private var customFilename = ""
    @State private var useCustomFilename = false
    @State private var isLoading = true
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Content")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if isLoading {
                ProgressView("Loading archetypes...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    // Archetype selection
                    Section("Template") {
                        if archetypes.isEmpty {
                            Text("No archetypes found. Using default template.")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Archetype", selection: $selectedArchetype) {
                                Text("Default").tag(nil as Archetype?)
                                ForEach(archetypes) { archetype in
                                    Text(archetype.displayName)
                                        .tag(archetype as Archetype?)
                                }
                            }
                        }
                    }

                    // Content details
                    Section("Content") {
                        TextField("Title", text: $title)
                            .textFieldStyle(.roundedBorder)

                        Toggle("Custom filename", isOn: $useCustomFilename)

                        if useCustomFilename {
                            HStack {
                                TextField("Filename", text: $customFilename)
                                    .textFieldStyle(.roundedBorder)
                                Text(".md")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Preview
                    Section("Preview") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("File:")
                                    .foregroundStyle(.secondary)
                                Text(previewFilename)
                                    .font(.system(.body, design: .monospaced))
                            }

                            HStack {
                                Text("Location:")
                                    .foregroundStyle(.secondary)
                                Text(targetDirectory.lastPathComponent + "/")
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Error message
                    if let error = errorMessage {
                        Section {
                            Text(error)
                                .foregroundStyle(Color.Status.error)
                        }
                    }
                }
                .formStyle(.grouped)
            }

            Divider()

            // Footer buttons
            HStack {
                Spacer()

                Button("Create") {
                    createContent()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty || isCreating)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 450, height: 400)
        .task {
            await loadArchetypes()
        }
    }

    private var previewFilename: String {
        if useCustomFilename && !customFilename.isEmpty {
            return customFilename.hasSuffix(".md") ? customFilename : "\(customFilename).md"
        }
        let slug = slugify(title)
        return slug.isEmpty ? "untitled.md" : "\(slug).md"
    }

    private func loadArchetypes() async {
        isLoading = true
        do {
            archetypes = try await ArchetypeManager.shared.loadArchetypes(from: siteURL)
            // Select the default archetype if available
            selectedArchetype = archetypes.first { $0.isDefault }
        } catch {
            errorMessage = "Failed to load archetypes: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func createContent() {
        guard !title.isEmpty else { return }

        isCreating = true
        errorMessage = nil

        Task {
            do {
                let filename = useCustomFilename && !customFilename.isEmpty ? customFilename : nil
                let fileURL: URL

                if let archetype = selectedArchetype {
                    fileURL = try await ArchetypeManager.shared.createContent(
                        from: archetype,
                        title: title,
                        in: targetDirectory,
                        filename: filename
                    )
                } else {
                    // Use default content
                    let content = ArchetypeManager.shared.defaultArchetypeContent(title: title)
                    let slug = filename ?? slugify(title)
                    let fileName = slug.hasSuffix(".md") ? slug : "\(slug).md"
                    fileURL = targetDirectory.appendingPathComponent(fileName)

                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        throw ArchetypeError.fileAlreadyExists(fileURL)
                    }

                    try content.write(to: fileURL, atomically: true, encoding: .utf8)
                }

                await MainActor.run {
                    onCreated(fileURL)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isCreating = false
                }
            }
        }
    }

    private func slugify(_ text: String) -> String {
        let lowercased = text.lowercased()
        let alphanumeric = lowercased.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return alphanumeric.filter { !$0.isEmpty }.joined(separator: "-")
    }
}

/// Compact button version for toolbar/menu integration
struct NewContentButton: View {
    let siteURL: URL
    let targetDirectory: URL
    let onCreated: (URL) -> Void

    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            Label("New Content", systemImage: "doc.badge.plus")
        }
        .sheet(isPresented: $showSheet) {
            NewContentView(
                siteURL: siteURL,
                targetDirectory: targetDirectory,
                onCreated: onCreated
            )
        }
    }
}
