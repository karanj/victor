import SwiftUI

/// View for creating a new data file in the data/ directory
struct NewDataFileView: View {
    let targetDirectory: URL
    let onCreated: (URL) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var filename = ""
    @State private var selectedFormat: DataFormat = .yaml
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Data File")
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
                Section("File Details") {
                    TextField("Filename", text: $filename)
                        .textFieldStyle(.roundedBorder)

                    Picker("Format", selection: $selectedFormat) {
                        Text("YAML").tag(DataFormat.yaml)
                        Text("JSON").tag(DataFormat.json)
                        Text("TOML").tag(DataFormat.toml)
                    }
                    .pickerStyle(.segmented)
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
                        Text(targetDirectory.lastPathComponent + "/")
                            .font(.system(.body, design: .monospaced))
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
                    createFile()
                }
                .buttonStyle(.borderedProminent)
                .disabled(filename.isEmpty || isCreating)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 400, height: 300)
    }

    private var previewFilename: String {
        let base = filename.isEmpty ? "untitled" : filename
        let ext = selectedFormat.extensions.first ?? "yaml"
        if base.hasSuffix(".\(ext)") {
            return base
        }
        return "\(base).\(ext)"
    }

    private func createFile() {
        guard !filename.isEmpty else { return }

        isCreating = true
        errorMessage = nil

        let ext = selectedFormat.extensions.first ?? "yaml"
        let finalFilename = filename.hasSuffix(".\(ext)") ? filename : "\(filename).\(ext)"
        let fileURL = targetDirectory.appendingPathComponent(finalFilename)

        // Check if file already exists
        if FileManager.default.fileExists(atPath: fileURL.path) {
            errorMessage = "A file with this name already exists"
            isCreating = false
            return
        }

        // Create data file with valid parseable content
        let content: String
        switch selectedFormat {
        case .yaml:
            content = "# Data file\n# Add your data below\nkey: value\n"
        case .json:
            content = "{\n  \"key\": \"value\"\n}\n"
        case .toml:
            content = "# Data file\n# Add your data below\nkey = \"value\"\n"
        }

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            onCreated(fileURL)
            dismiss()
        } catch {
            errorMessage = "Failed to create file: \(error.localizedDescription)"
            isCreating = false
        }
    }
}
