import Foundation
import CoreGraphics

/// Centralized constants for the application
enum AppConstants {

    // MARK: - Timing

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

    /// UI feedback timing constants
    enum Timing {
        /// Duration to show "Saved" indicator after saving
        static let savedIndicatorDuration: TimeInterval = 2.0
        /// Duration to show auto-save indicator
        static let autoSaveIndicatorDuration: TimeInterval = 1.0
    }

    // MARK: - Animation

    /// Animation duration constants
    enum Animation {
        /// Fast transitions (fade in/out, hover effects)
        static let fast: Double = 0.15
        /// Standard UI animations (panel show/hide, mode switches)
        static let standard: Double = 0.2
        /// Slower animations (focus mode transitions)
        static let slow: Double = 0.3
    }

    // MARK: - Layout

    /// Editor related constants
    enum Editor {
        /// Default font size for the markdown editor
        static let fontSize: CGFloat = 13
        /// Horizontal padding inside text container
        static let textContainerInsetWidth: CGFloat = 16
        /// Vertical padding inside text container
        static let textContainerInsetHeight: CGFloat = 10
    }

    /// Sidebar layout constants
    enum Sidebar {
        /// Minimum sidebar width
        static let minWidth: CGFloat = 250
        /// Ideal/default sidebar width
        static let idealWidth: CGFloat = 300
        /// Maximum sidebar width
        static let maxWidth: CGFloat = 400
    }

    /// Content area layout constants
    enum Content {
        /// Minimum width for main content area
        static let minWidth: CGFloat = 400
        /// Minimum width for editor/preview panels in split view
        static let panelMinWidth: CGFloat = 300
    }

    /// Main window constants
    enum Window {
        /// Minimum window width
        static let minWidth: CGFloat = 1000
        /// Minimum window height
        static let minHeight: CGFloat = 600
    }

    /// Dialog/picker constants
    enum Dialog {
        /// Shortcode picker minimum width
        static let shortcodePickerWidth: CGFloat = 800
        /// Shortcode picker minimum height
        static let shortcodePickerHeight: CGFloat = 500
        /// Shortcode form minimum width
        static let shortcodeFormWidth: CGFloat = 400
    }

    /// Editor toolbar constants
    enum Toolbar {
        /// Horizontal padding for toolbar container
        static let horizontalPadding: CGFloat = 12
        /// Vertical padding for toolbar container
        static let verticalPadding: CGFloat = 8
        /// Spacing between buttons within a group
        static let groupSpacing: CGFloat = 4
        /// Height of separator dividers between groups
        static let separatorHeight: CGFloat = 20
        /// Horizontal padding around separators
        static let separatorPadding: CGFloat = 8
        /// Height of action separator (before save button)
        static let actionSeparatorHeight: CGFloat = 24
        /// Width of heading dropdown menu
        static let headingMenuWidth: CGFloat = 100
        /// Save indicator spring response
        static let saveSpringResponse: Double = 0.3
        /// Save indicator spring damping
        static let saveSpringDamping: Double = 0.6
    }

    // MARK: - UserDefaults Keys

    /// Centralized UserDefaults keys to avoid string literal duplication
    enum UserDefaultsKeys {
        static let hugoSiteBookmark = "hugoSiteBookmark"
        static let isAutoSaveEnabled = "isAutoSaveEnabled"
        static let editorLayoutMode = "editorLayoutMode"
        static let highlightCurrentLine = "highlightCurrentLine"
        static let editorFontSize = "editorFontSize"
        static let autoSaveDelay = "autoSaveDelay"
        static let isInspectorVisible = "isInspectorVisible"
        static let recentSitePaths = "recentSitePaths"
    }
}
