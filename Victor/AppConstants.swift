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
        /// Field label width in forms
        static let fieldLabelWidth: CGFloat = 100
        /// Maximum height for autocomplete dropdown
        static let autocompleteMaxHeight: CGFloat = 250
    }

    /// Standard spacing values
    enum Spacing {
        /// Small spacing (4pt)
        static let small: CGFloat = 4
        /// Medium spacing (8pt)
        static let medium: CGFloat = 8
        /// Large spacing (12pt)
        static let large: CGFloat = 12
        /// Extra large spacing (16pt)
        static let extraLarge: CGFloat = 16
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
        /// Default window width
        static let defaultWidth: CGFloat = 1200
        /// Default window height
        static let defaultHeight: CGFloat = 800
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
        /// Shortcode card width
        static let shortcodeCardWidth: CGFloat = 350
        /// New content dialog width
        static let newContentWidth: CGFloat = 450
        /// New content dialog height
        static let newContentHeight: CGFloat = 400
        /// Menu entry editor width
        static let menuEditorWidth: CGFloat = 400
        /// Menu weight field width
        static let menuWeightWidth: CGFloat = 60
        /// Custom field editor width
        static let customFieldWidth: CGFloat = 400
    }

    /// Config editor constants
    enum ConfigEditor {
        /// Label column width
        static let labelWidth: CGFloat = 120
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
        /// View with Icons label frame width
        static let viewIconLabelFrameWidth: CGFloat = 100
        /// View with form/raw label frame width
        static let viewFormLabelFrameWidth: CGFloat = 150
    }

    // MARK: - UserDefaults Keys

    /// Global search settings
    enum GlobalSearch {
        /// Maximum matches to show per file (for performance)
        static let maxResultsPerFile = 100
        /// Debounce interval for live search (increased from 0.3 for large codebases)
        static let debounceInterval: TimeInterval = 0.5
        /// Minimum query length before search triggers (avoids expensive single-char searches)
        static let minQueryLength = 2
        /// Width of search panel
        static let panelWidth: CGFloat = 700
        /// Height of search panel
        static let panelHeight: CGFloat = 500
        /// Width of scope picker dropdown
        static let scopePickerWidth: CGFloat = 100
        /// Width of line number column in results
        static let lineNumberWidth: CGFloat = 40
    }

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
        static let lastSelectedFilePath = "lastSelectedFilePath"
    }
}
