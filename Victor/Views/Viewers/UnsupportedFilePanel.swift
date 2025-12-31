import SwiftUI
import AppKit

/// Panel shown for unsupported file types
struct UnsupportedFilePanel: View {
    let url: URL
    let fileType: FileType

    @State private var fileSize: String = "Unknown"
    @State private var modificationDate: String = "Unknown"

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // File icon
            Image(systemName: fileType.systemImage)
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            // File name
            Text(url.lastPathComponent)
                .font(.title2)
                .fontWeight(.medium)

            // File info
            VStack(spacing: 8) {
                HStack {
                    Text("Type:")
                        .foregroundStyle(.secondary)
                    Text(fileType.displayName)
                }
                HStack {
                    Text("Size:")
                        .foregroundStyle(.secondary)
                    Text(fileSize)
                }
                HStack {
                    Text("Modified:")
                        .foregroundStyle(.secondary)
                    Text(modificationDate)
                }
            }
            .font(.callout)

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open in Default App", systemImage: "arrow.up.forward.square")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            loadFileInfo()
        }
    }

    private func loadFileInfo() {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)

            // File size
            if let size = attributes[.size] as? Int64 {
                fileSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }

            // Modification date
            if let date = attributes[.modificationDate] as? Date {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                modificationDate = formatter.string(from: date)
            }
        } catch {
            // Keep defaults
        }
    }
}
