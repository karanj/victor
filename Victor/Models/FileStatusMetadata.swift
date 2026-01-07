import Foundation
import SwiftUI

/// Lightweight metadata for file status indicators in the sidebar.
/// Only contains fields needed to determine Draft/Scheduled/Expired status,
/// without loading the full file content.
struct FileStatusMetadata: Equatable {
    /// Whether the file has `draft: true` in frontmatter
    let isDraft: Bool

    /// The publication date from frontmatter
    let date: Date?

    /// The publish date if different from date
    let publishDate: Date?

    /// The expiry date from frontmatter
    let expiryDate: Date?

    /// Computed status based on current date (returns single status for backwards compatibility)
    var status: ContentStatus {
        // Return first non-published status, or published if none
        return statuses.first ?? .published
    }

    /// All applicable statuses (a post can be both draft AND scheduled, for example)
    var statuses: [ContentStatus] {
        let now = Date()
        var result: [ContentStatus] = []

        // Check draft
        if isDraft {
            result.append(.draft)
        }

        // Check future-dated (publishDate or date in the future)
        let effectivePublishDate = publishDate ?? date
        if let pubDate = effectivePublishDate, pubDate > now {
            result.append(.scheduled)
        }

        // Check expired
        if let expiry = expiryDate, expiry < now {
            result.append(.expired)
        }

        return result
    }

    /// Initialize from a Frontmatter object (for when full content is loaded)
    init(from frontmatter: Frontmatter?) {
        self.isDraft = frontmatter?.isDraft ?? false
        self.date = frontmatter?.date
        self.publishDate = frontmatter?.publishDate
        self.expiryDate = frontmatter?.expiryDate
    }

    /// Initialize directly (for lightweight parsing)
    init(isDraft: Bool, date: Date?, publishDate: Date?, expiryDate: Date?) {
        self.isDraft = isDraft
        self.date = date
        self.publishDate = publishDate
        self.expiryDate = expiryDate
    }
}

/// Represents the publication status of a content file
enum ContentStatus: Equatable {
    case published   // Live content - no badge
    case draft       // Not published (draft: true)
    case scheduled   // Future-dated (will publish later)
    case expired     // Past expiry date

    var displayName: String {
        switch self {
        case .published: return "Published"
        case .draft: return "Draft"
        case .scheduled: return "Scheduled"
        case .expired: return "Expired"
        }
    }

    var badgeColor: Color {
        switch self {
        case .published: return .clear
        case .draft: return Color.Badge.draft
        case .scheduled: return Color.Badge.scheduled
        case .expired: return Color.Badge.expired
        }
    }
}
