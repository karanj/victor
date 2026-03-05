import SwiftUI
import AppKit

/// Reusable empty state view component
/// Provides a consistent way to display empty states across the application
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var action: (() -> Void)? = nil
    var actionLabel: String? = nil
    var actionIcon: String? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        } actions: {
            if let action, let actionLabel {
                Button {
                    action()
                } label: {
                    if let actionIcon {
                        Label(actionLabel, systemImage: actionIcon)
                    } else {
                        Text(actionLabel)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Convenience Initializers

extension EmptyStateView {
    /// Simple empty state without action button
    init(icon: String, title: String, message: String) {
        self.icon = icon
        self.title = title
        self.message = message
        self.action = nil
        self.actionLabel = nil
        self.actionIcon = nil
    }

    /// Empty state with action button
    init(icon: String, title: String, message: String, actionLabel: String, actionIcon: String? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.message = message
        self.action = action
        self.actionLabel = actionLabel
        self.actionIcon = actionIcon
    }
}

// MARK: - Loading State View

/// Reusable loading state with centered spinner and message
struct LoadingStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Error State View

/// Reusable error state with icon, title, message, and optional retry/open actions
struct ErrorStateView: View {
    let title: String
    let message: String
    var retryAction: (() -> Void)? = nil
    var openURL: URL? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let retryAction {
                Button("Retry") { retryAction() }
                    .buttonStyle(.borderedProminent)
                    .padding(.top)
            }
            if let openURL {
                Button("Open in Default App") { NSWorkspace.shared.open(openURL) }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview("No Action") {
    EmptyStateView(
        icon: "doc.text",
        title: "No File Selected",
        message: "Select a file to view its metadata"
    )
}

#Preview("With Action") {
    EmptyStateView(
        icon: "server.rack",
        title: "Hugo Server Not Running",
        message: "Start the Hugo development server to see live preview of your site.",
        actionLabel: "Start Server",
        actionIcon: "play.fill"
    ) {
        print("Start server")
    }
}
