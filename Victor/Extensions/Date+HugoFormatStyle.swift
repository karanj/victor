import Foundation

/// `Date.FormatStyle`/`Date.VerbatimFormatStyle`/`Date.ISO8601FormatStyle` equivalents
/// for the handful of Hugo-facing date formats this app needs (victor-mod grab-bag item 2:
/// `DateFormatter` -> `Date.FormatStyle`). Each one was verified against its
/// `DateFormatter`/`ISO8601DateFormatter` predecessor to produce byte-identical output
/// for the same date before replacing call sites.
extension Date.ISO8601FormatStyle {
    /// Hugo archetype timestamp: `yyyy-MM-ddTHH:mm:ss` - no timezone offset. Matches the
    /// exact `ISO8601DateFormatter` options archetypes have always used
    /// (`.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime`,
    /// deliberately omitting `.withTimeZone`).
    static var hugoArchetypeTimestamp: Self {
        Date.ISO8601FormatStyle()
            .year().month().day()
            .dateSeparator(.dash)
            .time(includingFractionalSeconds: false)
            .timeSeparator(.colon)
    }
}

extension Date.VerbatimFormatStyle {
    /// `yyyy-MM-dd`, POSIX locale, Gregorian calendar, given timezone (defaults to
    /// `.current`) - used for Hugo-facing filenames and frontmatter dates where the
    /// format must stay fixed regardless of the user's locale/calendar (matches the
    /// `en_US_POSIX`-locale `DateFormatter`s this replaces).
    static func hugoDateOnly(timeZone: TimeZone = .current) -> Self {
        Date.VerbatimFormatStyle(
            format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)",
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: timeZone,
            calendar: Calendar(identifier: .gregorian)
        )
    }

    /// Full (English) month name, e.g. "December" - matches `dateFormat = "MMMM"` with
    /// the `en_US_POSIX` locale Hugo permalink tokens have always used.
    static func hugoMonthName(timeZone: TimeZone) -> Self {
        Date.VerbatimFormatStyle(
            format: "\(month: .wide)",
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: timeZone,
            calendar: Calendar(identifier: .gregorian)
        )
    }

    /// Full (English) weekday name, e.g. "Tuesday" - matches `dateFormat = "EEEE"` with
    /// the `en_US_POSIX` locale Hugo permalink tokens have always used.
    static func hugoWeekdayName(timeZone: TimeZone) -> Self {
        Date.VerbatimFormatStyle(
            format: "\(weekday: .wide)",
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: timeZone,
            calendar: Calendar(identifier: .gregorian)
        )
    }
}
