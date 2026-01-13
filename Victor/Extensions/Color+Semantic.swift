import SwiftUI
import AppKit

// MARK: - Color Luminance & Contrast

extension Color {
    /// Calculate relative luminance using WCAG formula
    /// Returns value between 0 (black) and 1 (white)
    var luminance: Double {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else {
            return 0.5
        }

        // Convert sRGB to linear RGB
        func linearize(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }

        let r = linearize(components.redComponent)
        let g = linearize(components.greenComponent)
        let b = linearize(components.blueComponent)

        // WCAG relative luminance formula
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Returns white or black depending on which provides better contrast
    var contrastingTextColor: Color {
        // Use white text for dark backgrounds, black for light
        // Threshold of 0.5 provides good results for most colors
        luminance < 0.5 ? .white : .black
    }
}

// MARK: - Hex Color Conversion

extension Color {
    /// Initialize Color from hex string (e.g., "#FF5500" or "FF5500")
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6,
              let rgb = UInt64(hexSanitized, radix: 16) else {
            return nil
        }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    /// Convert Color to hex string
    var hexString: String {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else {
            return "#000000"
        }
        let r = Int(components.redComponent * 255)
        let g = Int(components.greenComponent * 255)
        let b = Int(components.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Badge Color Keys

extension Color {
    /// UserDefaults keys for customizable badge colors
    enum BadgeColorKey: String {
        case draft = "badgeColorDraft"
        case scheduled = "badgeColorScheduled"
        case expired = "badgeColorExpired"

        /// Default color for this badge type
        var defaultColor: Color {
            switch self {
            case .draft: return Color(nsColor: .systemOrange)
            case .scheduled: return Color(nsColor: .systemBlue)
            case .expired: return Color(nsColor: .systemGray)
            }
        }

        /// Default hex value for this badge type
        var defaultHex: String {
            defaultColor.hexString
        }
    }
}

// MARK: - Semantic Badge Colors

extension Color {
    /// Colors for content status badges (customizable via Preferences)
    enum Badge {
        /// Draft content badge color
        static var draft: Color {
            if let hex = UserDefaults.standard.string(forKey: BadgeColorKey.draft.rawValue),
               let color = Color(hex: hex) {
                return color
            }
            return BadgeColorKey.draft.defaultColor
        }

        /// Scheduled content badge color
        static var scheduled: Color {
            if let hex = UserDefaults.standard.string(forKey: BadgeColorKey.scheduled.rawValue),
               let color = Color(hex: hex) {
                return color
            }
            return BadgeColorKey.scheduled.defaultColor
        }

        /// Expired content badge color
        static var expired: Color {
            if let hex = UserDefaults.standard.string(forKey: BadgeColorKey.expired.rawValue),
               let color = Color(hex: hex) {
                return color
            }
            return BadgeColorKey.expired.defaultColor
        }

        /// Page bundle badge color (not customizable)
        static let pageBundle = Color(nsColor: .systemPurple)
        /// Config file badge color (not customizable)
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
