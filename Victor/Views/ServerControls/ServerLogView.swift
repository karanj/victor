import SwiftUI

/// Server output log view showing Hugo server console output
struct ServerLogView: View {
    @State private var logLines: [String] = []
    @State private var autoScroll = true

    /// ScrollView proxy for auto-scrolling
    @Namespace private var bottomID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            Divider()

            // Log content
            logContent
        }
        .frame(minWidth: 400, minHeight: 300)
        .task {
            await observeServerOutput()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Text("Server Log")
                .font(.headline)

            Spacer()

            // Auto-scroll toggle
            Toggle(isOn: $autoScroll) {
                Label("Auto-scroll", systemImage: "arrow.down.to.line")
                    .labelStyle(.iconOnly)
            }
            .toggleStyle(.button)
            .help("Auto-scroll to bottom")
            .accessibilityLabel("Auto-scroll")
            .accessibilityHint("Automatically scroll to bottom when new log entries appear")

            // Copy log button
            Button {
                copyLogToClipboard()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .labelStyle(.iconOnly)
            }
            .help("Copy log to clipboard")
            .accessibilityLabel("Copy log")
            .accessibilityHint("Copy all log entries to clipboard")

            // Clear log button
            Button {
                clearLog()
            } label: {
                Label("Clear", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .help("Clear log")
            .accessibilityLabel("Clear log")
            .accessibilityHint("Remove all log entries")
        }
        .padding(8)
    }

    // MARK: - Log Content

    private var logContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if logLines.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(logLines.enumerated()), id: \.offset) { index, line in
                            logLineView(line: line, index: index)
                        }

                        // Invisible anchor for auto-scrolling
                        Color.clear
                            .frame(height: 1)
                            .id(bottomID)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: logLines.count) { _, _ in
                if autoScroll {
                    withAnimation(reduceMotion ? nil : .default) {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("No server output yet")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Start the Hugo server to see output here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Log Line View

    private func logLineView(line: String, index: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Line number
            Text("\(index + 1)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 50, alignment: .trailing)
                .padding(.leading, 8)

            // Log line with syntax coloring
            Text(line)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(colorForLine(line))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
        }
        .padding(.vertical, 2)
        .background(
            index % 2 == 0
                ? Color(nsColor: .textBackgroundColor)
                : Color(nsColor: .controlBackgroundColor).opacity(0.3)
        )
    }

    // MARK: - Line Coloring

    private func colorForLine(_ line: String) -> Color {
        // Color based on log level
        let uppercased = line.uppercased()

        if uppercased.contains("ERROR") || uppercased.contains("FATAL") {
            return .red
        } else if uppercased.contains("WARN") {
            return .orange
        } else if uppercased.contains("CHANGE DETECTED") || uppercased.contains("REBUILDING") {
            return .blue
        } else if uppercased.contains("WEB SERVER IS AVAILABLE") {
            return .green
        } else {
            return .primary
        }
    }

    // MARK: - Actions

    /// Independent stream consumer (WP3.5 Cluster 9 / M2). `ServerLogView` opens
    /// in its own `Window` scene with no `SiteViewModel` in its environment
    /// (`VictorApp.swift`), so it observes `HugoServerService` directly rather
    /// than through `SiteViewModel` - same shape as the other three consumers,
    /// just not routed through it. Replay-on-subscribe means a freshly-opened
    /// Server Logs window (opened after the server already started) still
    /// shows the current output, without a separate initial-fetch.
    private func observeServerOutput() async {
        for await newOutput in await HugoServerService.shared.outputUpdates() {
            logLines = newOutput
        }
    }

    private func clearLog() {
        // Note: This only clears the UI, not the service's log
        // In a future version, we could add a clearOutput() method to the service
        logLines = []
    }

    private func copyLogToClipboard() {
        let logText = logLines.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(logText, forType: .string)
    }
}

// MARK: - Preview

#Preview("Empty Log") {
    ServerLogView()
}

#Preview("With Content") {
    struct PreviewWrapper: View {
        @State private var lines = [
            "Start building sites ...",
            "hugo v0.121.1-00b46fed8e47f7bb0a85d7cfc2d9f1356379dca5+extended darwin/arm64 BuildDate=2023-12-08T08:47:45Z VendorInfo=gohugoio",
            "",
            "                   | EN",
            "-------------------+-----",
            "  Pages            |  24",
            "  Paginator pages  |   0",
            "  Non-page files   |   8",
            "  Static files     |  12",
            "  Processed images |   0",
            "  Aliases          |   3",
            "  Sitemaps         |   1",
            "  Cleaned          |   0",
            "",
            "Built in 123 ms",
            "Watching for changes in /Users/victor/mysite/{archetypes,content,data,layouts,static}",
            "Watching for config changes in /Users/victor/mysite/hugo.toml",
            "Environment: \"development\"",
            "Serving pages from memory",
            "Running in Fast Render Mode. For full rebuilds on change: hugo server --disableFastRender",
            "Web Server is available at http://localhost:1313/ (bind address 127.0.0.1)",
            "Press Ctrl+C to stop"
        ]

        var body: some View {
            ServerLogView()
                .onAppear {
                    Task {
                        for await _ in await HugoServerService.shared.outputUpdates() {
                            // Preview version
                        }
                    }
                }
        }
    }

    return PreviewWrapper()
}
