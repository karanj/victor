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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

#Preview {
    TabBarView(viewModel: SiteViewModel())
        .frame(width: 600)
}
