import SwiftUI

/// Shared popover content for displaying Hugo build errors and warnings
/// Used by both ServerControlView (toolbar badge) and LivePreviewPanel (floating badge)
struct BuildIssuesPopover: View {
    let errors: [HugoBuildError]
    let onFileClick: ((String) -> Void)?
    let onDismiss: (() -> Void)?

    // MARK: - Computed Properties

    private var hasActualErrors: Bool {
        errors.contains { $0.level == .error }
    }

    private var errorCount: Int {
        errors.filter { $0.level == .error }.count
    }

    private var warningCount: Int {
        errors.filter { $0.level == .warning }.count
    }

    private var headerTitle: String {
        if hasActualErrors {
            return "Build Errors (\(errorCount))"
        } else {
            return "Build Warnings (\(warningCount))"
        }
    }

    private var headerIcon: String {
        hasActualErrors ? "xmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var headerColor: Color {
        hasActualErrors ? .red : .orange
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            header

            Divider()

            // Issue list
            if errors.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(errors) { error in
                            IssueRow(error: error, onFileClick: onFileClick)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 450, height: 350)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: headerIcon)
                .foregroundStyle(headerColor)
            Text(headerTitle)
                .font(.headline)
            Spacer()

            if let onDismiss = onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Text("No issues")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
    }
}

// MARK: - Issue Row

/// Row view for a single build error or warning
private struct IssueRow: View {
    let error: HugoBuildError
    let onFileClick: ((String) -> Void)?

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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // Level icon
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .font(.system(size: 12))

                // File path if available - clickable
                if let filePath = error.clickableFilePath {
                    if let onFileClick = onFileClick {
                        Button {
                            onFileClick(filePath)
                        } label: {
                            HStack(spacing: 4) {
                                Text(filePath)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.blue)

                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.blue.opacity(0.7))
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Open file in editor")
                    } else {
                        Text(filePath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.blue)
                    }
                }

                Spacer()

                // Timestamp
                Text(error.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Error message
            Text(error.message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

// MARK: - Previews

#Preview("Build Errors") {
    BuildIssuesPopover(
        errors: [
            HugoBuildError(
                level: .error,
                message: "Template execution failed: template: _default/single.html:10:5",
                file: "layouts/_default/single.html",
                line: 10,
                timestamp: Date()
            ),
            HugoBuildError(
                level: .error,
                message: "Error building site: failed to render pages",
                file: nil,
                line: nil,
                timestamp: Date().addingTimeInterval(-5)
            )
        ],
        onFileClick: { path in
            print("Clicked: \(path)")
        },
        onDismiss: {
            print("Dismissed")
        }
    )
}

#Preview("Warnings Only") {
    BuildIssuesPopover(
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
        onFileClick: nil,
        onDismiss: nil
    )
}

#Preview("Mixed Issues") {
    BuildIssuesPopover(
        errors: [
            HugoBuildError(
                level: .error,
                message: "Template execution failed",
                file: "layouts/single.html",
                line: 15,
                timestamp: Date()
            ),
            HugoBuildError(
                level: .warning,
                message: "Deprecated feature used",
                file: nil,
                line: nil,
                timestamp: Date().addingTimeInterval(-10)
            )
        ],
        onFileClick: { path in
            print("Clicked: \(path)")
        },
        onDismiss: {
            print("Dismissed")
        }
    )
}
