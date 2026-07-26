import SwiftUI

// MARK: - Tab Bar View

/// Tab bar for switching between Editor, Preview, and Split layout modes
struct TabBarView: View {
    @Bindable var viewModel: SiteViewModel
    @Bindable private var settings = AppSettings.shared

    @State private var isBuildIssuesPopoverPresented = false

    var body: some View {
        HStack {
            Picker("Layout Mode", selection: $settings.layoutMode) {
                ForEach(EditorLayoutMode.allCases, id: \.self) { mode in
                    Label(mode.displayName, systemImage: mode.iconName)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            .help("Switch between Editor, Preview, and Split views")

            Spacer()

            // Build issues pill: passive surface for Hugo build errors/warnings.
            // Deliberately never auto-presents anything - it replaced
            // ServerControlView's auto-showing popover, which interrupted on
            // every new batch of errors. Count + latest message, details on click.
            if !viewModel.hugoBuildErrors.isEmpty {
                buildIssuesPill
            }

            // Not gated on the server running: with it stopped, "Live Server" routes to
            // LivePreviewPanel's placeholder, which offers to start it. A labelled segmented
            // control rather than a pill, which read as a status chip.
            if settings.layoutMode != .editor {
                previewSourcePicker
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Build Issues Pill

    private var hasActualErrors: Bool {
        viewModel.hugoBuildErrors.contains { $0.level == .error }
    }

    private var buildIssuesPill: some View {
        Button {
            isBuildIssuesPopoverPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: hasActualErrors ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.caption)
                    .accessibilityHidden(true)
                Text("\(viewModel.hugoBuildErrors.count)")
                    .font(.caption.bold())
                if let latest = viewModel.hugoBuildErrors.last {
                    Text(latest.message)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 280, alignment: .leading)
                }
            }
            .foregroundStyle(hasActualErrors ? Color.red : Color.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill((hasActualErrors ? Color.red : Color.orange).opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(hasActualErrors ? Color.red : Color.orange, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Hugo reported \(viewModel.hugoBuildErrors.count) build issue\(viewModel.hugoBuildErrors.count == 1 ? "" : "s") - click for details")
        .accessibilityLabel("\(viewModel.hugoBuildErrors.count) build \(hasActualErrors ? "error" : "warning")\(viewModel.hugoBuildErrors.count == 1 ? "" : "s")")
        .popover(isPresented: $isBuildIssuesPopoverPresented) {
            BuildIssuesPopover(
                errors: viewModel.hugoBuildErrors,
                onFileClick: nil,
                onDismiss: { isBuildIssuesPopoverPresented = false }
            )
        }
    }

    // MARK: - Preview Source Picker

    /// Labelled segmented control choosing what the preview pane renders:
    /// this app's own markdown rendering, or the running Hugo server's output.
    private var previewSourcePicker: some View {
        HStack(spacing: 6) {
            Text("Preview:")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Preview Source", selection: $viewModel.useLivePreview) {
                Text("Markdown").tag(false)
                Text("Hugo Server").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .help("Choose the preview pane's source: Victor's rendered markdown, or the live site from the Hugo development server")
        .accessibilityLabel("Preview source")
    }
}

#Preview {
    TabBarView(viewModel: SiteViewModel())
        .frame(width: 600)
}
