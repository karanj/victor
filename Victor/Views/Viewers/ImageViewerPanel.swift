import SwiftUI
import AppKit

/// Panel for viewing image files
struct ImageViewerPanel: View {
    let url: URL

    @State private var image: NSImage?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var zoomLevel: Double = 1.0

    // Zoom range
    private let minZoom: Double = 0.1
    private let maxZoom: Double = 5.0

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            imageToolbar

            Divider()

            // Image content
            if isLoading {
                ProgressView("Loading image...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let image = image {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoomLevel)
                        .frame(
                            width: image.size.width * zoomLevel,
                            height: image.size.height * zoomLevel
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            await loadImage()
        }
    }

    private var imageToolbar: some View {
        HStack {
            // File name
            Text(url.lastPathComponent)
                .font(.headline)

            Spacer()

            // Image dimensions (if loaded)
            if let image = image {
                Text("\(Int(image.size.width)) × \(Int(image.size.height))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 20)

            // Zoom controls
            Button {
                zoomLevel = max(minZoom, zoomLevel - 0.25)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(zoomLevel <= minZoom)

            Text("\(Int(zoomLevel * 100))%")
                .frame(width: 50)
                .font(.caption.monospacedDigit())

            Button {
                zoomLevel = min(maxZoom, zoomLevel + 0.25)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(zoomLevel >= maxZoom)

            Button {
                zoomLevel = 1.0
            } label: {
                Text("100%")
                    .font(.caption)
            }

            Divider()
                .frame(height: 20)

            // Open in external app
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .help("Open in Preview")

            // Reveal in Finder
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "folder")
            }
            .help("Reveal in Finder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func loadImage() async {
        isLoading = true
        errorMessage = nil

        do {
            // Load image on background thread
            let loadedImage = try await Task.detached {
                guard let image = NSImage(contentsOf: url) else {
                    throw ImageError.failedToLoad
                }
                return image
            }.value

            await MainActor.run {
                self.image = loadedImage
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load image: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
}

enum ImageError: LocalizedError {
    case failedToLoad

    var errorDescription: String? {
        switch self {
        case .failedToLoad:
            return "Could not load the image file."
        }
    }
}
