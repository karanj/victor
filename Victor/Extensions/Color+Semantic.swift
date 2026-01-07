import SwiftUI

// MARK: - Semantic Badge Colors

extension Color {
    /// Colors for content status badges
    enum Badge {
        /// Draft content badge color
        static let draft = Color(nsColor: .systemOrange)
        /// Scheduled content badge color
        static let scheduled = Color(nsColor: .systemBlue)
        /// Expired content badge color
        static let expired = Color(nsColor: .systemGray)
        /// Page bundle badge color
        static let pageBundle = Color(nsColor: .systemPurple)
        /// Config file badge color
        static let config = Color(nsColor: .systemOrange)
    }

    /// Colors for file type icons
    enum FileIcon {
        /// Default folder color
        static let folder = Color(nsColor: .systemBlue)
        /// Page bundle folder color
        static let pageBundle = Color(nsColor: .systemPurple)
        /// Config file color
        static let config = Color(nsColor: .systemOrange)
        /// Markdown file color
        static let markdown = Color(nsColor: .systemBlue)
        /// Image file color
        static let image = Color(nsColor: .systemPurple)
        /// Code file color
        static let code = Color(nsColor: .systemOrange)
    }

    /// Colors for shortcode elements
    enum Shortcode {
        /// Required parameter badge
        static let required = Color(nsColor: .systemOrange)
        /// Optional parameter badge
        static let optional = Color(nsColor: .systemBlue)
    }

    /// Colors for status indicators
    enum Status {
        /// Modified/unsaved indicator
        static let modified = Color(nsColor: .systemOrange)
        /// Saved/success indicator
        static let saved = Color(nsColor: .systemGreen)
        /// Error indicator
        static let error = Color(nsColor: .systemRed)
        /// Warning/deprecated indicator
        static let warning = Color(nsColor: .systemOrange)
        /// Info/block indicator
        static let info = Color(nsColor: .systemBlue)
    }
}
