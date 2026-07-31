import SwiftUI
import AppKit

// MARK: - Editor Save Button

/// Reusable save button with loading indicator
/// Shows a progress spinner when saving is in progress
struct EditorSaveButton: View {
    let isSaving: Bool
    let hasUnsavedChanges: Bool
    let action: () async -> Void

    var body: some View {
        Button {
            Task {
                await action()
            }
        } label: {
            if isSaving {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Image(systemName: "square.and.arrow.down")
            }
        }
        .disabled(!hasUnsavedChanges || isSaving)
        .keyboardShortcut("s", modifiers: .command)
        .help("Save (\u{2318}S)")
        .accessibilityLabel("Save")
        .accessibilityValue(isSaving ? "Saving" : "")
    }
}

// MARK: - Editor Reload Button

/// Reusable reload from disk button
struct EditorReloadButton: View {
    let action: () async -> Void

    var body: some View {
        Button {
            Task {
                await action()
            }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .help("Reload from disk")
        .accessibilityLabel("Reload from Disk")
    }
}

// MARK: - Editor Open External Button

/// Reusable open in external editor button
struct EditorOpenExternalButton: View {
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Image(systemName: "arrow.up.forward.square")
        }
        .help("Open in default app")
        .accessibilityLabel("Open in Default App")
    }
}

// MARK: - Editor Reveal in Finder Button

/// Reusable reveal in Finder button
struct EditorRevealInFinderButton: View {
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } label: {
            Image(systemName: "folder")
        }
        .help("Reveal in Finder")
        .accessibilityLabel("Reveal in Finder")
    }
}

// MARK: - Editor Error Label

/// Inline error text for an editor toolbar. Renders nothing when `message` is nil.
///
/// The accessibility label repeats the "Error:" prefix that sighted users get from the red
/// tint - without it VoiceOver reads the message as ordinary toolbar text.
struct EditorErrorLabel: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(.caption)
                .foregroundStyle(Color.Status.error)
                .accessibilityLabel("Error: \(message)")
        }
    }
}

// MARK: - Editor Toolbar Divider

/// Consistent divider used between toolbar button groups
struct EditorToolbarDivider: View {
    var body: some View {
        Divider()
            .frame(height: 20)
    }
}

// MARK: - Previews

#Preview("Save Button - Normal") {
    HStack {
        EditorSaveButton(isSaving: false, hasUnsavedChanges: true) {
            print("Save")
        }
    }
    .padding()
}

#Preview("Save Button - Saving") {
    HStack {
        EditorSaveButton(isSaving: true, hasUnsavedChanges: true) {
            print("Save")
        }
    }
    .padding()
}

#Preview("Save Button - Disabled") {
    HStack {
        EditorSaveButton(isSaving: false, hasUnsavedChanges: false) {
            print("Save")
        }
    }
    .padding()
}

#Preview("Reload Button") {
    HStack {
        EditorReloadButton {
            print("Reload")
        }
    }
    .padding()
}

#Preview("Open External Button") {
    HStack {
        EditorOpenExternalButton(url: URL(fileURLWithPath: "/tmp/test.txt"))
    }
    .padding()
}

#Preview("Reveal in Finder Button") {
    HStack {
        EditorRevealInFinderButton(url: URL(fileURLWithPath: "/tmp/test.txt"))
    }
    .padding()
}
