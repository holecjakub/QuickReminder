import Foundation

/// Copy and constants shared by both Set Date styles (popover and in-notch), so the two never drift.
enum ScheduleText {
    /// Time chips under the day + time row.
    static let chipHours = [9, 12, 15, 19]
    /// Short enough for the field at default text size (the text-cursor icon already says "type").
    static let placeholder = "fri 2pm, zítra 14:00, +2h"
    /// The invalid hint's example follows the UI language a Czech user would type in.
    static var invalidExample: String {
        Locale.current.language.languageCode?.identifier == "cs" ? "zítra 14:00" : "tomorrow 2pm"
    }
}
