import SwiftUI
import WebKit

/// Live preview panel that displays Hugo server output in a WKWebView
/// Replaces the markdown-only preview when Hugo server is running
struct LivePreviewPanel: View {
    let siteViewModel: SiteViewModel
    let currentFilePath: String?
    let permalinkResolver: PermalinkResolver
    let currentDate: Date?
    let currentSlug: String?

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
                        permalinkResolver: permalinkResolver,
                        currentDate: currentDate,
                        currentSlug: currentSlug,
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
    let permalinkResolver: PermalinkResolver
    let currentDate: Date?
    let currentSlug: String?

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

            let hugoPath = permalinkResolver.resolveURL(
                filePath: filePath, date: currentDate, slug: currentSlug
            )
            let targetURL = serverURL.appendingPathComponent(hugoPath)
            context.coordinator.lastLoadedURL = targetURL
            let request = URLRequest(url: targetURL)
            webView.load(request)
        } else if context.coordinator.lastLoadedURL == nil {
            // Initial load - navigate to server root or current file
            var targetURL = serverURL
            if let filePath = currentFilePath {
                context.coordinator.currentFilePath = filePath
                let hugoPath = permalinkResolver.resolveURL(
                    filePath: filePath, date: currentDate, slug: currentSlug
                )
                targetURL = serverURL.appendingPathComponent(hugoPath)
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

    // MARK: - Coordinator

    // `@MainActor`: `WKNavigationDelegate.webView(_:decidePolicyFor:decisionHandler:)`
    // is itself declared `@MainActor` in the SDK (WP3.5 Cluster 10) - matching
    // that exactly is what the signature-drift warning below needs.
    @MainActor
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

        // No deinit nil-out needed: `WKWebView.navigationDelegate` is `weak`
        // in WebKit, so it already clears itself automatically when this
        // Coordinator deallocates. A synchronous `deinit` can't touch
        // `@MainActor` state anyway (WP3.5 Cluster 11, applied here per its
        // own prose note even though this file isn't in Cluster 11's file
        // list - the same pattern, an apparent gap in the memo's file
        // enumeration).

        // Handle navigation decision
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
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
        currentFilePath: "content/posts/my-post.md",
        permalinkResolver: PermalinkResolver(permalinks: [:]),
        currentDate: nil,
        currentSlug: nil
    )
    .frame(width: 800, height: 600)
}

#Preview("Server Stopped") {
    LivePreviewPanel(
        siteViewModel: SiteViewModel(),
        currentFilePath: nil,
        permalinkResolver: PermalinkResolver(permalinks: [:]),
        currentDate: nil,
        currentSlug: nil
    )
    .frame(width: 800, height: 600)
}
