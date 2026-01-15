import SwiftUI

/// Configuration popover for Hugo server settings
struct ServerConfigPopover: View {
    @Binding var isPresented: Bool

    @State private var config: HugoServerConfig
    @State private var hasChanges = false

    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented

        // Load initial config from service
        let initialConfig = HugoServerConfig()
        self._config = State(initialValue: initialConfig)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Server Configuration")
                .font(.headline)

            Form {
                // Port number
                HStack {
                    Text("Port:")
                        .frame(width: 120, alignment: .leading)
                    
                    Spacer()
                    
                    TextField("", value: $config.port,
                              format: .number.grouping(.never),
                              prompt: Text("(1024-65535)"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .onChange(of: config.port) { _, _ in
                            hasChanges = true
                        }
                }

                Divider()

                // Build options
                VStack(alignment: .leading, spacing: 8) {
                    Text("Build Options")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Toggle("Build drafts", isOn: $config.buildDrafts)
                        .onChange(of: config.buildDrafts) { _, _ in
                            hasChanges = true
                        }

                    Toggle("Build future", isOn: $config.buildFuture)
                        .onChange(of: config.buildFuture) { _, _ in
                            hasChanges = true
                        }

                    Toggle("Build expired", isOn: $config.buildExpired)
                        .onChange(of: config.buildExpired) { _, _ in
                            hasChanges = true
                        }

                    Toggle("Disable live reload", isOn: $config.disableLiveReload)
                        .onChange(of: config.disableLiveReload) { _, _ in
                            hasChanges = true
                        }
                }
            }
            .formStyle(.grouped)

            // Buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Apply") {
                    applyConfiguration()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!hasChanges || !isValidConfig)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            loadCurrentConfig()
        }
    }

    // MARK: - Validation

    private var isValidConfig: Bool {
        config.port >= 1024 && config.port <= 65535
    }

    // MARK: - Actions

    private func loadCurrentConfig() {
        Task {
            let currentConfig = await HugoServerService.shared.config
            await MainActor.run {
                config = currentConfig
                hasChanges = false
            }
        }
    }

    private func applyConfiguration() {
        guard isValidConfig else { return }

        Task {
            await HugoServerService.shared.updateConfig(config)
            await MainActor.run {
                hasChanges = false
                isPresented = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var isPresented = true

        var body: some View {
            VStack {
                Text("Popover Preview")

                Button("Show Config") {
                    isPresented = true
                }
                .popover(isPresented: $isPresented) {
                    ServerConfigPopover(isPresented: $isPresented)
                }
            }
            .frame(width: 600, height: 400)
        }
    }

    return PreviewWrapper()
}
