import SwiftUI
import WebKit

/// NSViewRepresentable wrapper around WKWebView for displaying HTML preview
/// Note: WKProcessPool sharing is NOT needed - it was deprecated in macOS 12.0 and
/// process pooling is now automatic. Do not add manual WKProcessPool management.
struct PreviewWebView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        // Configure for local content - transparent background using setValue (KVC)
        // Note: WKWebView.isOpaque is read-only, so we still need to use KVC here
        webView.setValue(false, forKey: "drawsBackground")

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Only update if HTML has changed
        if context.coordinator.currentHTML != html {
            context.coordinator.currentHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        var currentHTML: String = ""
        weak var webView: WKWebView?

        deinit {
            webView?.navigationDelegate = nil
        }

        // Handle navigation
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow initial load
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
                return
            }

            // For link clicks, open in default browser
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        // Handle navigation errors
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Logger.shared.error("Preview web view navigation failed", error: error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Logger.shared.error("Preview web view provisional navigation failed", error: error)
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleHTML = """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="UTF-8">
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
                padding: 20px;
                line-height: 1.6;
            }
            h1 { color: #333; }
            code {
                background-color: #f6f8fa;
                padding: 2px 6px;
                border-radius: 3px;
                font-family: monospace;
            }
        </style>
    </head>
    <body>
        <h1>Preview Test</h1>
        <p>This is a <strong>sample</strong> preview with <code>code</code>.</p>
        <ul>
            <li>Item 1</li>
            <li>Item 2</li>
            <li>Item 3</li>
        </ul>
    </body>
    </html>
    """

    return PreviewWebView(html: sampleHTML)
        .frame(width: 600, height: 400)
}
