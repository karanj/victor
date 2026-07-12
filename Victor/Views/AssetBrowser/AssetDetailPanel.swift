import SwiftUI
import AppKit
import QuickLook

/// Detail panel showing asset info and actions
struct AssetDetailPanel: View {
    let asset: Asset
    let onInsert: ((String) -> Void)?

    @State private var copyFeedback: String?
    @State private var quickLookURL: URL?
    @State private var copyFeedbackTask: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Details")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Preview
                    previewSection

                    // Filename
                    detailSection("Filename") {
                        Text(asset.url.lastPathComponent)
                            .font(.body)
                            .textSelection(.enabled)
                    }

                    // Path
                    detailSection("Path") {
                        Text(asset.relativePath)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    // Dimensions (for images)
                    if let dims = asset.formattedDimensions {
                        detailSection("Dimensions") {
                            Text("\(dims) pixels")
                        }
                    }

                    // File size
                    detailSection("Size") {
                        Text(asset.formattedFileSize)
                    }

                    // Modification date
                    if let date = asset.modificationDate {
                        detailSection("Modified") {
                            Text(date, style: .date)
                            Text(date, style: .time)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Location
                    detailSection("Location") {
                        Text(asset.locationDescription)
                    }

                    Divider()

                    // Insert buttons
                    insertSection

                    Divider()

                    // Action buttons
                    actionSection
                }
                .padding()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .quickLookPreview($quickLookURL)
    }

    // MARK: - Preview Section

    @ViewBuilder
    private var previewSection: some View {
        if let thumbnail = asset.thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 200)
                .cornerRadius(4)
                .frame(maxWidth: .infinity)
        } else {
            // Show file type icon for non-images
            VStack(spacing: 8) {
                Image(systemName: asset.fileType.systemImage)
                    .font(.system(size: 48))
                    .foregroundStyle(asset.fileType.defaultColor)
                Text(asset.fileType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(height: 100)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(4)
        }
    }

    // MARK: - Insert Section

    private var insertSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Insert into content")
                .font(.caption)
                .foregroundStyle(.secondary)

            if asset.fileType == .image {
                Button {
                    if let onInsert = onInsert {
                        onInsert(asset.markdownSyntax)
                    } else {
                        copyToClipboard(asset.markdownSyntax)
                    }
                } label: {
                    Label(
                        onInsert != nil ? "Insert Markdown" : "Copy Markdown",
                        systemImage: "photo"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)

                Button {
                    if let onInsert = onInsert {
                        onInsert(asset.figureShortcode)
                    } else {
                        copyToClipboard(asset.figureShortcode)
                    }
                } label: {
                    Label(
                        onInsert != nil ? "Insert Figure" : "Copy Figure",
                        systemImage: "text.below.photo"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }

            Button {
                let path = asset.isInAssetsDir ? asset.relativePath : "/\(asset.relativePath)"
                copyToClipboard(path)
            } label: {
                Label("Copy Path", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            // Copy feedback
            if let feedback = copyFeedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(Color.Status.saved)
                    .transition(.opacity)
                    .accessibilityLabel("Copied to clipboard")
            }
        }
        // The feedback Text above is transient and easy to miss visually;
        // announce it explicitly since there's no focus change to carry it
        // to a screen reader otherwise.
        .onChange(of: copyFeedback) { _, newValue in
            if newValue != nil {
                AccessibilityNotification.Announcement("Copied to clipboard").post()
            }
        }
    }

    // MARK: - Action Section

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button {
                    NSWorkspace.shared.open(asset.url)
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.square")
                }
                .buttonStyle(.bordered)
                .help("Open in default app")

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([asset.url])
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .help("Reveal in Finder")

                ShareLink(item: asset.url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .help("Share this file")
            }

            // Quick Look preview
            Button {
                quickLookURL = asset.url
            } label: {
                Label("Quick Look", systemImage: "eye")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.space, modifiers: [])
        }
    }

    // MARK: - Helper Views

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: - Actions

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Show feedback
        withAnimation(reduceMotion ? nil : .default) {
            copyFeedback = "Copied!"
        }

        // Clear feedback after delay - cancellable so a re-copy resets the timer
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .default) {
                copyFeedback = nil
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let asset = Asset(
        url: URL(fileURLWithPath: "/test/image.png"),
        relativePath: "images/image.png",
        isInAssetsDir: false
    )

    return AssetDetailPanel(asset: asset, onInsert: nil)
        .frame(width: 280, height: 600)
}
