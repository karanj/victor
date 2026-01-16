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
                        canGoBack: $canGoBack,
                        canGoForward: $canGoForward,
                        currentURL: $currentURL,
                        onNavigate: { }
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
                // Web view will handle navigation
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(canGoBack ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canGoBack)
            .help("Go back")

            // Forward button
            Button {
                // Web view will handle navigation
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(canGoForward ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canGoForward)
            .help("Go forward")

            // Refresh button
            Button {
                // Web view will handle refresh
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh")

            Divider()
                .frame(height: 16)

            // URL display
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))

                Text(currentURL.isEmpty ? serverURL?.absoluteString ?? "" : currentURL)
                    .font(.system(size: 11))
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
                    .font(.system(size: 11))
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
        ContentUnavailableView {
            Label("Hugo Server Not Running", systemImage: "server.rack")
        } description: {
            VStack(spacing: 12) {
                Text("Start the Hugo development server to see live preview of your site.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                // TODO: Add start server button when ServerControlPanel is implemented
                // Button("Start Server") {
                //     Task {
                //         try? await HugoServerService.shared.start(siteURL: siteViewModel.site!.rootURL)
                //     }
                // }
                // .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Server State Management

    private func setupServerStateObservers() {
        Task {
            await HugoServerService.shared.setOnStatusChange { @MainActor newStatus in
                status = newStatus
            }
        }
    }

    private func refreshServerState() async {
        let currentStatus = await HugoServerService.shared.status
        let currentServerURL = await HugoServerService.shared.serverURL

        await MainActor.run {
            status = currentStatus
            serverURL = currentServerURL
        }
    }
}

// MARK: - Live Preview WebView

private struct LivePreviewWebView: NSViewRepresentable {
    let serverURL: URL
    let currentFilePath: String?

    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var currentURL: String
    let onNavigate: () -> Void

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
        // Build target URL
        var targetURL = serverURL

        // If we have a current file path, try to navigate to it
        if let filePath = currentFilePath, context.coordinator.currentFilePath != filePath {
            context.coordinator.currentFilePath = filePath

            // Convert content file path to Hugo URL path
            // e.g., content/posts/my-post.md -> /posts/my-post/
            if let hugoPath = convertFilePathToHugoPath(filePath) {
                targetURL = serverURL.appendingPathComponent(hugoPath)
            }
        }

        // Only load if URL has changed
        if context.coordinator.lastLoadedURL != targetURL {
            context.coordinator.lastLoadedURL = targetURL
            let request = URLRequest(url: targetURL)
            webView.load(request)
            Logger.shared.debug("[LivePreview] Loading URL: \(targetURL.absoluteString)")
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

        var canGoBackBinding: Binding<Bool>?
        var canGoForwardBinding: Binding<Bool>?
        var currentURLBinding: Binding<String>?

        deinit {
            webView?.navigationDelegate = nil
        }

        // Handle navigation
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow all navigation within the Hugo server
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
