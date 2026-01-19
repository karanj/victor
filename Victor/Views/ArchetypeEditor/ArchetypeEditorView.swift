import SwiftUI
import AppKit

/// Editor view for Hugo archetype files with syntax highlighting and help panel
struct ArchetypeEditorView: View {
    @Bindable var archetype: Archetype
    let onSave: () async -> Void

    @State private var isSaving = false
    @State private var showSavedIndicator = false
    @State private var errorMessage: String?
    @State private var showHelpPanel = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HSplitView {
            // Main editor
            VStack(spacing: 0) {
                archetypeToolbar

                Divider()

                TemplateTextView(
                    text: $archetype.rawContent,
                    onTextChange: {
                        // Content changed - handled by Archetype's hasUnsavedChanges
                    }
                )
            }

            // Help panel (collapsible)
            if showHelpPanel {
                ArchetypeHelpPanel()
                    .frame(minWidth: 280, maxWidth: 350)
            }
        }
    }

    // MARK: - Toolbar

    private var archetypeToolbar: some View {
        HStack {
            // Archetype icon and name
            Image(systemName: "doc.text.fill.viewfinder")
                .foregroundStyle(.orange)

            Text(archetype.fileName)
                .font(.headline)

            // Archetype type badge
            Text("Archetype")
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.orange)
                .cornerRadius(4)

            // Format badge
            Text(archetype.frontmatterFormat.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.2))
                .cornerRadius(4)

            // Default badge
            if archetype.isDefault {
                Text("Default")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue)
                    .cornerRadius(4)
            }

            // Status indicator (uses reusable component)
            FileStatusBadgeView(
                hasUnsavedChanges: archetype.hasUnsavedChanges,
                showSavedIndicator: showSavedIndicator
            )

            Spacer()

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Saving indicator
            if isSaving {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Saving...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 20)

            // Help panel toggle
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: AppConstants.Animation.standard)) {
                    showHelpPanel.toggle()
                }
            } label: {
                Image(systemName: showHelpPanel ? "questionmark.circle.fill" : "questionmark.circle")
            }
            .help("Toggle template help panel")

            Divider()
                .frame(height: 20)

            // Save button
            Button {
                Task {
                    await save()
                }
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!archetype.hasUnsavedChanges || isSaving)
            .help("Save (Cmd+S)")

            // Reload button
            Button {
                Task {
                    await reloadFromDisk()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload from disk")

            Divider()
                .frame(height: 20)

            // Open in external editor
            Button {
                NSWorkspace.shared.open(archetype.url)
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .help("Open in default app")

            // Reveal in Finder
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([archetype.url])
            } label: {
                Image(systemName: "folder")
            }
            .help("Reveal in Finder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(reduceMotion ? nil : .easeInOut(duration: AppConstants.Animation.fast), value: archetype.hasUnsavedChanges)
        .animation(reduceMotion ? nil : .easeInOut(duration: AppConstants.Animation.fast), value: showSavedIndicator)
    }

    // MARK: - Actions

    private func save() async {
        isSaving = true
        errorMessage = nil

        do {
            // Write raw content directly to disk
            try archetype.rawContent.write(to: archetype.url, atomically: true, encoding: .utf8)
            archetype.markAsSaved()
            await onSave()
            showSavedIndicator = true

            // Hide saved indicator after delay
            try? await Task.sleep(for: .seconds(2))
            showSavedIndicator = false
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }

        isSaving = false
    }

    private func reloadFromDisk() async {
        do {
            let content = try String(contentsOf: archetype.url, encoding: .utf8)
            archetype.rawContent = content
            archetype.markAsSaved()
        } catch {
            errorMessage = "Reload failed: \(error.localizedDescription)"
        }
    }
}
