import SwiftUI

/// View for creating a new translation file in the i18n/ directory
struct NewTranslationFileView: View {
    let targetDirectory: URL
    let onCreated: (URL) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var languageCode = ""
    @State private var selectedFormat: DataFormat = .yaml
    @State private var isCreating = false
    @State private var errorMessage: String?

    /// Common language codes for quick selection
    private let commonLanguages = [
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("zh", "Chinese"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("ar", "Arabic"),
        ("ru", "Russian"),
        ("nl", "Dutch"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Translation File")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Form {
                Section("Language") {
                    TextField("Language Code (e.g., en, fr, de)", text: $languageCode)
                        .textFieldStyle(.roundedBorder)

                    // Quick select common languages
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 80))
                    ], spacing: 8) {
                        ForEach(commonLanguages, id: \.0) { code, name in
                            Button {
                                languageCode = code
                            } label: {
                                VStack(spacing: 2) {
                                    Text(code.uppercased())
                                        .font(.caption.bold())
                                    Text(name)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(languageCode == code ? Color.accentColor.opacity(0.2) : Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Format") {
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
                            .foregroundStyle(.red)
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
                .disabled(languageCode.isEmpty || isCreating)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 450, height: 480)
    }

    private var previewFilename: String {
        let code = languageCode.isEmpty ? "xx" : languageCode.lowercased()
        let ext = selectedFormat.extensions.first ?? "yaml"
        return "\(code).\(ext)"
    }

    private func createFile() {
        guard !languageCode.isEmpty else { return }

        isCreating = true
        errorMessage = nil

        let code = languageCode.lowercased()
        let ext = selectedFormat.extensions.first ?? "yaml"
        let finalFilename = "\(code).\(ext)"
        let fileURL = targetDirectory.appendingPathComponent(finalFilename)

        // Check if file already exists
        if FileManager.default.fileExists(atPath: fileURL.path) {
            errorMessage = "A translation file for '\(code)' already exists"
            isCreating = false
            return
        }

        // Create translation file with example content
        let content: String
        switch selectedFormat {
        case .yaml:
            content = """
            # Translation file for \(code)
            # Add your translations as key-value pairs

            hello: "Hello"
            welcome: "Welcome"

            """
        case .json:
            content = """
            {
              "hello": "Hello",
              "welcome": "Welcome"
            }

            """
        case .toml:
            content = """
            # Translation file for \(code)
            # Add your translations as key-value pairs

            hello = "Hello"
            welcome = "Welcome"

            """
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
