import SwiftUI
import WebKit

/// Live preview panel that displays Hugo server output in a WKWebView
/// Replaces the markdown-only preview when Hugo server is running
struct LivePreviewPanel: View {
    let siteViewModel: SiteViewModel
    let currentFilePath: String?

    @State private var status: HugoServerStatus = .stopped
    @State private var serverURL: URL?
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false
    @State private var currentURL: String = ""

    /// Navigation path triggered by LiveReload (from --navigateToChanged)
    @State private var liveReloadNavigatePath: String?
    /// Reload trigger incremented when LiveReload requests a refresh
    @State private var reloadTrigger: Int = 0

    /// Navigation action triggers
    @State private var goBackTrigger: Int = 0
    @State private var goForwardTrigger: Int = 0
    @State private var refreshTrigger: Int = 0

    var body: some View {
        Group {
            if status.isRunning, let url = serverURL {
                VStack(spacing: 0) {
                    // Navigation toolbar
                    navigationToolbar

                    Divider()

                    // Web view
                    LivePreviewWebView(
                        serverURL: url,
                        currentFilePath: currentFilePath,
                        liveReloadNavigatePath: $liveReloadNavigatePath,
                        reloadTrigger: reloadTrigger,
                        goBackTrigger: goBackTrigger,
                        goForwardTrigger: goForwardTrigger,
                        refreshTrigger: refreshTrigger,
                        canGoBack: $canGoBack,
                        canGoForward: $canGoForward,
                        currentURL: $currentURL
                    )
                }
            } else {
                // Server not running placeholder
                serverNotRunningPlaceholder
            }
        }
        .onAppear {
            setupServerStateObservers()
            Task {
                await refreshServerState()
            }
        }
    }

    // MARK: - Navigation Toolbar

    private var navigationToolbar: some View {
        HStack(spacing: 12) {
            // Back button
            Button {
                goBackTrigger += 1
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(canGoBack ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canGoBack)
            .help("Go back")
            .accessibilityLabel("Go back")
            .accessibilityHint("Navigate to previous page")

            // Forward button
            Button {
                goForwardTrigger += 1
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(canGoForward ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canGoForward)
            .help("Go forward")
            .accessibilityLabel("Go forward")
            .accessibilityHint("Navigate to next page")

            // Refresh button
            Button {
                refreshTrigger += 1
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh")
            .accessibilityLabel("Refresh page")
            .accessibilityHint("Reload the current page")

            Divider()
                .frame(height: 16)

            // URL display
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                Text(currentURL.isEmpty ? serverURL?.absoluteString ?? "" : currentURL)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Spacer()

            // Server status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(serverStatusColor)
                    .frame(width: 8, height: 8)

                Text(status.displayText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var serverStatusColor: Color {
        switch status {
        case .running:
            return .green
        case .starting:
            return .orange
        case .stopped:
            return .gray
        case .error:
            return .red
        }
    }

    // MARK: - Server Not Running Placeholder

    private var serverNotRunningPlaceholder: some View {
        EmptyStateView(
            icon: "server.rack",
            title: "Hugo Server Not Running",
            message: "Start the Hugo development server to see live preview of your site."
        )
        // TODO: Add start server action when ServerControlPanel is implemented
        // EmptyStateView(
        //     icon: "server.rack",
        //     title: "Hugo Server Not Running",
        //     message: "Start the Hugo development server to see live preview of your site.",
        //     actionLabel: "Start Server",
        //     actionIcon: "play.fill"
        // ) {
        //     Task {
        //         try? await HugoServerService.shared.start(siteURL: siteViewModel.site!.rootURL)
        //     }
        // }
    }

    // MARK: - Server State Management

    private func setupServerStateObservers() {
        Task {
            await HugoServerService.shared.setOnStatusChange { @MainActor newStatus in
                let previousStatus = status
                status = newStatus

                // Connect/disconnect LiveReload based on server status
                if newStatus.isRunning, let url = serverURL {
                    Task {
                        await LiveReloadClient.shared.connect(
                            to: url,
                            onNavigate: { path in
                                liveReloadNavigatePath = path
                            },
                            onReload: {
                                reloadTrigger += 1
                            }
                        )
                    }
                } else if previousStatus.isRunning && !newStatus.isRunning {
                    Task {
                        await LiveReloadClient.shared.disconnect()
                    }
                }
            }
        }
    }

    private func refreshServerState() async {
        let currentStatus = await HugoServerService.shared.status
        let currentServerURL = await HugoServerService.shared.serverURL

        await MainActor.run {
            status = currentStatus
            serverURL = currentServerURL

            // Connect LiveReload if server is already running
            if currentStatus.isRunning, let url = currentServerURL {
                Task {
                    await LiveReloadClient.shared.connect(
                        to: url,
                        onNavigate: { path in
                            liveReloadNavigatePath = path
                        },
                        onReload: {
                            reloadTrigger += 1
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Live Preview WebView

private struct LivePreviewWebView: NSViewRepresentable {
    let serverURL: URL
    let currentFilePath: String?

    /// Path to navigate to from LiveReload (--navigateToChanged)
    @Binding var liveReloadNavigatePath: String?
    /// Incremented when LiveReload requests a page refresh
    let reloadTrigger: Int

    /// Navigation action triggers from toolbar buttons
    let goBackTrigger: Int
    let goForwardTrigger: Int
    let refreshTrigger: Int

    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var currentURL: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.canGoBackBinding = $canGoBack
        context.coordinator.canGoForwardBinding = $canGoForward
        context.coordinator.currentURLBinding = $currentURL

        // Allow magnification (pinch to zoom)
        webView.allowsMagnification = true

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Handle LiveReload navigation (from --navigateToChanged)
        if let navigatePath = liveReloadNavigatePath {
            // Clear immediately to prevent re-triggering
            DispatchQueue.main.async {
                liveReloadNavigatePath = nil
            }

            // Skip if already loading to avoid cancellation errors
            if webView.isLoading {
                return
            }

            let navigateURL = serverURL.appendingPathComponent(navigatePath)
            context.coordinator.lastLoadedURL = navigateURL
            let request = URLRequest(url: navigateURL)
            webView.load(request)
            return
        }

        // Handle LiveReload refresh
        if context.coordinator.lastReloadTrigger != reloadTrigger {
            context.coordinator.lastReloadTrigger = reloadTrigger

            // Skip if already loading
            if webView.isLoading {
                return
            }

            webView.reload()
            return
        }

        // Handle toolbar navigation buttons
        if context.coordinator.lastGoBackTrigger != goBackTrigger {
            context.coordinator.lastGoBackTrigger = goBackTrigger
            if webView.canGoBack {
                webView.goBack()
            }
            return
        }

        if context.coordinator.lastGoForwardTrigger != goForwardTrigger {
            context.coordinator.lastGoForwardTrigger = goForwardTrigger
            if webView.canGoForward {
                webView.goForward()
            }
            return
        }

        if context.coordinator.lastRefreshTrigger != refreshTrigger {
            context.coordinator.lastRefreshTrigger = refreshTrigger
            webView.reload()
            return
        }

        // Handle file selection change - only navigate when user selects a different file
        if let filePath = currentFilePath, context.coordinator.currentFilePath != filePath {
            context.coordinator.currentFilePath = filePath

            // Convert content file path to Hugo URL path
            // e.g., content/posts/my-post.md -> /posts/my-post/
            if let hugoPath = convertFilePathToHugoPath(filePath) {
                let targetURL = serverURL.appendingPathComponent(hugoPath)
                context.coordinator.lastLoadedURL = targetURL
                let request = URLRequest(url: targetURL)
                webView.load(request)
            }
        } else if context.coordinator.lastLoadedURL == nil {
            // Initial load - navigate to server root or current file
            var targetURL = serverURL
            if let filePath = currentFilePath {
                context.coordinator.currentFilePath = filePath
                if let hugoPath = convertFilePathToHugoPath(filePath) {
                    targetURL = serverURL.appendingPathComponent(hugoPath)
                }
            }
            context.coordinator.lastLoadedURL = targetURL
            let request = URLRequest(url: targetURL)
            webView.load(request)
        }

        // Update navigation state
        DispatchQueue.main.async {
            canGoBack = webView.canGoBack
            canGoForward = webView.canGoForward
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Convert content file path to Hugo URL path
    /// e.g., content/posts/my-post.md -> /posts/my-post/
    private func convertFilePathToHugoPath(_ filePath: String) -> String? {
        // Remove 'content/' prefix if present
        var path = filePath
        if path.hasPrefix("content/") {
            path = String(path.dropFirst("content/".count))
        }

        // Remove file extension
        if let lastDot = path.lastIndex(of: ".") {
            path = String(path[..<lastDot])
        }

        // Handle index files (_index.md or index.md)
        if path.hasSuffix("/_index") || path.hasSuffix("/index") {
            if let lastSlash = path.lastIndex(of: "/") {
                path = String(path[..<lastSlash])
            }
        } else if path == "_index" || path == "index" {
            path = ""
        }

        // Ensure path starts with /
        if !path.isEmpty && !path.hasPrefix("/") {
            path = "/" + path
        }

        // Hugo expects trailing slash for section pages
        if !path.isEmpty && !path.hasSuffix("/") {
            path += "/"
        }

        return path.isEmpty ? "/" : path
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var lastLoadedURL: URL?
        var currentFilePath: String?
        var lastReloadTrigger: Int = 0
        var lastGoBackTrigger: Int = 0
        var lastGoForwardTrigger: Int = 0
        var lastRefreshTrigger: Int = 0

        var canGoBackBinding: Binding<Bool>?
        var canGoForwardBinding: Binding<Bool>?
        var currentURLBinding: Binding<String>?

        deinit {
            webView?.navigationDelegate = nil
        }

        // Handle navigation decision
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Update navigation state
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.canGoBackBinding?.wrappedValue = webView.canGoBack
                self.canGoForwardBinding?.wrappedValue = webView.canGoForward

                // Update current URL display
                if let url = webView.url?.absoluteString {
                    self.currentURLBinding?.wrappedValue = url
                }
            }
        }

        // Handle navigation errors
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Logger.shared.error("Live preview navigation failed", error: error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Logger.shared.error("Live preview provisional navigation failed", error: error)
        }
    }
}

// MARK: - Preview

#Preview("Running Server") {
    LivePreviewPanel(
        siteViewModel: SiteViewModel(),
        currentFilePath: "content/posts/my-post.md"
    )
    .frame(width: 800, height: 600)
}

#Preview("Server Stopped") {
    LivePreviewPanel(
        siteViewModel: SiteViewModel(),
        currentFilePath: nil
    )
    .frame(width: 800, height: 600)
}
