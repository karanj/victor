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

    /// Tracks whether we've auto-shown the errors popover this server session
    @State private var hasAutoShownErrorsThisSession = false
    
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            checkHugoInstallation()
        }
        .task {
            await observeServerStatus()
        }
        .task {
            await observeBuildErrors()
        }
        .alert(errorTitle, isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: serverStatus) { oldStatus, newStatus in
            // Reset auto-show flag when server stops
            if !newStatus.isRunning {
                hasAutoShownErrorsThisSession = false
            }
        }
        .onChange(of: buildErrors) { _, newErrors in
            // Auto-show popover on first errors after server start
            if serverStatus.isRunning && !newErrors.isEmpty && !hasAutoShownErrorsThisSession {
                hasAutoShownErrorsThisSession = true
                isErrorsPopoverPresented = true
            }
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
        .accessibilityLabel("Server Settings")
        .accessibilityHint("Configure Hugo server options")
        .popover(isPresented: $isConfigPopoverPresented) {
            ServerConfigPopover(
                isPresented: $isConfigPopoverPresented,
                hugoServerService: siteViewModel.hugoServerService
            )
        }
    }

    // MARK: - Error Badge

    private var hasActualErrors: Bool {
        buildErrors.contains { $0.level == .error }
    }

    private var errorBadge: some View {
        Button {
            isErrorsPopoverPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: hasActualErrors ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
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
                    .fill(hasActualErrors ? .red : .orange)
            )
        }
        .buttonStyle(.plain)
        .help("Click to view \(buildErrors.count) build \(hasActualErrors ? "error" : "warning")\(buildErrors.count == 1 ? "" : "s")")
        .popover(isPresented: $isErrorsPopoverPresented) {
            BuildIssuesPopover(
                errors: buildErrors,
                onFileClick: { filePath in
                    // TODO: Navigate to file in editor
                    Logger.shared.info("[ServerControl] File clicked: \(filePath)")
                },
                onDismiss: {
                    isErrorsPopoverPresented = false
                }
            )
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
            await siteViewModel.hugoServerService.stop()
            dismissWindow(id: "server-logs")
        } else {
            // Start the server
            do {
                try await siteViewModel.hugoServerService.start(siteURL: siteURL)
            } catch {
                showError(title: "Failed to Start Server", message: error.localizedDescription)
            }
        }
    }

    private func openInBrowser() {
        Task {
            let serverURL = await siteViewModel.hugoServerService.serverURL
            guard let url = serverURL else { return }
            NSWorkspace.shared.open(url)
        }
    }
    // TODO: Fix this so it shows the server log in a separate window
    private func showServerLogView() {
        openWindow(id: "server-logs")
    }

    /// Independent stream consumer (WP3.5 Cluster 9 / M2) - same shape as
    /// `SiteViewModel`'s observers, just not routed through it (`ServerControlView`
    /// is its own `@MainActor` consumer). Using SwiftUI's `.task {}` instead of a
    /// bare `Task {}` inside `.onAppear`-style setup means the observation task
    /// is automatically cancelled when the view disappears - a strict
    /// improvement over the old callback registration, which never
    /// deregistered and leaked for the toolbar's lifetime.
    private func observeServerStatus() async {
        for await newStatus in await siteViewModel.hugoServerService.statusUpdates() {
            withAnimation(reduceMotion ? nil : .default) {
                serverStatus = newStatus
            }
        }
    }

    private func observeBuildErrors() async {
        for await errors in await siteViewModel.hugoServerService.buildErrorUpdates() {
            withAnimation(reduceMotion ? nil : .default) {
                buildErrors = errors
            }
        }
    }

    private func checkHugoInstallation() {
        Task {
            isHugoInstalled = await siteViewModel.hugoServerService.isHugoInstalled()

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

// MARK: - Preview

#Preview {
    VStack {
        ServerControlView(siteViewModel: SiteViewModel())
            .padding()

        Spacer()
    }
    .frame(width: 600, height: 200)
}
