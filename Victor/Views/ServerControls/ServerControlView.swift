import SwiftUI

/// Toolbar controls for Hugo server management
struct ServerControlView: View {
    @Bindable var siteViewModel: SiteViewModel

    @State private var serverStatus: HugoServerStatus = .stopped
    @State private var buildErrors: [HugoBuildError] = []
    @State private var isConfigPopoverPresented = false
    @State private var isErrorsPopoverPresented = false
    @State private var isHugoInstalled = false
    @State private var showingError = false
    @State private var errorTitle = ""
    @State private var errorMessage = ""
    
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator with text
            statusIndicator

            Divider()
                .frame(height: 20)

            // Start/Stop button
            startStopButton

            // Open in Browser button (shown when running)
            if serverStatus.isRunning {
                openBrowserButton
                showServerLogButton
            }

            // Configuration button
            configButton

            // Error count badge (shown when there are errors)
            if !buildErrors.isEmpty {
                errorBadge
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .onAppear {
            setupServerCallbacks()
            checkHugoInstallation()
        }
        .alert(errorTitle, isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Status Indicator

    private var statusIndicator: some View {
        HStack(spacing: 6) {
            // Colored status dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(serverStatus.displayText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch serverStatus {
        case .stopped:
            return .secondary
        case .starting:
            return .yellow
        case .running:
            return .green
        case .error:
            return .red
        }
    }

    // MARK: - Start/Stop Button

    private var startStopButton: some View {
        Button {
            Task {
                await toggleServer()
            }
        } label: {
            Label(
                serverStatus.isRunning ? "Stop" : "Start",
                systemImage: serverStatus.isRunning ? "stop.fill" : "play.fill"
            )
        }
        .disabled(!isHugoInstalled || serverStatus == .starting)
        .help(serverStatus.isRunning ? "Stop Hugo server" : "Start Hugo development server")
    }

    // MARK: - Open Browser Button

    private var openBrowserButton: some View {
        Button {
            openInBrowser()
        } label: {
            Label("Open", systemImage: "safari")
        }
        .help("Open site in default browser")
    }
    
    private var showServerLogButton: some View {
        Button {
            showServerLogView()
        } label: {
            Label("Server Logs", systemImage: "waveform.path.ecg.text")
        }
        .help("Open Server Logs")
    }

    // MARK: - Configuration Button

    private var configButton: some View {
        Button {
            isConfigPopoverPresented.toggle()
        } label: {
            Label("Settings", systemImage: "gearshape")
                .labelStyle(.iconOnly)
        }
        .help("Server configuration")
        .popover(isPresented: $isConfigPopoverPresented) {
            ServerConfigPopover(isPresented: $isConfigPopoverPresented)
        }
    }

    // MARK: - Error Badge

    private var errorBadge: some View {
        Button {
            isErrorsPopoverPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.white)

                Text("\(buildErrors.count)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(.red)
            )
        }
        .buttonStyle(.plain)
        .help("Click to view \(buildErrors.count) build error\(buildErrors.count == 1 ? "" : "s")")
        .popover(isPresented: $isErrorsPopoverPresented) {
            ErrorsPopoverView(errors: buildErrors)
        }
    }

    // MARK: - Actions

    private func toggleServer() async {
        guard let siteURL = siteViewModel.site?.rootURL else {
            showError(title: "No Site Open", message: "Please open a Hugo site first.")
            return
        }

        if serverStatus.isRunning {
            // Stop the server
            await HugoServerService.shared.stop()
            dismissWindow(id: "server-logs")
        } else {
            // Start the server
            do {
                try await HugoServerService.shared.start(siteURL: siteURL)
            } catch {
                showError(title: "Failed to Start Server", message: error.localizedDescription)
            }
        }
    }

    private func openInBrowser() {
        Task {
            let serverURL = await HugoServerService.shared.serverURL
            guard let url = serverURL else { return }
            NSWorkspace.shared.open(url)
        }
    }
    // TODO: Fix this so it shows the server log in a separate window
    private func showServerLogView() {
        openWindow(id: "server-logs")
    }

    private func setupServerCallbacks() {
        // Set up callbacks to update UI when server state changes
        Task {
            await HugoServerService.shared.setOnStatusChange { @MainActor newStatus in
                withAnimation {
                    serverStatus = newStatus
                }
            }

            await HugoServerService.shared.setOnBuildErrorsChange { @MainActor errors in
                withAnimation {
                    buildErrors = errors
                }
            }

            // Get initial status
            let initialStatus = await HugoServerService.shared.status
            serverStatus = initialStatus

            let initialErrors = await HugoServerService.shared.buildErrors
            buildErrors = initialErrors
        }
    }

    private func checkHugoInstallation() {
        Task {
            isHugoInstalled = await HugoServerService.shared.isHugoInstalled()

            if !isHugoInstalled {
                showError(
                    title: "Hugo Not Found",
                    message: "Hugo is not installed. Please install Hugo to use the development server.\n\nVisit https://gohugo.io/installation/ for installation instructions."
                )
            }
        }
    }

    private func showError(title: String, message: String) {
        errorTitle = title
        errorMessage = message
        showingError = true
    }
}

// MARK: - Errors Popover View

/// Popover view showing build error details
private struct ErrorsPopoverView: View {
    let errors: [HugoBuildError]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Build Errors (\(errors.count))")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Error list
            if errors.isEmpty {
                Text("No errors")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(errors) { error in
                            ErrorRowView(error: error)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 450, height: 300)
    }
}

/// Row view for a single build error
private struct ErrorRowView: View {
    let error: HugoBuildError

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // Level icon
                Image(systemName: error.level == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(error.level == .error ? .red : .orange)
                    .font(.system(size: 12))

                // File path if available
                if let filePath = error.clickableFilePath {
                    Text(filePath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.blue)
                }

                Spacer()

                // Timestamp
                Text(error.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Error message
            Text(error.message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

// MARK: - Preview

#Preview {
    VStack {
        ServerControlView(siteViewModel: SiteViewModel())
            .padding()

        Spacer()
    }
    .frame(width: 600, height: 200)
}
