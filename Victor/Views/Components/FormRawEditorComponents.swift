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
                    Text("Could not parse the raw content: \(error)")
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

/// Helper to handle Form/Raw toggle transitions
struct FormRawToggleHandler {
    /// Handle the transition from Form to Raw mode
    /// - Parameters:
    ///   - serializeToRaw: Closure that serializes form data to raw content (throws on error)
    ///   - parseError: Binding to store any serialization error
    static func handleFormToRaw(
        serializeToRaw: () throws -> Void,
        parseError: inout String?
    ) {
        do {
            try serializeToRaw()
        } catch {
            parseError = "Failed to serialize: \(error.localizedDescription)"
        }
    }

    /// Handle the transition from Raw to Form mode
    /// - Parameters:
    ///   - parseFromRaw: Closure that parses raw content to form data (throws on error)
    ///   - parseError: Binding to store any parse error
    static func handleRawToForm(
        parseFromRaw: () throws -> Void,
        parseError: inout String?
    ) {
        do {
            try parseFromRaw()
            parseError = nil
        } catch {
            parseError = error.localizedDescription
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
