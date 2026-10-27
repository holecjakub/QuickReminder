import Foundation

/// The in-notch Set Date month grid as data: always six weeks (so the section's height never
/// depends on the month), starting on the locale's first weekday, with nil for days outside the
/// month. Pure, so the layout and keyboard movement are unit-tested without a view.
enum MonthGrid {
    static let weeks = 6
    static let cellCount = weeks * 7

    /// Midnight on the first day of `date`'s month.
    static func startOfMonth(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// `cellCount` cells, row by row; a cell is the day's midnight or nil (leading / trailing blank).
    static func cells(for month: Date, calendar: Calendar = .current) -> [Date?] {
        let first = startOfMonth(month, calendar: calendar)
        let dayCount = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        var cells = [Date?](repeating: nil, count: cellCount)
        for offset in 0..<dayCount {
            cells[lead + offset] = calendar.date(byAdding: .day, value: offset, to: first)
        }
        return cells
    }

    /// The grid row (0…5) of `day` in its own month's grid.
    static func week(of day: Date, calendar: Calendar = .current) -> Int? {
        let start = calendar.startOfDay(for: day)
        return cells(for: day, calendar: calendar).firstIndex { $0 == start }.map { $0 / 7 }
    }

    /// Very short weekday names ("M", "T" / "P", "Ú") in grid order.
    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    /// Full weekday names in grid order (VoiceOver / tooltips).
    static func fullWeekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.standaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    /// The first of the month `by` months away from `month`'s.
    static func shiftMonth(_ month: Date, by months: Int, calendar: Calendar = .current) -> Date {
        let first = startOfMonth(month, calendar: calendar)
        return calendar.date(byAdding: .month, value: months, to: first) ?? first
    }

    /// Arrow-key movement: `days` away from `day` (±1 left/right, ±7 up/down), never before
    /// `earliest` (today; the past is not selectable). Keeps `day`'s time of day.
    static func moving(_ day: Date, byDays days: Int, earliest: Date, calendar: Calendar = .current) -> Date {
        let moved = calendar.date(byAdding: .day, value: days, to: day) ?? day
        return calendar.startOfDay(for: moved) < calendar.startOfDay(for: earliest) ? day : moved
    }

    /// Whether `day` can be picked (today or later).
    static func isSelectable(_ day: Date, now: Date, calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: day) >= calendar.startOfDay(for: now)
    }

    /// Whether the month before `month` still has selectable days (the ‹ button).
    static func canGoBack(from month: Date, now: Date, calendar: Calendar = .current) -> Bool {
        startOfMonth(month, calendar: calendar) > startOfMonth(now, calendar: calendar)
    }
}
