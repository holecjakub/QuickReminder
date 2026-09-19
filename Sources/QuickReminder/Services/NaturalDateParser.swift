import Foundation

/// A date/time phrase recognised inside a piece of free text, together with the
/// absolute date it resolves to and the exact range it occupied in the original string.
struct DateSuggestion: Equatable, Sendable {
    /// The resolved absolute date/time.
    let date: Date
    /// `false` when only a day was recognised — the caller is expected to apply its own
    /// default time of day (9:00) in that case.
    let hasTime: Bool
    /// Range of the phrase inside the ORIGINAL text.
    let matchedRange: Range<String.Index>
    /// The phrase exactly as the user typed it, e.g. "tomorrow at 2pm", "zítra ve 14:00".
    let matchedText: String
}

/// Reminders-style natural language date parser for English and Czech.
///
/// Design notes / documented simplifications:
///
/// * Matching is case-insensitive and diacritics-insensitive, so "zitra" == "zítra".
///   The text is folded into a parallel string with an identical UTF-16 length, the
///   regular expressions run over that, and ranges are mapped back by UTF-16 offset.
/// * **"next X" == "X"**: both `friday` and `next friday` resolve to the next occurrence
///   *strictly after* today. The same holds for Czech `pátek` / `příští pátek`. This keeps
///   the behaviour predictable; the "the friday after the coming one" reading is not implemented.
/// * **Bare numbers are never times.** `at 2` needs `at` / `v` / `ve`, or am/pm, or a
///   `:`/`.` minute separator, or a Czech day-part suffix ("v 8 ráno"). So "buy 2 apples",
///   "iPhone 17" and "call 5 people" produce no match.
/// * **Ambiguous hours**: without am/pm or a day-part word, hours 1…6 are read as PM
///   ("at 3" → 15:00, "v půl třetí" → 14:30) while 7…12 are taken literally ("at 9" → 09:00).
///   An adjacent evening/afternoon day part overrides that for a bare hour below 12, so
///   "tonight at 8" is 20:00. Hour 12 is left alone even next to an evening word — "v 12 večer"
///   stays 12:00, because both readings (noon, midnight) are guesses and noon is the safer one.
/// * **Slash dates** (`3/12`) are read as month/day for English text and day/month when the
///   text carries Czech signals (Czech diacritics or a Czech word). Dotted dates (`3.12.`)
///   are always day/month.
/// * **Invalid calendar dates never roll over.** "31. února" / "30.2." produce no match at all
///   instead of silently becoming March. "29.2." with no year walks forward to the next leap
///   year (2028). A written-out year must be a `20xx` within ±10 years of `now`, so
///   "12 March 1000 items" reads as a plain March 12 and "1000" stays in the title.
/// * **Missing year** → the first valid occurrence from this year up to +8 years that is not
///   in the past.
/// * **Time without a day** that already lies in the past today rolls over to tomorrow.
/// * Day-sized relative offsets ("in 3 days", "za týden") return the start of that day with
///   `hasTime == false`; hour/minute offsets keep the exact time. A day-sized offset merges
///   with an adjacent time ("in 2 days at 3pm").
/// * Only the RIGHT-MOST phrase is returned, so "Call mom tomorrow 2pm" strips the tail.
///   A time only merges with a day that is directly ADJACENT to it, so in "tomorrow buy milk
///   at 2pm" the 2pm is resolved on its own (today/tomorrow by clock) and "tomorrow" stays in
///   the title. Keeping the merge strictly adjacent is what makes the stripped title predictable.
enum NaturalDateParser {

    // MARK: - Public API

    /// Finds the LAST (right-most) date/time phrase in `text`. Returns nil if none.
    /// Only the right-most phrase matters, and the parser runs on every keystroke on the main
    /// thread, so pathological pastes are cut off instead of stalling the UI.
    static let maxLengthUTF16 = 1_000

    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> DateSuggestion? {
        guard text.utf16.count <= maxLengthUTF16 else { return nil }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let normalized = normalize(text)
        let czech = looksCzech(original: text, normalized: normalized)

        let offsets = offsetCandidates(normalized, now: now, calendar: calendar)
        let days = dayCandidates(normalized, now: now, calendar: calendar, czech: czech)
            .filter { !overlaps($0.range, offsets) }
        let times = timeCandidates(normalized)
            .filter { !overlaps($0.range, offsets) && !overlaps($0.range, days) }

        let all = (offsets + days + times).sorted { $0.range.location < $1.range.location }
        guard let last = all.last else { return nil }
        let previous: Candidate? = all.count >= 2 ? all[all.count - 2] : nil

        var range = last.range
        var date: Date
        var hasTime: Bool

        switch last.payload {
        case let .offset(resolved, offsetHasTime):
            date = resolved
            hasTime = offsetHasTime

        case let .time(time):
            if let previous, adjacent(previous.range, range, in: normalized),
               let day = dayBase(of: previous.payload, calendar: calendar) {
                range = union(previous.range, range)
                date = merge(time, with: day, calendar: calendar)
            } else {
                date = timeOnly(time, now: now, calendar: calendar)
            }
            hasTime = true

        case let .day(day):
            if let previous, case let .time(time) = previous.payload, adjacent(previous.range, range, in: normalized) {
                range = union(previous.range, range)
                date = merge(time, with: day, calendar: calendar)
                hasTime = true
            } else if let implied = day.impliedTime {
                date = apply(implied, to: day.startOfDay, calendar: calendar)
                hasTime = true
            } else {
                date = day.startOfDay
                hasTime = false
            }
        }

        guard let swiftRange = Range(range, in: text) else { return nil }
        return DateSuggestion(date: date,
                              hasTime: hasTime,
                              matchedRange: swiftRange,
                              matchedText: String(text[swiftRange]))
    }

    /// Returns `text` with the matched phrase removed and whitespace collapsed.
    ///
    /// Only the single word directly BEFORE the removed range is dropped, and only when it is a
    /// preposition left dangling by the removal ("Review this by friday" → "Review this",
    /// "odevzdat do 5. prosince" → "odevzdat"). Words that carry meaning in a title — "this",
    /// "the", "next", "in" — are always kept, so "check in tomorrow" stays "check in".
    /// Punctuation orphaned by the removal is dropped as well: "Buy milk, tomorrow" → "Buy milk".
    static func removingMatch(from text: String, suggestion: DateSuggestion) -> String {
        let head = String(text[text.startIndex..<suggestion.matchedRange.lowerBound])
        var tail = Substring(text[suggestion.matchedRange.upperBound...])

        // "ve 14.30." leaves a lone "." behind; so does "tomorrow, buy milk".
        while let first = tail.first, first.isWhitespace || danglingPunctuation.contains(first) {
            tail.removeFirst()
        }

        var words = head.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if let last = words.last {
            let bare = bareWord(last)
            if bare.isEmpty || danglingPrepositions.contains(normalize(bare)) { words.removeLast() }
        }
        words += tail.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        if let last = words.last {
            let trimmed = trimmingTrailingPunctuation(last)
            if trimmed.isEmpty { words.removeLast() } else { words[words.count - 1] = trimmed }
        }

        return words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Internal model

    private struct TimeInfo {
        var hour: Int
        var minute: Int
        /// `false` only for a bare hour ("at 8") that nothing in the phrase pinned down —
        /// no am/pm, no minutes, no day-part suffix. Such an hour may still be pushed into
        /// the evening by an adjacent day part ("tonight at 8" → 20:00).
        var explicit: Bool = true
    }

    private struct DayInfo {
        var startOfDay: Date
        var impliedTime: TimeInfo?
    }

    private struct Candidate {
        enum Payload {
            case day(DayInfo)
            case time(TimeInfo)
            case offset(Date, Bool)
        }
        var range: NSRange
        var payload: Payload
    }

    // MARK: - Normalisation

    /// Lowercases and strips diacritics while guaranteeing the UTF-16 length is preserved,
    /// so ranges found in the normalised string are valid in the original one.
    private static func normalize(_ text: String) -> String {
        // Fast path: fold the whole string at once; fall back to per-character folding only when
        // some character would change its UTF-16 length (the range mapping depends on it).
        // Equal totals only prove 1:1 alignment when nothing can shrink (e.g. a decomposed
        // accent, 2 → 1) while something else grows (ß → ss): so require one UTF-16 unit per
        // Character before trusting the whole-string fold.
        if text.utf16.count == text.count {
            let whole = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            if whole.utf16.count == text.utf16.count { return whole }
        }
        var out = String()
        out.reserveCapacity(text.count)
        for character in text {
            let source = String(character)
            let folded = source.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            out += folded.utf16.count == source.utf16.count ? folded : source.lowercased()
        }
        return out
    }

    private static let danglingPunctuation: Set<Character> = [
        ",", ".", ";", ":", "!", "?", "-", "–", "—", "(", ")", "[", "]", "{", "}", "\"", "'"
    ]

    /// Words that are meaningless on their own once the date phrase after them is gone.
    /// Deliberately NO determiners or adverbs ("the", "this", "next", "in", "tento", "příští"):
    /// those are ordinary title words and removing them mangled titles like "check in tomorrow".
    private static let danglingPrepositions: Set<String> = [
        "at", "on", "by", "for", "until", "till",
        "v", "ve", "o", "do", "na", "za", "od"
    ]

    private static func bareWord(_ word: String) -> String {
        var slice = Substring(word)
        while let first = slice.first, danglingPunctuation.contains(first) { slice.removeFirst() }
        while let last = slice.last, danglingPunctuation.contains(last) { slice.removeLast() }
        return String(slice)
    }

    private static func trimmingTrailingPunctuation(_ word: String) -> String {
        var trimmed = Substring(word)
        while let last = trimmed.last, danglingPunctuation.contains(last) { trimmed.removeLast() }
        return String(trimmed)
    }

    private static let czechHintWords: Set<String> = [
        "zitra", "zejtra", "dnes", "dneska", "pozitri", "vcera",
        "tyden", "tydne", "tydnu", "tydny", "mesic", "mesice",
        "hodina", "hodinu", "hodiny", "hodin", "minuta", "minutu", "minuty", "minut",
        "rano", "vecer", "vecera", "odpoledne", "dopoledne", "poledne", "pulnoc", "pulnoci", "pul",
        "pondeli", "pondelek", "utery", "streda", "stredu", "ctvrtek", "patek",
        "sobota", "sobotu", "nedele", "nedeli", "vikend", "vikendu",
        "pristi", "tento", "tuto", "ve", "za", "schuzka", "zubar", "lekar", "koupit", "zavolat", "napsat"
    ]

    private static let czechDiacritics = Set("áčďéěíňóřšťúůýžÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ")

    private static func looksCzech(original: String, normalized: String) -> Bool {
        if original.contains(where: { czechDiacritics.contains($0) }) { return true }
        let words = normalized.split(whereSeparator: { !$0.isLetter })
        return words.contains { czechHintWords.contains(String($0)) }
    }

    // MARK: - Regex helpers

    private static func makeRegex(_ pattern: String) -> NSRegularExpression {
        // Patterns are compile-time constants; a failure here is a programming error.
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: pattern, options: [])
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> [NSTextCheckingResult] {
        let full = NSRange(location: 0, length: text.utf16.count)
        return regex.matches(in: text, options: [], range: full)
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        guard index < match.numberOfRanges else { return nil }
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    private static func overlaps(_ range: NSRange, _ others: [Candidate]) -> Bool {
        others.contains { NSIntersectionRange($0.range, range).length > 0 }
    }

    private static func dedupe(_ items: [Candidate]) -> [Candidate] {
        let sorted = items.sorted { lhs, rhs in
            if lhs.range.location != rhs.range.location { return lhs.range.location < rhs.range.location }
            return lhs.range.length > rhs.range.length
        }
        var result: [Candidate] = []
        for candidate in sorted {
            if result.contains(where: { NSIntersectionRange($0.range, candidate.range).length > 0 }) { continue }
            result.append(candidate)
        }
        return result
    }

    private static func union(_ lhs: NSRange, _ rhs: NSRange) -> NSRange {
        let location = min(lhs.location, rhs.location)
        let end = max(lhs.location + lhs.length, rhs.location + rhs.length)
        return NSRange(location: location, length: end - location)
    }

    /// True when only whitespace / a comma separates the two ranges.
    private static func adjacent(_ lhs: NSRange, _ rhs: NSRange, in normalized: String) -> Bool {
        let start = lhs.location + lhs.length
        let length = rhs.location - start
        guard length >= 0, length <= 3 else { return false }
        let gapRange = NSRange(location: start, length: length)
        guard let swiftRange = Range(gapRange, in: normalized) else { return false }
        return normalized[swiftRange].allSatisfy { $0.isWhitespace || $0 == "," }
    }

    // MARK: - Word lists

    private static let boundaryBefore = "(?<![\\p{L}])"
    private static let boundaryAfter = "(?![\\p{L}])"

    private static let weekdayNumbers: [String: Int] = [
        "sunday": 1, "sun": 1, "nedele": 1, "nedeli": 1,
        "monday": 2, "mon": 2, "pondeli": 2, "pondelek": 2,
        "tuesday": 3, "tues": 3, "tue": 3, "utery": 3, "uterek": 3,
        "wednesday": 4, "weds": 4, "wed": 4, "streda": 4, "stredu": 4,
        "thursday": 5, "thurs": 5, "thur": 5, "thu": 5, "ctvrtek": 5,
        "friday": 6, "fri": 6, "patek": 6,
        "saturday": 7, "sat": 7, "sobota": 7, "sobotu": 7
    ]

    private static let monthNumbers: [String: Int] = [
        "january": 1, "jan": 1, "ledna": 1, "leden": 1,
        "february": 2, "feb": 2, "unora": 2, "unor": 2,
        "march": 3, "mar": 3, "brezna": 3, "brezen": 3,
        "april": 4, "apr": 4, "dubna": 4, "duben": 4,
        "may": 5, "kvetna": 5, "kveten": 5,
        "june": 6, "jun": 6, "cervna": 6, "cerven": 6,
        "july": 7, "jul": 7, "cervence": 7, "cervenec": 7,
        "august": 8, "aug": 8, "srpna": 8, "srpen": 8,
        "september": 9, "sept": 9, "sep": 9, "zari": 9,
        "october": 10, "oct": 10, "rijna": 10, "rijen": 10,
        "november": 11, "nov": 11, "listopadu": 11, "listopad": 11,
        "december": 12, "dec": 12, "prosince": 12, "prosinec": 12
    ]

    /// Ordered longest-first so the alternation prefers the full word. Full names may stand
    /// alone; three/four-letter abbreviations ("sat", "sun", "mon", "wed" are ordinary words)
    /// only count after a prefix such as "on" / "next".
    private static let weekdayFullAlternation = weekdayNumbers.keys.filter { $0.count > 4 }.sorted { $0.count > $1.count }.joined(separator: "|")
    private static let weekdayAbbrevAlternation = weekdayNumbers.keys.filter { $0.count <= 4 }.sorted { $0.count > $1.count }.joined(separator: "|")
    private static let monthAlternation = monthNumbers.keys.sorted { $0.count > $1.count }.joined(separator: "|")

    private static let czechHalfOrdinals: [String: Int] = [
        "jedne": 1, "druhe": 2, "treti": 3, "ctvrte": 4, "pate": 5, "seste": 6,
        "sedme": 7, "osme": 8, "devate": 9, "desate": 10, "jedenacte": 11, "dvanacte": 12
    ]

    private static let dayPartTimes: [String: TimeInfo] = [
        "rano": TimeInfo(hour: 9, minute: 0),
        "dopoledne": TimeInfo(hour: 10, minute: 0),
        "poledne": TimeInfo(hour: 12, minute: 0),
        "odpoledne": TimeInfo(hour: 15, minute: 0),
        "vecer": TimeInfo(hour: 19, minute: 0),
        "vecera": TimeInfo(hour: 19, minute: 0),
        "pulnoc": TimeInfo(hour: 0, minute: 0),
        "pulnoci": TimeInfo(hour: 0, minute: 0),
        "noon": TimeInfo(hour: 12, minute: 0),
        "midnight": TimeInfo(hour: 0, minute: 0),
        "morning": TimeInfo(hour: 9, minute: 0),
        "afternoon": TimeInfo(hour: 15, minute: 0),
        "evening": TimeInfo(hour: 19, minute: 0),
        "night": TimeInfo(hour: 20, minute: 0)
    ]

    // MARK: - Compiled patterns

    private static let relativeDayRegex = makeRegex(
        boundaryBefore
        + "(?:(?:next|pristi)\\s+(?:weekend|week|tyden|month|mesic)"
        + "|day\\s+after\\s+tomorrow"
        + "|pozitri"
        + "|tomorrow|tmrw|tmr|zitra|zejtra"
        + "|tonight"
        + "|today|dneska|dnes"
        + "|(?:this\\s+|tento\\s+|toto\\s+|o\\s+)?(?:weekend|vikendu|vikend))"
        + boundaryAfter
    )

    private static let weekdayRegex = makeRegex(
        boundaryBefore
        + "(?:"
        + "(?:(?:on|next|this|upcoming|v|ve|pristi|tento|tuto)\\s+)?(" + weekdayFullAlternation + ")"
        + "|(?:on|next|this|upcoming|v|ve|pristi|tento|tuto)\\s+(" + weekdayAbbrevAlternation + ")"
        + ")"
        + boundaryAfter
    )

    /// A written-out year is only accepted in this century; `resolveDate` narrows it further
    /// to ±10 years of `now`, so stray numbers ("12 March 1000 items") never become years.
    private static let yearPattern = "20\\d{2}"

    /// "12.3.", "12. 3.", "12.3.2026"
    private static let dottedDateRegex = makeRegex(
        "(?<![\\p{L}\\d.])(\\d{1,2})\\.\\s?(\\d{1,2})\\.(?:\\s?(" + yearPattern + "))?(?![\\d])"
    )

    /// "3/12", "3/12/2026"
    private static let slashDateRegex = makeRegex(
        "(?<![\\p{L}\\d/])(\\d{1,2})/(\\d{1,2})(?:/(" + yearPattern + "))?(?![\\d/])"
    )

    /// "12 March", "12. března", "12 March 2027"
    private static let dayMonthRegex = makeRegex(
        "(?<![\\p{L}\\d])(\\d{1,2})\\.?\\s+(" + monthAlternation + ")" + boundaryAfter
        + "(?:\\s+(" + yearPattern + ")(?!\\d))?"
    )

    /// "March 12", "Mar 12th", "March 12, 2027"
    private static let monthDayRegex = makeRegex(
        boundaryBefore + "(" + monthAlternation + ")\\s+(\\d{1,2})(?:st|nd|rd|th)?(?![\\p{L}\\d])"
        + "(?:,?\\s+(" + yearPattern + ")(?!\\d))?"
    )

    private static let timeWordRegex = makeRegex(
        boundaryBefore
        + "(?:in\\s+the\\s+(morning|afternoon|evening)"
        + "|(?:at\\s+)?(noon|midnight)"
        + "|(?:v\\s+)?(poledne)"
        + "|(?:o\\s+)?(pulnoci|pulnoc)"
        + "|(rano|dopoledne|odpoledne|vecera|vecer)"
        + "|(morning|afternoon|evening|night))"
        + boundaryAfter
    )

    /// The day-part suffix shared by the numeric and half-hour time patterns ("ve 2 odpoledne",
    /// "půl třetí odpoledne", "at 3 in the afternoon").
    private static let dayPartSuffixPattern =
        "(rano|dopoledne|odpoledne|vecera|vecer|morning|afternoon|evening|night"
        + "|in\\s+the\\s+morning|in\\s+the\\s+afternoon|in\\s+the\\s+evening)" + boundaryAfter

    /// "v půl třetí", "půl třetí odpoledne" → 14:30
    private static let halfHourRegex = makeRegex(
        boundaryBefore + "(?:v\\s+)?pul\\s+(" + czechHalfOrdinals.keys.sorted { $0.count > $1.count }.joined(separator: "|") + ")" + boundaryAfter
        + "(?:\\s+" + dayPartSuffixPattern + ")?"
    )

    /// 1: at/v/ve  2: hour  3: minutes after ':'  4: minutes after '.'  5: am/pm  6: day-part suffix
    ///
    /// The minute lookahead `(?!\d|\.\d)` tolerates a sentence-final period ("ve 14.30.") while
    /// still refusing the middle of a dotted date ("12.30.2026").
    private static let numericTimeRegex = makeRegex(
        "(?<![\\p{L}\\d])(?:(at|v|ve)\\s+)?(\\d{1,2})(?::(\\d{2})|\\.(\\d{2})(?!\\d|\\.\\d))?(?!\\d)"
        + "(?:\\s*(am|pm)(?![\\p{L}]))?"
        + "(?:\\s+" + dayPartSuffixPattern + ")?"
    )

    private static let englishOffsetRegex = makeRegex(
        boundaryBefore + "in\\s+(?:(\\d{1,3})|an|a)\\s+(hours|hour|hrs|hr|minutes|minute|mins|min|days|day|weeks|week|months|month)" + boundaryAfter
    )

    private static let czechOffsetRegex = makeRegex(
        boundaryBefore + "za\\s+(?:(\\d{1,3})\\s+)?(hodinu|hodiny|hodin|minutu|minuty|minut|dny|dni|dnu|den|tydny|tydnu|tyden|mesice|mesicu|mesic)" + boundaryAfter
    )

    // MARK: - Day candidates

    private static func dayCandidates(_ text: String, now: Date, calendar: Calendar, czech: Bool) -> [Candidate] {
        var found: [Candidate] = []

        for match in matches(relativeDayRegex, text) {
            guard let phrase = group(match, 0, in: text) else { continue }
            if let info = relativeDay(phrase, now: now, calendar: calendar) {
                found.append(Candidate(range: match.range, payload: .day(info)))
            }
        }

        for match in matches(weekdayRegex, text) {
            guard let name = group(match, 1, in: text) ?? group(match, 2, in: text),
                  let weekday = weekdayNumbers[name] else { continue }
            let start = nextWeekday(weekday, after: now, calendar: calendar)
            found.append(Candidate(range: match.range, payload: .day(DayInfo(startOfDay: start, impliedTime: nil))))
        }

        for match in matches(dottedDateRegex, text) {
            guard let day = group(match, 1, in: text).flatMap(Int.init),
                  let month = group(match, 2, in: text).flatMap(Int.init) else { continue }
            let year = group(match, 3, in: text).flatMap(Int.init)
            if let date = resolveDate(day: day, month: month, year: year, now: now, calendar: calendar) {
                found.append(Candidate(range: match.range, payload: .day(DayInfo(startOfDay: date, impliedTime: nil))))
            }
        }

        for match in matches(slashDateRegex, text) {
            guard let first = group(match, 1, in: text).flatMap(Int.init),
                  let second = group(match, 2, in: text).flatMap(Int.init) else { continue }
            let year = group(match, 3, in: text).flatMap(Int.init)
            let day = czech ? first : second
            let month = czech ? second : first
            if let date = resolveDate(day: day, month: month, year: year, now: now, calendar: calendar) {
                found.append(Candidate(range: match.range, payload: .day(DayInfo(startOfDay: date, impliedTime: nil))))
            }
        }

        for match in matches(dayMonthRegex, text) {
            guard let day = group(match, 1, in: text).flatMap(Int.init),
                  let name = group(match, 2, in: text), let month = monthNumbers[name] else { continue }
            let year = group(match, 3, in: text).flatMap(Int.init)
            if let date = resolveDate(day: day, month: month, year: year, now: now, calendar: calendar) {
                found.append(Candidate(range: match.range, payload: .day(DayInfo(startOfDay: date, impliedTime: nil))))
            }
        }

        for match in matches(monthDayRegex, text) {
            guard let name = group(match, 1, in: text), let month = monthNumbers[name],
                  let day = group(match, 2, in: text).flatMap(Int.init) else { continue }
            let year = group(match, 3, in: text).flatMap(Int.init)
            if let date = resolveDate(day: day, month: month, year: year, now: now, calendar: calendar) {
                found.append(Candidate(range: match.range, payload: .day(DayInfo(startOfDay: date, impliedTime: nil))))
            }
        }

        return dedupe(found)
    }

    private static func relativeDay(_ phrase: String, now: Date, calendar: Calendar) -> DayInfo? {
        let today = calendar.startOfDay(for: now)
        func shifted(_ days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: today) ?? today }

        if phrase.contains("month") || phrase.contains("mesic") {
            var components = calendar.dateComponents([.year, .month], from: today)
            components.day = 1
            guard let firstOfThisMonth = calendar.date(from: components),
                  let firstOfNextMonth = calendar.date(byAdding: .month, value: 1, to: firstOfThisMonth) else { return nil }
            return DayInfo(startOfDay: firstOfNextMonth, impliedTime: nil)
        }
        if phrase.contains("weekend") || phrase.contains("vikend") {
            return DayInfo(startOfDay: nextWeekday(7, after: now, calendar: calendar), impliedTime: nil)
        }
        if phrase.contains("week") || phrase.contains("tyden") {
            return DayInfo(startOfDay: nextWeekday(2, after: now, calendar: calendar), impliedTime: nil)
        }
        if phrase.contains("day after tomorrow") || phrase.contains("pozitri") {
            return DayInfo(startOfDay: shifted(2), impliedTime: nil)
        }
        if phrase.contains("tomorrow") || phrase.contains("tmrw") || phrase.contains("tmr")
            || phrase.contains("zitra") || phrase.contains("zejtra") {
            return DayInfo(startOfDay: shifted(1), impliedTime: nil)
        }
        if phrase.contains("tonight") {
            return DayInfo(startOfDay: today, impliedTime: TimeInfo(hour: 20, minute: 0))
        }
        if phrase.contains("today") || phrase.contains("dnes") {
            return DayInfo(startOfDay: today, impliedTime: nil)
        }
        return nil
    }

    private static func nextWeekday(_ weekday: Int, after now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        let current = calendar.component(.weekday, from: today)
        var delta = (weekday - current + 7) % 7
        if delta == 0 { delta = 7 }
        return calendar.date(byAdding: .day, value: delta, to: today) ?? today
    }

    /// How far ahead a day/month with no year may look for a valid occurrence — enough to reach
    /// the next leap day from any starting year ("29.2." → 2028-02-29).
    private static let yearSearchSpan = 8
    /// How far a written-out year may sit from today before it is treated as a stray number.
    private static let yearWindow = 10

    /// Resolves a day/month(/year) triple, or nil when the combination is not a real date.
    /// The components are round-tripped through the calendar so "31. února" is rejected rather
    /// than silently rolled over into March.
    private static func resolveDate(day: Int, month: Int, year: Int?, now: Date, calendar: Calendar) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let today = calendar.startOfDay(for: now)
        let thisYear = calendar.component(.year, from: today)

        func exactDate(in year: Int) -> Date? {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            guard let date = calendar.date(from: components) else { return nil }
            let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
            guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else { return nil }
            return calendar.startOfDay(for: date)
        }

        if let year {
            guard abs(year - thisYear) <= yearWindow, let date = exactDate(in: year), date >= today else { return nil }
            return date
        }

        for offset in 0...yearSearchSpan {
            if let candidate = exactDate(in: thisYear + offset), candidate >= today { return candidate }
        }
        return nil
    }

    // MARK: - Time candidates

    private static func timeCandidates(_ text: String) -> [Candidate] {
        var found: [Candidate] = []

        for match in matches(numericTimeRegex, text) {
            let prefix = group(match, 1, in: text)
            guard let hourText = group(match, 2, in: text), var hour = Int(hourText) else { continue }
            let minuteText = group(match, 3, in: text) ?? group(match, 4, in: text)
            let meridiem = group(match, 5, in: text)
            let suffix = group(match, 6, in: text)

            // A bare number is never a time.
            guard prefix != nil || meridiem != nil || minuteText != nil || suffix != nil else { continue }
            let minute = minuteText.flatMap(Int.init) ?? 0
            guard minute < 60, hour <= 23 else { continue }

            if let meridiem {
                guard hour >= 1, hour <= 12 else { continue }
                if meridiem == "pm" { hour = hour == 12 ? 12 : hour + 12 }
                if meridiem == "am" { hour = hour == 12 ? 0 : hour }
            } else if let suffix {
                hour = shifted(hour, by: suffix)
            } else {
                hour = disambiguate(hour)
            }
            guard hour <= 23 else { continue }
            let explicit = meridiem != nil || minuteText != nil || suffix != nil
            found.append(Candidate(range: match.range,
                                   payload: .time(TimeInfo(hour: hour, minute: minute, explicit: explicit))))
        }

        for match in matches(halfHourRegex, text) {
            guard let name = group(match, 1, in: text), let ordinal = czechHalfOrdinals[name] else { continue }
            // "půl jedné" is half past twelve, otherwise "půl N" is half past N-1.
            var hour = ordinal == 1 ? 12 : disambiguate(ordinal - 1)
            if let suffix = group(match, 2, in: text) { hour = shifted(hour, by: suffix) }
            found.append(Candidate(range: match.range, payload: .time(TimeInfo(hour: hour, minute: 30))))
        }

        for match in matches(timeWordRegex, text) {
            var key: String?
            for index in 1..<match.numberOfRanges where key == nil {
                key = group(match, index, in: text)
            }
            guard let key, let time = dayPartTimes[key] else { continue }
            found.append(Candidate(range: match.range, payload: .time(time)))
        }

        return dedupe(found)
    }

    /// Hours 1…6 without am/pm are read as the afternoon; 0 and 7…23 are taken literally.
    private static func disambiguate(_ hour: Int) -> Int {
        (1...6).contains(hour) ? hour + 12 : hour
    }

    /// Maps a day-part suffix ("odpoledne", "in the evening", "night") onto its table key.
    private static func dayPartKey(_ suffix: String) -> String? {
        for key in ["afternoon", "evening", "morning", "night"] where suffix.contains(key) {
            switch key {
            case "afternoon": return "odpoledne"
            case "evening", "night": return "vecer"
            default: return "rano"
            }
        }
        return dayPartTimes[suffix] != nil ? suffix : nil
    }

    /// "ve 2 odpoledne" → 14. Hour 12 is left alone: see the type doc.
    private static func shifted(_ hour: Int, by suffix: String) -> Int {
        guard let key = dayPartKey(suffix), let part = dayPartTimes[key] else { return hour }
        return (part.hour >= 12 && hour < 12) ? hour + 12 : hour
    }

    /// The day a time candidate can attach itself to, if the neighbouring candidate offers one.
    private static func dayBase(of payload: Candidate.Payload, calendar: Calendar) -> DayInfo? {
        switch payload {
        case let .day(day):
            return day
        case let .offset(date, hasTime):
            // "in 2 days at 3pm": a day-sized offset is just a day, so it merges like one.
            return hasTime ? nil : DayInfo(startOfDay: calendar.startOfDay(for: date), impliedTime: nil)
        case .time:
            return nil
        }
    }

    /// Applies a time to a day, letting an evening/afternoon day part disambiguate a bare hour.
    private static func merge(_ time: TimeInfo, with day: DayInfo, calendar: Calendar) -> Date {
        var time = time
        if !time.explicit, time.hour < 12, let implied = day.impliedTime, implied.hour >= 12 {
            time.hour += 12
        }
        return apply(time, to: day.startOfDay, calendar: calendar)
    }

    /// Uses `bySettingHour` so a time that does not exist on a DST spring-forward day moves to the
    /// next valid instant instead of collapsing back to midnight.
    private static func apply(_ time: TimeInfo, to day: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day,
                      matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward) ?? day
    }

    private static func timeOnly(_ time: TimeInfo, now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        let candidate = apply(time, to: today, calendar: calendar)
        if candidate > now { return candidate }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return apply(time, to: tomorrow, calendar: calendar)
    }

    // MARK: - Relative offsets

    private static func offsetCandidates(_ text: String, now: Date, calendar: Calendar) -> [Candidate] {
        var found: [Candidate] = []

        func append(_ match: NSTextCheckingResult, amount: Int, unit: String) {
            guard let candidate = offsetDate(amount: amount, unit: unit, now: now, calendar: calendar) else { return }
            found.append(Candidate(range: match.range, payload: .offset(candidate.0, candidate.1)))
        }

        for match in matches(englishOffsetRegex, text) {
            let amount = group(match, 1, in: text).flatMap(Int.init) ?? 1
            guard let unit = group(match, 2, in: text) else { continue }
            append(match, amount: amount, unit: unit)
        }
        for match in matches(czechOffsetRegex, text) {
            let amount = group(match, 1, in: text).flatMap(Int.init) ?? 1
            guard let unit = group(match, 2, in: text) else { continue }
            append(match, amount: amount, unit: unit)
        }

        return dedupe(found)
    }

    private static func offsetDate(amount: Int, unit: String, now: Date, calendar: Calendar) -> (Date, Bool)? {
        let component: Calendar.Component
        var keepsTime = true
        var value = amount

        switch true {
        case unit.hasPrefix("hod"), unit.hasPrefix("hour"), unit.hasPrefix("hr"):
            component = .hour
        case unit.hasPrefix("min"):
            component = .minute
        case unit.hasPrefix("day"), unit.hasPrefix("den"), unit.hasPrefix("dn"):
            component = .day
            keepsTime = false
        case unit.hasPrefix("week"), unit.hasPrefix("tyd"):
            component = .day
            keepsTime = false
            value = amount * 7
        case unit.hasPrefix("month"), unit.hasPrefix("mesic"):
            component = .month
            keepsTime = false
        default:
            return nil
        }

        guard let shifted = calendar.date(byAdding: component, value: value, to: now) else { return nil }
        return (keepsTime ? shifted : calendar.startOfDay(for: shifted), keepsTime)
    }
}
