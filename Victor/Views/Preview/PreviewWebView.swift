import SwiftUI
import WebKit

/// NSViewRepresentable wrapper around WKWebView for displaying HTML preview
struct PreviewWebView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator

        // Configure for local content
        webView.setValue(false, forKey: "drawsBackground") // Transparent background

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
            print("Preview web view navigation failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("Preview web view provisional navigation failed: \(error.localizedDescription)")
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
