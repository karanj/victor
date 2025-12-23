import Foundation
import CoreGraphics

/// Centralized constants for the application
enum AppConstants {

    /// Auto-save related constants
    enum AutoSave {
        /// Debounce interval for auto-save (wait time after last edit before saving)
        static let debounceInterval: TimeInterval = 2.0
    }

    /// Preview panel related constants
    enum Preview {
        /// Debounce interval for preview updates (wait time after typing stops)
        static let debounceInterval: TimeInterval = 0.3
    }

    /// Editor related constants
    enum Editor {
        /// Default font size for the markdown editor
        static let fontSize: CGFloat = 13
    }
}
