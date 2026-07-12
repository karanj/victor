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
                .foregroundStyle(Color.FileIcon.config)
                .accessibilityHidden(true)

            Text(archetype.fileName)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

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
                    .foregroundStyle(Color.Status.error)
                    .accessibilityLabel("Error: \(error)")
            }

            EditorToolbarDivider()

            // Help panel toggle
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: AppConstants.Animation.standard)) {
                    showHelpPanel.toggle()
                }
            } label: {
                Image(systemName: showHelpPanel ? "questionmark.circle.fill" : "questionmark.circle")
            }
            .help("Toggle template help panel")
            .accessibilityLabel("Template Help")
            .accessibilityValue(showHelpPanel ? "Shown" : "Hidden")

            EditorToolbarDivider()

            EditorSaveButton(
                isSaving: isSaving,
                hasUnsavedChanges: archetype.hasUnsavedChanges,
                action: save
            )

            EditorReloadButton(action: reloadFromDisk)

            EditorToolbarDivider()

            EditorOpenExternalButton(url: archetype.url)
            EditorRevealInFinderButton(url: archetype.url)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(reduceMotion ? nil : .easeInOut(duration: AppConstants.Animation.fast), value: archetype.hasUnsavedChanges)
        .animation(reduceMotion ? nil : .easeInOut(duration: AppConstants.Animation.fast), value: showSavedIndicator)
    }

    // MARK: - Actions

    private func save() async {
        let helper = EditorSaveHelper()
        await helper.performSave(
            to: archetype.url,
            content: { archetype.rawContent },
            isSaving: { isSaving },
            setIsSaving: { isSaving = $0 },
            showSavedIndicator: { showSavedIndicator },
            setShowSavedIndicator: { showSavedIndicator = $0 },
            errorMessage: { errorMessage },
            setErrorMessage: { errorMessage = $0 },
            markAsSaved: { archetype.markAsSaved() },
            afterSave: { await onSave() }
        )
    }

    private func reloadFromDisk() async {
        let helper = EditorReloadHelper()
        await helper.performReload(
            from: archetype.url,
            updateContent: { archetype.rawContent = $0 },
            errorMessage: { errorMessage },
            setErrorMessage: { errorMessage = $0 },
            markAsSaved: { archetype.markAsSaved() }
        )
    }
}
