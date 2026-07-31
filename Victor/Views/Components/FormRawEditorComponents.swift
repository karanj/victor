import SwiftUI

// MARK: - Form/Raw Picker

/// Reusable segmented picker for switching between Form and Raw editing modes
struct FormRawPickerView: View {
    @Binding var showRawEditor: Bool
    var width: CGFloat = AppConstants.Toolbar.viewFormLabelFrameWidth

    var body: some View {
        Picker("View", selection: $showRawEditor) {
            Text("Form").tag(false)
            Text("Raw").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(width: width)
    }
}

// MARK: - Parse Error Alert Modifier

/// View modifier that adds a parse error alert to any view
struct ParseErrorAlertModifier: ViewModifier {
    @Binding var parseError: String?

    func body(content: Content) -> some View {
        content
            .alert("Parse Error", isPresented: Binding(
                get: { parseError != nil },
                set: { if !$0 { parseError = nil } }
            )) {
                Button("OK") { parseError = nil }
            } message: {
                if let error = parseError {
                    // The message carries its own direction ("Failed to serialize: ..." vs a
                    // parse error), so don't prefix one here.
                    Text(error)
                }
            }
    }
}

extension View {
    /// Adds a parse error alert that displays when parseError is non-nil
    func parseErrorAlert(_ parseError: Binding<String?>) -> some View {
        modifier(ParseErrorAlertModifier(parseError: parseError))
    }
}

// MARK: - Form/Raw Toggle Handler

/// Form/Raw toggle transitions.
///
/// Both directions return whether the conversion landed. A false result means the target
/// mode is showing stale content while the user's real edits sit in the mode they came
/// from - the caller must revert the toggle rather than leave them there, or the next
/// toggle back overwrites the edits from the stale side.
struct FormRawToggleHandler {
    static func handleFormToRaw(
        serializeToRaw: () throws -> Void,
        parseError: inout String?
    ) -> Bool {
        do {
            try serializeToRaw()
            parseError = nil
            return true
        } catch {
            parseError = "Failed to serialize: \(error.localizedDescription)"
            return false
        }
    }

    static func handleRawToForm(
        parseFromRaw: () throws -> Void,
        parseError: inout String?
    ) -> Bool {
        do {
            try parseFromRaw()
            parseError = nil
            return true
        } catch {
            parseError = error.localizedDescription
            return false
        }
    }
}

// MARK: - Previews

#Preview("Form/Raw Picker - Form Selected") {
    FormRawPickerView(showRawEditor: .constant(false))
        .padding()
}

#Preview("Form/Raw Picker - Raw Selected") {
    FormRawPickerView(showRawEditor: .constant(true))
        .padding()
}
