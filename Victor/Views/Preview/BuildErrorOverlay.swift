import SwiftUI

/// Semi-transparent overlay that shows Hugo build errors over the live preview
/// Appears when build fails with detailed error information
struct BuildErrorOverlay: View {
    let errors: [HugoBuildError]
    let onDismiss: () -> Void
    let onFileClick: (String) -> Void

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            // Error panel
            VStack(spacing: 0) {
                // Header
                errorHeader

                Divider()

                // Error list
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(errors) { error in
                            ErrorRow(error: error, onFileClick: onFileClick)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 400)

                // Footer with dismiss button
                errorFooter
            }
            .frame(maxWidth: 700)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        }
    }

    // MARK: - Header

    private var errorHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: errorIconName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("Build Failed")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(errorCountText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Dismiss and show stale preview")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(errorHeaderColor)
    }

    private var errorIconName: String {
        let hasErrors = errors.contains { $0.level == .error }
        return hasErrors ? "xmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var errorHeaderColor: Color {
        let hasErrors = errors.contains { $0.level == .error }
        return hasErrors ? Color.red : Color.orange
    }

    private var errorCountText: String {
        let errorCount = errors.filter { $0.level == .error }.count
        let warningCount = errors.filter { $0.level == .warning }.count

        var parts: [String] = []
        if errorCount > 0 {
            parts.append("\(errorCount) \(errorCount == 1 ? "error" : "errors")")
        }
        if warningCount > 0 {
            parts.append("\(warningCount) \(warningCount == 1 ? "warning" : "warnings")")
        }

        return parts.joined(separator: ", ")
    }

    // MARK: - Footer

    private var errorFooter: some View {
        HStack {
            Text("Fix the errors above and Hugo will automatically rebuild")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Dismiss") {
                onDismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Error Row

private struct ErrorRow: View {
    let error: HugoBuildError
    let onFileClick: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Error level icon
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 6) {
                // File path (if available) - clickable
                if let filePath = error.clickableFilePath {
                    Button {
                        onFileClick(filePath)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 11))

                            Text(filePath)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.blue)

                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9))
                                .foregroundStyle(.blue.opacity(0.7))
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Open file in editor")
                }

                // Error message
                Text(error.message)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                // Timestamp
                Text(formatTimestamp(error.timestamp))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var iconName: String {
        switch error.level {
        case .error:
            return "xmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle.fill"
        }
    }

    private var iconColor: Color {
        switch error.level {
        case .error:
            return .red
        case .warning:
            return .orange
        case .info:
            return .blue
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview("Build Errors") {
    BuildErrorOverlay(
        errors: [
            HugoBuildError(
                level: .error,
                message: "Template execution failed: template: _default/single.html:10:5: executing \"_default/single.html\" at <.Title>: can't evaluate field Title",
                file: "layouts/_default/single.html",
                line: 10,
                timestamp: Date()
            ),
            HugoBuildError(
                level: .error,
                message: "Error building site: failed to render pages: render of \"page\" failed",
                file: nil,
                line: nil,
                timestamp: Date().addingTimeInterval(-5)
            ),
            HugoBuildError(
                level: .warning,
                message: "found no layout file for \"HTML\" for kind \"home\"",
                file: nil,
                line: nil,
                timestamp: Date().addingTimeInterval(-10)
            )
        ],
        onDismiss: {
            print("Dismissed")
        },
        onFileClick: { path in
            print("Clicked: \(path)")
        }
    )
    .frame(width: 900, height: 700)
}

#Preview("Single Error") {
    BuildErrorOverlay(
        errors: [
            HugoBuildError(
                level: .error,
                message: "Error building site: TOML parsing error at line 5: invalid character '=' in key",
                file: "config.toml",
                line: 5,
                timestamp: Date()
            )
        ],
        onDismiss: {
            print("Dismissed")
        },
        onFileClick: { path in
            print("Clicked: \(path)")
        }
    )
    .frame(width: 900, height: 700)
}

#Preview("Warnings Only") {
    BuildErrorOverlay(
        errors: [
            HugoBuildError(
                level: .warning,
                message: "found no layout file for \"HTML\" for kind \"home\"",
                file: nil,
                line: nil,
                timestamp: Date()
            ),
            HugoBuildError(
                level: .warning,
                message: "found no layout file for \"HTML\" for kind \"section\"",
                file: nil,
                line: nil,
                timestamp: Date().addingTimeInterval(-2)
            )
        ],
        onDismiss: {
            print("Dismissed")
        },
        onFileClick: { path in
            print("Clicked: \(path)")
        }
    )
    .frame(width: 900, height: 700)
}
