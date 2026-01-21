import SwiftUI

/// A reusable form section container with title, optional icon, and content
///
/// Use this component for non-collapsible sections in forms and editors.
/// For collapsible sections, use `InspectorSection` or SwiftUI's `DisclosureGroup`.
///
/// Usage:
/// ```swift
/// FormSectionView("Site Identity", icon: "globe") {
///     TextField("Title", text: $title)
///     TextField("URL", text: $url)
/// }
/// ```
struct FormSectionView<Content: View>: View {
    let title: String
    let icon: String?
    @ViewBuilder let content: Content

    /// Creates a form section with title, optional icon, and content
    /// - Parameters:
    ///   - title: The section title
    ///   - icon: Optional SF Symbol name for the section icon
    ///   - content: The section content
    init(_ title: String, icon: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.headline)
            }
            .foregroundStyle(.secondary)

            // Section content
            content
        }
    }
}

// MARK: - Previews

#Preview("Basic Section") {
    VStack(spacing: 20) {
        FormSectionView("User Details") {
            TextField("Name", text: .constant(""))
            TextField("Email", text: .constant(""))
        }

        FormSectionView("Settings", icon: "gearshape") {
            Toggle("Enable notifications", isOn: .constant(true))
            Toggle("Dark mode", isOn: .constant(false))
        }
    }
    .padding()
    .frame(width: 300)
}

#Preview("With Icon") {
    FormSectionView("Server Configuration", icon: "server.rack") {
        LabeledContent("Host") {
            TextField("", text: .constant("localhost"))
        }
        LabeledContent("Port") {
            TextField("", text: .constant("1313"))
        }
    }
    .padding()
    .frame(width: 300)
}
