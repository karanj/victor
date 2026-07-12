import SwiftUI

/// View for creating a new archetype file in the archetypes/ directory
struct NewArchetypeView: View {
    let targetDirectory: URL
    let onCreated: (URL) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var archetypeName = ""
    @State private var selectedFormat: FrontmatterFormat = .yaml
    @State private var includeCommonFields = true
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Archetype")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Form {
                Section("Archetype Details") {
                    TextField("Name (e.g., posts, news, projects)", text: $archetypeName)
                        .textFieldStyle(.roundedBorder)

                    Picker("Frontmatter Format", selection: $selectedFormat) {
                        Text("YAML").tag(FrontmatterFormat.yaml)
                        Text("TOML").tag(FrontmatterFormat.toml)
                        Text("JSON").tag(FrontmatterFormat.json)
                    }
                    .pickerStyle(.segmented)

                    Toggle("Include common fields", isOn: $includeCommonFields)
                        .help("Pre-populate with title, date, and draft fields")
                }

                Section("Preview") {
                    HStack {
                        Text("File:")
                            .foregroundStyle(.secondary)
                        Text(previewFilename)
                            .font(.system(.body, design: .monospaced))
                    }

                    HStack {
                        Text("Location:")
                            .foregroundStyle(.secondary)
                        Text("archetypes/")
                            .font(.system(.body, design: .monospaced))
                    }

                    HStack(alignment: .top) {
                        Text("Content type:")
                            .foregroundStyle(.secondary)
                        Text(contentTypeDescription)
                            .font(.caption)
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(Color.Status.error)
                            .accessibilityLabel("Error: \(error)")
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer buttons
            HStack {
                Spacer()

                Button("Create") {
                    createArchetype()
                }
                .buttonStyle(.borderedProminent)
                .disabled(archetypeName.isEmpty || isCreating)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 450, height: 380)
    }

    private var previewFilename: String {
        let name = archetypeName.isEmpty ? "untitled" : archetypeName.lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return "\(name).md"
    }

    private var contentTypeDescription: String {
        let name = archetypeName.isEmpty ? "untitled" : archetypeName.lowercased()
        return "Used when creating content in content/\(name)/"
    }

    private func createArchetype() {
        guard !archetypeName.isEmpty else { return }

        isCreating = true
        errorMessage = nil

        let sanitizedName = archetypeName.lowercased()
            .replacingOccurrences(of: " ", with: "-")
        let filename = "\(sanitizedName).md"
        let fileURL = targetDirectory.appendingPathComponent(filename)

        // Check if file already exists
        if FileManager.default.fileExists(atPath: fileURL.path) {
            errorMessage = "An archetype with this name already exists"
            isCreating = false
            return
        }

        // Generate archetype content based on format
        let content = generateArchetypeContent()

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            onCreated(fileURL)
            dismiss()
        } catch {
            errorMessage = "Failed to create archetype: \(error.localizedDescription)"
            isCreating = false
        }
    }

    private func generateArchetypeContent() -> String {
        if includeCommonFields {
            switch selectedFormat {
            case .yaml:
                return """
                ---
                title: "{{ replace .File.ContentBaseName "-" " " | title }}"
                date: '{{ .Date }}'
                draft: true
                description: ""
                tags: []
                categories: []
                ---

                Write your content here.
                """

            case .toml:
                return """
                +++
                title = "{{ replace .File.ContentBaseName "-" " " | title }}"
                date = '{{ .Date }}'
                draft = true
                description = ""
                tags = []
                categories = []
                +++

                Write your content here.
                """

            case .json:
                return """
                {
                  "title": "{{ replace .File.ContentBaseName \\"-\\" \\" \\" | title }}",
                  "date": "{{ .Date }}",
                  "draft": true,
                  "description": "",
                  "tags": [],
                  "categories": []
                }

                Write your content here.
                """
            }
        } else {
            switch selectedFormat {
            case .yaml:
                return """
                ---
                title: "{{ .Title }}"
                date: '{{ .Date }}'
                draft: true
                ---

                """

            case .toml:
                return """
                +++
                title = "{{ .Title }}"
                date = '{{ .Date }}'
                draft = true
                +++

                """

            case .json:
                return """
                {
                  "title": "{{ .Title }}",
                  "date": "{{ .Date }}",
                  "draft": true
                }

                """
            }
        }
    }
}

#Preview {
    NewArchetypeView(
        targetDirectory: URL(fileURLWithPath: "/tmp/archetypes"),
        onCreated: { _ in }
    )
}
