import Foundation

/// The rules every scheduling path shares (Tab on a title suggestion, the typed field in the
/// Set Date popover, the presets): which time a day-only date gets, and where "now-ish" lands.
enum ScheduleDefaults {
    /// Hour a day-only date ("tomorrow", "v pátek", "15.11.") resolves to; the parser's "morning".
    static let dayOnlyHour = DayPart.morningHour

    /// The next :00 / :30 (for the default `granularity`) that is at least `minLead` ahead, so a
    /// reminder set "for later today" never fires a minute after it was written.
    /// 14:12 → 14:30, 14:20 → 15:00, 23:50 → 00:30 the next day.
    static func nextSlot(after now: Date, calendar: Calendar = .current,
                         granularity: Int = 30, minLead: TimeInterval = 15 * 60) -> Date {
        let earliest = now.addingTimeInterval(minLead)
        // Slots are counted from the start of the hour, so half-hour time zones and DST days
        // still land on wall-clock :00 / :30.
        guard let hourStart = calendar.dateInterval(of: .hour, for: earliest)?.start else { return earliest }
        var slot = hourStart
        while slot < earliest {
            slot = calendar.date(byAdding: .minute, value: granularity, to: slot) ?? earliest
        }
        return slot
    }

    /// A day-only date at 9:00. Today after 9:00 becomes the next slot instead of an alarm already
    /// in the past, and when that slot would cross midnight, tomorrow at 9:00.
    static func resolveDayOnly(_ day: Date, now: Date, calendar: Calendar = .current) -> Date {
        let morning = at(hour: dayOnlyHour, minute: 0, on: day, calendar: calendar)
        if morning > now { return morning }
        let slot = nextSlot(after: now, calendar: calendar)
        if calendar.isDate(slot, inSameDayAs: now) { return slot }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return at(hour: dayOnlyHour, minute: 0, on: tomorrow, calendar: calendar)
    }

    /// The calendar day of `day` with the hour and minute of `time` (the popover's day and time
    /// controls write through this so neither loses the other's half).
    static func compose(day: Date, time: Date, calendar: Calendar = .current) -> Date {
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        return at(hour: clock.hour ?? 0, minute: clock.minute ?? 0, on: day, calendar: calendar)
    }

    /// `hour:minute` on the day of `day`. Built from components rather than
    /// `date(bySettingHour:…, matchingPolicy: .nextTime)`: on a spring-forward day the latter
    /// snaps a skipped 02:30 to 03:00, components shift it by the gap to 03:30 (what a wall clock
    /// would show). A repeated autumn time takes its first occurrence either way.
    static func at(hour: Int, minute: Int, on day: Date, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.era, .year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = 0
        if let date = calendar.date(from: components) { return date }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day,
                             matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward) ?? day
    }
}

/// Day-part hours shared by the parser ("morning", "večer", "tonight") and the presets, so a typed
/// "tomorrow evening" and the This Evening preset can never drift apart.
enum DayPart {
    static let morningHour = 9
    static let afternoonHour = 15
    static let eveningHour = 19
    /// "tonight" / "night" — later than the evening preset on purpose (see `DatePreset.evening`).
    static let nightHour = 20
}

/// "Now" for the UI. `QR_NOW=2026-10-23T10:00` (local time, or any ISO 8601 date with a zone)
/// shifts the clock for deterministic screenshots and E2E runs; time still advances from there.
/// Read once, like `QR_TEXT_SCALE`.
enum AppClock {
    static var now: Date { Date().addingTimeInterval(offset) }

    private static let offset: TimeInterval = {
        guard let raw = ProcessInfo.processInfo.environment["QR_NOW"],
              let forced = parse(raw) else { return 0 }
        return forced.timeIntervalSinceNow
    }()

    /// Accepts `yyyy-MM-dd'T'HH:mm` (local) or a full ISO 8601 timestamp.
    static func parse(_ raw: String, timeZone: TimeZone = .current) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) { return date }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = timeZone
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm"] {
            local.dateFormat = format
            if let date = local.date(from: raw) { return date }
        }
        return nil
    }
}
