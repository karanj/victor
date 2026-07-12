import SwiftUI

// MARK: - Rename Validation

/// Why a candidate rename target is rejected. Pure/value-only so the sheet's
/// validation logic is unit-testable without a filesystem or SiteViewModel
/// fixture (victor-rnm).
enum RenameValidationError: Equatable {
    case empty
    case invalidCharacters
    case collision

    var message: String {
        switch self {
        case .empty:
            return "Name cannot be empty."
        case .invalidCharacters:
            return "Name cannot contain \"/\" or \":\"."
        case .collision:
            return "An item with this name already exists."
        }
    }
}

/// Pure validation for the rename sheet's TextField - no I/O. Mirrors
/// FileSystemService.renameFile's on-disk checks (isSafeFilename, destination
/// already exists) at the UI layer, so the sheet can disable Confirm and show
/// an inline message before ever touching disk.
enum RenameValidator {
    /// - Parameters:
    ///   - newName: the candidate name, as typed (untrimmed).
    ///   - currentName: the node's existing name - a case-insensitive match
    ///     against this is not a collision, since it targets the same node
    ///     (e.g. correcting the casing of "post.MD" to "post.md").
    ///   - existingSiblingNames: names of every OTHER node in the same parent
    ///     (or every other top-level node, for a root item), for the
    ///     case-insensitive collision check - APFS default-formats
    ///     case-insensitive, so "Post.md" and "post.md" collide.
    static func validate(
        newName: String,
        currentName: String,
        existingSiblingNames: [String]
    ) -> RenameValidationError? {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return .empty }
        guard !trimmed.contains("/") && !trimmed.contains(":") else { return .invalidCharacters }

        if trimmed.caseInsensitiveCompare(currentName) != .orderedSame {
            let collides = existingSiblingNames.contains {
                $0.caseInsensitiveCompare(trimmed) == .orderedSame
            }
            if collides { return .collision }
        }

        return nil
    }
}

// MARK: - Rename Sheet

/// Rename sheet for a file or folder node, opened from FileContextMenu /
/// FolderContextMenu's "Rename..." item or the Return-key accelerator on the
/// sidebar List. Follows the header / Form / footer pattern the other sidebar
/// sheets already use (NewDataFileView, NewArchetypeView) rather than
/// inventing a new style.
struct RenameSheet: View {
    let node: FileNode
    let siteViewModel: SiteViewModel

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFieldFocused: Bool

    @State private var newName: String
    @State private var isRenaming = false

    init(node: FileNode, siteViewModel: SiteViewModel) {
        self.node = node
        self.siteViewModel = siteViewModel
        self._newName = State(initialValue: node.name)
    }

    /// Every other child of `node`'s parent (or every other top-level node,
    /// for a root item) - the collision set `RenameValidator` checks against.
    private var existingSiblingNames: [String] {
        let siblings = node.parent?.children ?? siteViewModel.fileNodes
        return siblings.filter { $0.id != node.id }.map(\.name)
    }

    private var validationError: RenameValidationError? {
        RenameValidator.validate(newName: newName, currentName: node.name, existingSiblingNames: existingSiblingNames)
    }

    /// Also blocks confirming an unchanged name: not a validation error, just
    /// nothing to do - and FileSystemService.renameFile would throw
    /// .fileAlreadyExists for a rename where source and destination path are
    /// identical.
    private var canConfirm: Bool {
        validationError == nil
            && newName.trimmingCharacters(in: .whitespacesAndNewlines) != node.name
            && !isRenaming
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Rename")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Form {
                Section {
                    TextField("Name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNameFieldFocused)
                        // Validation message isn't visible-adjacent-only:
                        // VoiceOver users focused on the field hear the
                        // constraint without having to separately discover
                        // the inline error Text below.
                        .accessibilityHint(validationError?.message ?? "")
                        .onSubmit {
                            confirm()
                        }
                }

                if let validationError {
                    Section {
                        Text(validationError.message)
                            .font(.caption)
                            .foregroundStyle(Color.Status.error)
                    }
                }
            }
            .formStyle(.grouped)
            // Announces validation state changes as the user types, since the
            // inline error Text above has no focus of its own to carry the
            // message to a screen reader otherwise.
            .onChange(of: validationError) { _, newValue in
                if let newValue {
                    AccessibilityNotification.Announcement(newValue.message).post()
                }
            }

            Divider()

            HStack {
                Spacer()

                Button("Rename") {
                    confirm()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canConfirm)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 380, height: 200)
        .onAppear {
            isNameFieldFocused = true
        }
    }

    private func confirm() {
        guard canConfirm else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        isRenaming = true
        Task {
            await siteViewModel.renameFile(node: node, to: trimmed)
            isRenaming = false
            dismiss()
        }
    }
}
