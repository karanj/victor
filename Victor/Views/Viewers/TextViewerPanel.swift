import SwiftUI
import AppKit

/// Panel for viewing text files (read-only initially, editable in Phase 3)
struct TextViewerPanel: View {
    let url: URL
    let fileType: FileType

    @State private var content: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            textToolbar

            Divider()

            // Content
            if isLoading {
                LoadingStateView(message: "Loading file...")
            } else if let errorMessage = errorMessage {
                ErrorStateView(
                    title: "Failed to Load File",
                    message: errorMessage
                )
            } else {
                ScrollView {
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .task {
            await loadContent()
        }
    }

    private var textToolbar: some View {
        HStack {
            // File type icon
            Image(systemName: fileType.systemImage)
                .foregroundStyle(fileType.defaultColor)
                .accessibilityHidden(true)

            // File name
            Text(url.lastPathComponent)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            // File type badge
            Text(fileType.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.2))
                .cornerRadius(4)

            Spacer()

            // Line count
            if !content.isEmpty {
                let lineCount = content.components(separatedBy: .newlines).count
                Text("\(lineCount) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 20)

            // Open in external editor
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .help("Open in default app")
            .accessibilityLabel("Open in Default App")

            // Reveal in Finder
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "folder")
            }
            .help("Reveal in Finder")
            .accessibilityLabel("Reveal in Finder")

            // Copy path
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(url.path, forType: .string)
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .help("Copy file path")
            .accessibilityLabel("Copy File Path")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func loadContent() async {
        isLoading = true
        errorMessage = nil

        do {
            // `readFileContentsOffActor` (shared `nonisolated` + `@concurrent` helper)
            // replaces `Task.detached` here (victor-tdt audit) - `@concurrent` on the
            // helper compiler-pins the blocking read off whatever actor this SwiftUI
            // `View`'s method runs on.
            let loadedContent = try await readFileContentsOffActor(at: url)

            await MainActor.run {
                self.content = loadedContent
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load file: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
}
