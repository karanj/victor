import SwiftUI

/// Breadcrumb navigation bar showing the current file path with clickable segments
struct BreadcrumbBar: View {
    let fileNode: FileNode
    @Bindable var siteViewModel: SiteViewModel

    /// Path components from content directory to current file
    private var pathComponents: [PathComponent] {
        buildPathComponents()
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(pathComponents.enumerated()), id: \.element.id) { index, component in
                if index > 0 {
                    // Separator chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                BreadcrumbSegment(
                    component: component,
                    isLast: index == pathComponents.count - 1,
                    onNavigate: { navigateToComponent(component) }
                )
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Path Building

    /// Build path components from content directory to current file
    private func buildPathComponents() -> [PathComponent] {
        var components: [PathComponent] = []

        // Get the content directory URL for relative path calculation
        guard let contentURL = siteViewModel.site?.contentDirectory else {
            // Fallback: just show the file name
            return [PathComponent(
                name: fileNode.name,
                url: fileNode.url,
                isDirectory: fileNode.isDirectory,
                node: fileNode
            )]
        }

        // Build path from file up to content directory
        var currentURL = fileNode.url
        var pathStack: [(name: String, url: URL)] = []

        // Walk up the path until we reach the content directory
        while currentURL != contentURL && currentURL.path != "/" {
            pathStack.append((currentURL.lastPathComponent, currentURL))
            currentURL = currentURL.deletingLastPathComponent()
        }

        // Add the content folder as root
        components.append(PathComponent(
            name: "content",
            url: contentURL,
            isDirectory: true,
            node: findNode(for: contentURL)
        ))

        // Add remaining components in order (reverse the stack)
        for (name, url) in pathStack.reversed() {
            let isDir = url != fileNode.url || fileNode.isDirectory
            components.append(PathComponent(
                name: name,
                url: url,
                isDirectory: isDir,
                node: findNode(for: url)
            ))
        }

        return components
    }

    /// Find a FileNode by URL in the view model's file tree
    private func findNode(for url: URL) -> FileNode? {
        for rootNode in siteViewModel.fileNodes {
            if let found = rootNode.findNode(url: url) {
                return found
            }
        }
        return nil
    }

    /// Navigate to a path component (select its folder in sidebar)
    private func navigateToComponent(_ component: PathComponent) {
        // Don't navigate if clicking the current file
        guard component.url != fileNode.url else { return }

        // Find the node and select it
        if let node = component.node {
            // Expand all ancestors first so the node becomes visible in sidebar
            expandPathToNode(node)

            // For directories, expand them as well
            if node.isDirectory {
                node.isExpanded = true
            }

            // Select the node in the sidebar
            siteViewModel.selectNode(node)
        }
    }

    /// Expand all ancestor nodes to make a node visible in the sidebar
    private func expandPathToNode(_ node: FileNode) {
        var ancestors: [FileNode] = []
        var current = node.parent

        // Walk up the tree collecting ancestors
        while let parent = current {
            ancestors.append(parent)
            current = parent.parent
        }

        // Expand from root down (reverse order)
        for ancestor in ancestors.reversed() {
            ancestor.isExpanded = true
        }
    }
}

// MARK: - Path Component Model

/// Represents a single component in the breadcrumb path
struct PathComponent: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let isDirectory: Bool
    let node: FileNode?
}

// MARK: - Breadcrumb Segment View

/// Individual clickable segment in the breadcrumb bar
struct BreadcrumbSegment: View {
    let component: PathComponent
    let isLast: Bool
    let onNavigate: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onNavigate) {
            HStack(spacing: 4) {
                // Icon
                Image(systemName: iconName)
                    .font(.system(size: 11))
                    .foregroundStyle(isLast ? .primary : .secondary)

                // Name
                Text(component.name)
                    .font(.system(size: 12))
                    .foregroundStyle(isLast ? .primary : .secondary)
                    .underline(isHovered && !isLast)
            }
        }
        .buttonStyle(.plain)
        .disabled(isLast) // Can't click on current file
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isLast ? "" : "Click to navigate to this folder")
    }

    private var iconName: String {
        if component.isDirectory {
            return "folder.fill"
        } else {
            return "doc.text.fill"
        }
    }

    private var accessibilityLabel: String {
        if component.isDirectory {
            return "Folder: \(component.name)"
        } else {
            return "File: \(component.name)"
        }
    }
}

// MARK: - Preview

#Preview {
    // Create mock data for preview
    let mockNode = FileNode(url: URL(fileURLWithPath: "/Users/test/my-blog/content/posts/hello.md"), isDirectory: false)
    let viewModel = SiteViewModel()

    return BreadcrumbBar(fileNode: mockNode, siteViewModel: viewModel)
        .frame(width: 500)
}
