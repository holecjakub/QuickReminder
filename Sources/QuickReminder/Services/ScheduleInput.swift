import Foundation

/// Reads the Set Date popover's type field: the whole input must be one date/time phrase.
///
/// On top of `NaturalDateParser` it accepts a few picker-only shorthands that would be wrong in a
/// reminder title ("buy 2 apples" must stay a title, so the title parser never sees these):
/// a bare hour `14` / `3` (1…6 read as PM, like the parser), `930` / `1430`, `14:30` / `14.30`,
/// offsets `+90m` / `+2h` / `+3d`, and a leading weekday abbreviation ("fri 2pm").
///
/// Known rejection: anything that is not entirely a date, including "tomorrow please" — the field
/// would otherwise silently drop words the user may have meant.
enum ScheduleInput {
    enum Result: Equatable {
        case empty
        case date(Date)
        case invalid
    }

    static func resolve(_ text: String, now: Date, calendar: Calendar = .current) -> Result {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        if let shorthand = shorthand(trimmed, now: now, calendar: calendar) { return shorthand }

        let phrase = withWeekdayPrefix(trimmed)
        guard let suggestion = NaturalDateParser.parse(phrase, now: now, calendar: calendar) else { return .invalid }
        let leftover = NaturalDateParser.removingMatch(from: phrase, suggestion: suggestion)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard leftover.isEmpty else { return .invalid }

        // A time-only phrase already past today was rolled to tomorrow by the parser.
        if suggestion.hasTime { return .date(suggestion.date) }
        return .date(ScheduleDefaults.resolveDayOnly(suggestion.date, now: now, calendar: calendar))
    }

    // MARK: - Picker-only shorthands

    /// nil = not a shorthand (let the parser try); `.invalid` = shaped like one but out of range
    /// ("2500", "25:00"), which the parser must not reinterpret either.
    private static func shorthand(_ text: String, now: Date, calendar: Calendar) -> Result? {
        if text.allSatisfy(\.isASCIIDigit) {
            switch text.count {
            case 1...2:
                return time(hour: Int(text), minute: 0, now: now, calendar: calendar)
            case 3...4:
                let hour = Int(text.dropLast(2)), minute = Int(text.suffix(2))
                return time(hour: hour, minute: minute, now: now, calendar: calendar)
            default:
                return nil
            }
        }

        if let match = text.wholeMatch(of: /(\d{1,2})[:.](\d{2})/) {
            return time(hour: Int(match.1), minute: Int(match.2), now: now, calendar: calendar)
        }

        if let match = text.wholeMatch(of: /\+(\d{1,3})\s*(m|min|h|d)/.ignoresCase()), let amount = Int(match.1) {
            switch match.2.lowercased() {
            case "d":
                let day = calendar.date(byAdding: .day, value: amount, to: now) ?? now
                return .date(ScheduleDefaults.resolveDayOnly(calendar.startOfDay(for: day), now: now, calendar: calendar))
            case "h":
                return .date(now.addingTimeInterval(TimeInterval(amount) * 3600))
            default:
                return .date(now.addingTimeInterval(TimeInterval(amount) * 60))
            }
        }
        return nil
    }

    /// The title parser only takes "fri" / "sat" after "on" / "next" ("sat", "sun", "wed" are
    /// ordinary words in a title). Here the whole input is a date, so a leading abbreviation is
    /// read as "on fri": "fri 2pm" works.
    private static func withWeekdayPrefix(_ text: String) -> String {
        guard let first = text.split(separator: " ", maxSplits: 1).first,
              weekdayAbbreviations.contains(first.lowercased()) else { return text }
        return "on " + text
    }

    private static let weekdayAbbreviations: Set<String> = [
        "mon", "tue", "tues", "wed", "weds", "thu", "thur", "thurs", "fri", "sat", "sun"
    ]

    /// Hour/minute today, or tomorrow when already past (the parser's time-only rule).
    private static func time(hour: Int?, minute: Int?, now: Date, calendar: Calendar) -> Result {
        guard let hour, let minute, (0...23).contains(hour), (0...59).contains(minute) else { return .invalid }
        let resolvedHour = NaturalDateParser.disambiguate(hour)
        let today = calendar.startOfDay(for: now)
        let candidate = ScheduleDefaults.at(hour: resolvedHour, minute: minute, on: today, calendar: calendar)
        if candidate > now { return .date(candidate) }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return .date(ScheduleDefaults.at(hour: resolvedHour, minute: minute, on: tomorrow, calendar: calendar))
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
