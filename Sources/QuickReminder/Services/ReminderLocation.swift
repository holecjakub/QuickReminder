import Foundation

/// A place picked from Apple Maps' suggestions: what Reminders needs for a real location
/// (`EKStructuredLocation`) and a "When arriving / When leaving" alarm.
struct PickedPlace: Equatable, Sendable {
    /// The map item's name ("Café Slavia"); the field shows it once picked.
    var name: String
    /// One-line address, when Apple Maps has one ("Smetanovo nábřeží 1012/2, Praha").
    var address: String?
    var latitude: Double
    var longitude: Double
}

/// Reminders' location alarm: alert when arriving at the place or when leaving it.
enum LocationProximity: String, CaseIterable, Sendable {
    case arriving, leaving

    var title: String {
        switch self {
        case .arriving: "Arriving"
        case .leaving: "Leaving"
        }
    }

    /// For labels: "when arriving", "when leaving".
    var phrase: String { "when \(rawValue)" }
}

/// The reminder's location as edited in the panel (both styles): the typed text, the place picked
/// from Apple Maps (if any) and Arriving / Leaving.
///
/// The pick holds only while the text is the picked place's name: typing over it turns the
/// location back into free text, which is saved as the `📍 …` note line.
struct ReminderLocation: Equatable, Sendable {
    var text: String {
        didSet { if let place, place.name != text { self.place = nil } }
    }
    private(set) var place: PickedPlace?
    var proximity: LocationProximity

    init(text: String = "", proximity: LocationProximity = .arriving) {
        self.text = text
        self.place = nil
        self.proximity = proximity
    }

    /// Picking a suggestion writes its name into the field and keeps the place.
    mutating func pick(_ place: PickedPlace) {
        self.place = nil
        text = place.name
        self.place = place
    }

    /// Clear: no location; the Arriving / Leaving choice stays.
    mutating func clear() {
        text = ""
        place = nil
    }

    var isEmpty: Bool { text.isEmpty }
}

/// What a location alarm is made of; `RemindersService` turns it into an `EKAlarm` with an
/// `EKStructuredLocation`.
struct LocationAlarmSpec: Equatable, Sendable {
    /// `EKStructuredLocation.title`: the name, and the address when it adds something.
    var title: String
    var latitude: Double
    var longitude: Double
    /// Geofence radius in metres.
    var radius: Double
    var proximity: LocationProximity
}

/// How the reminder's location is saved. A picked place becomes a real Reminders location (a
/// structured location on a proximity alarm) and adds no note line; free text, which has no
/// coordinates and so cannot trigger an alarm, stays the `📍 …` line in Notes.
enum LocationSavePlan: Equatable, Sendable {
    case none
    /// The trimmed text for the `📍 …` note line.
    case noteLine(String)
    case structured(LocationAlarmSpec)

    /// Around a building: Reminders' own location alarms work at about this size, and region
    /// monitoring is not reliable much below it.
    static let radius: Double = 100

    static func plan(for location: ReminderLocation?) -> LocationSavePlan {
        guard let location else { return .none }
        if let place = location.place {
            return .structured(LocationAlarmSpec(title: title(for: place), latitude: place.latitude,
                                                 longitude: place.longitude, radius: radius,
                                                 proximity: location.proximity))
        }
        let trimmed = location.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .none : .noteLine(trimmed)
    }

    /// "Café Slavia, Smetanovo nábřeží 2, Praha". An address result's name is usually the start of
    /// its address ("Dukelských hrdinů 47" → "Dukelských hrdinů 47, Praha 7"): the address alone.
    static func title(for place: PickedPlace) -> String {
        let name = place.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let address = place.address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty else {
            return name
        }
        if name.isEmpty || address.hasPrefix(name) { return address }
        if name.hasPrefix(address) { return name }
        return "\(name), \(address)"
    }

    /// The note line's text, if this plan writes one.
    var noteLineText: String? {
        if case .noteLine(let text) = self { return text }
        return nil
    }
}
