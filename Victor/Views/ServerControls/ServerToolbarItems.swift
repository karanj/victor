import SwiftUI

// MARK: - Presentation logic

/// Text/state for the toolbar's Hugo server group (status + Run/Stop), kept out of
/// the views so it's testable (`ServerToolbarTests`). The group is secondary to
/// editing, so the status text is terse; the tooltip spells it out.
enum ServerActivity {
    struct RunButton: Equatable {
        let title: String
        let systemImage: String
        let isEnabled: Bool
    }

    static func title(for status: HugoServerStatus, url: URL?) -> String {
        switch status {
        case .stopped:
            return "Stopped"
        case .starting:
            return "Starting…"
        case .running(let port):
            if let url, let host = url.host() {
                return "\(host):\(url.port ?? port)"
            }
            return "Port \(port)"
        case .error:
            return "Error"
        }
    }

    static func help(for status: HugoServerStatus, url: URL?) -> String {
        switch status {
        case .stopped:
            return "Hugo server stopped"
        case .starting:
            return "Hugo server starting"
        case .running(let port):
            return "Hugo server running at \(url?.absoluteString ?? "port \(port)")"
        case .error(let message):
            return "Hugo server error: \(message)"
        }
    }

    static func runButton(for status: HugoServerStatus) -> RunButton {
        switch status {
        case .running:
            return RunButton(title: "Stop Hugo Server", systemImage: "stop.fill", isEnabled: true)
        case .starting:
            return RunButton(title: "Run Hugo Server", systemImage: "play.fill", isEnabled: false)
        case .stopped, .error:
            return RunButton(title: "Run Hugo Server", systemImage: "play.fill", isEnabled: true)
        }
    }

    static func dotColor(for status: HugoServerStatus) -> Color {
        switch status {
        case .stopped: return .secondary
        case .starting: return .yellow
        case .running: return .green
        case .error: return .red
        }
    }
}

// MARK: - Run/Stop split button

/// Leading toolbar item: click runs/stops the server; the menu holds the
/// server's secondary actions, which stay put (disabled) rather than appearing
/// and disappearing with the server state.
struct ServerRunMenu: View {
    @Bindable var siteViewModel: SiteViewModel

    @State private var isConfigPopoverPresented = false
    @State private var isHugoInstalled = true
    @State private var isHugoMissingAlertPresented = false

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    private var status: HugoServerStatus { siteViewModel.hugoServerStatus }

    var body: some View {
        let run = ServerActivity.runButton(for: status)

        Menu {
            Button("Open in Browser", systemImage: "safari") {
                if let url = siteViewModel.hugoServerURL {
                    NSWorkspace.shared.open(url)
                }
            }
            .disabled(!status.isRunning || siteViewModel.hugoServerURL == nil)

            Button("Show Server Logs", systemImage: "waveform.path.ecg.text") {
                openWindow(id: "server-logs")
            }
            .disabled(!status.isRunning)

            Divider()

            Button("Server Settings…", systemImage: "gearshape") {
                isConfigPopoverPresented = true
            }
        } label: {
            Label(run.title, systemImage: run.systemImage)
        } primaryAction: {
            guard run.isEnabled else { return }
            Task { await toggleServer() }
        }
        .help(run.title)
        .disabled(siteViewModel.site == nil || !isHugoInstalled)
        .popover(isPresented: $isConfigPopoverPresented) {
            ServerConfigPopover(
                isPresented: $isConfigPopoverPresented,
                hugoServerService: siteViewModel.hugoServerService
            )
        }
        .task {
            isHugoInstalled = await siteViewModel.hugoServerService.isHugoInstalled()
            isHugoMissingAlertPresented = !isHugoInstalled
        }
        .alert("Hugo Not Found", isPresented: $isHugoMissingAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Hugo is not installed. Please install Hugo to use the development server.\n\nVisit https://gohugo.io/installation/ for installation instructions.")
        }
    }

    private func toggleServer() async {
        let wasRunning = status.isRunning
        // Start failures surface through SiteViewModel.errorMessage (ContentView's alert).
        await siteViewModel.toggleHugoServer()
        if wasRunning {
            dismissWindow(id: "server-logs")
        }
    }
}

// MARK: - Status

/// Shares the server group's glass capsule with `ServerRunMenu`: dot + terse
/// state, and a spinner while a site or file loads. No controls.
struct ServerStatusView: View {
    let siteViewModel: SiteViewModel

    var body: some View {
        let status = siteViewModel.hugoServerStatus
        let url = siteViewModel.hugoServerURL
        let isLoading = siteViewModel.isLoading || siteViewModel.isLoadingFile

        HStack(spacing: 8) {
            // Decorative: the text carries the state for VoiceOver.
            Circle()
                .fill(ServerActivity.dotColor(for: status))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            Text(ServerActivity.title(for: status, url: url))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()

            // Fixed slot so the text doesn't shift when loading starts/stops.
            ProgressView()
                .controlSize(.mini)
                .opacity(isLoading ? 1 : 0)
                .accessibilityHidden(!isLoading)
        }
        .padding(.leading, 6)
        .help(ServerActivity.help(for: status, url: url))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Server status")
        .accessibilityValue(ServerActivity.title(for: status, url: url))
    }
}
