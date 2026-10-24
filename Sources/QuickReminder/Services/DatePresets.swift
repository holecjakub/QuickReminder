import Foundation

/// The one preset set shared by the calendar menu and the Set Date popover (⌘1…⌘6), in display
/// order. Rows never hide: labels adapt to the time of day, positions stay put.
enum DatePreset: Int, CaseIterable, Sendable {
    case inOneHour, evening, tomorrow, weekend, nextWeek, nextMonth

    /// The evening preset rolls to tomorrow this close to its hour (18:30 → tomorrow 19:00).
    static let eveningCutoffMinutes = 30

    static func date(for preset: DatePreset, now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }
        func morning(of day: Date) -> Date { ScheduleDefaults.at(hour: ScheduleDefaults.dayOnlyHour, minute: 0, on: day, calendar: calendar) }

        switch preset {
        case .inOneHour:
            // Exact minutes kept, like the menu's "Remind Me In 1 Hour" always did.
            return now.addingTimeInterval(60 * 60)
        case .evening:
            let tonight = ScheduleDefaults.at(hour: DayPart.eveningHour, minute: 0, on: today, calendar: calendar)
            let rolls = now >= tonight.addingTimeInterval(-Double(eveningCutoffMinutes) * 60)
            return rolls ? ScheduleDefaults.at(hour: DayPart.eveningHour, minute: 0, on: day(1), calendar: calendar) : tonight
        case .tomorrow:
            return morning(of: day(1))
        case .weekend:
            return morning(of: nextWeekday(7, after: now, calendar: calendar))
        case .nextWeek:
            return morning(of: nextWeekday(2, after: now, calendar: calendar))
        case .nextMonth:
            var components = calendar.dateComponents([.year, .month], from: today)
            components.day = 1
            let firstOfThisMonth = calendar.date(from: components) ?? today
            let firstOfNext = calendar.date(byAdding: .month, value: 1, to: firstOfThisMonth) ?? today
            return morning(of: firstOfNext)
        }
    }

    /// Short label (popover cards; the menu prefixes two of them, see `menuTitle`).
    static func title(for preset: DatePreset, now: Date, calendar: Calendar = .current) -> String {
        switch preset {
        case .inOneHour: return "In 1 Hour"
        case .evening:
            return calendar.isDate(date(for: .evening, now: now, calendar: calendar), inSameDayAs: now)
                ? "This Evening" : "Tomorrow Evening"
        case .tomorrow: return "Tomorrow"
        case .weekend:
            let weekday = calendar.component(.weekday, from: now)
            return (weekday == 7 || weekday == 1) ? "Next Weekend" : "This Weekend"
        case .nextWeek: return "Next Week"
        case .nextMonth: return "Next Month"
        }
    }

    /// Menu wording: the two rows the menu already had keep their "Remind Me …" labels.
    static func menuTitle(for preset: DatePreset, now: Date, calendar: Calendar = .current) -> String {
        switch preset {
        case .inOneHour: return "Remind Me In 1 Hour"
        case .tomorrow: return "Remind Me Tomorrow"
        default: return title(for: preset, now: now, calendar: calendar)
        }
    }

    static func systemImage(for preset: DatePreset) -> String {
        switch preset {
        case .inOneHour: return "clock"
        case .evening: return "moon"
        case .tomorrow: return "sunrise"
        case .weekend: return "sofa"
        case .nextWeek: return "calendar.badge.plus"
        case .nextMonth: return "calendar"
        }
    }

    /// Locale template for a date shown next to "now" (preset details, the Set button, their
    /// spoken labels): time only today ("19:00"), weekday + time for the next six days
    /// ("so 9:00" / "Sat 9:00 AM"), day + month + time from a week out ("1. 11. 9:00" /
    /// "Nov 1 at 9:00 AM") — a bare weekday would name the wrong day (Next Month on a Saturday
    /// reads "Sun 9:00", same as Tomorrow). `spoken` spells weekday and month out for VoiceOver.
    static func detailTemplate(for date: Date, now: Date, calendar: Calendar = .current, spoken: Bool = false) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "j:mm"
        case 1...6: return spoken ? "EEEE j:mm" : "EEE j:mm"
        default: return spoken ? "EEEE d MMMM j:mm" : "d MMM j:mm"
        }
    }

    /// The next `weekday` (1 = Sunday … 7 = Saturday) strictly after today, at the start of the day.
    /// The parser resolves "friday" / "next week" / "weekend" through this too, so a typed phrase
    /// and the matching preset always agree.
    static func nextWeekday(_ weekday: Int, after now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        let current = calendar.component(.weekday, from: today)
        var delta = (weekday - current + 7) % 7
        if delta == 0 { delta = 7 }
        return calendar.date(byAdding: .day, value: delta, to: today) ?? today
    }
}
