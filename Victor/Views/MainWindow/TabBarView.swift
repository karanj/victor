import SwiftUI

// MARK: - Tab Bar View

/// Tab bar for switching between Editor, Preview, and Split layout modes
struct TabBarView: View {
    @Bindable var viewModel: SiteViewModel

    var body: some View {
        HStack {
            Picker("Layout Mode", selection: $viewModel.layoutMode) {
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

            // Live Preview toggle (shown when Hugo server is running and in preview/split mode)
            if viewModel.isHugoServerRunning && viewModel.layoutMode != .editor {
                livePreviewToggle
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var livePreviewToggle: some View {
        Button {
            viewModel.useLivePreview.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: viewModel.useLivePreview ? "server.rack" : "doc.richtext")
                    .font(.caption)
                Text(viewModel.useLivePreview ? "Live Preview" : "Markdown Preview")
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(viewModel.useLivePreview ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(viewModel.useLivePreview ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(viewModel.useLivePreview ? "Using Hugo server for preview. Click to switch to Markdown preview." : "Using Markdown preview. Click to switch to Hugo server live preview.")
    }
}

#Preview {
    TabBarView(viewModel: SiteViewModel())
        .frame(width: 600)
}
